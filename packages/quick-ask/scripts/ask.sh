#!/bin/bash
# jq programs reach jq through update, so their $names are jq's, not the shell's.
# shellcheck disable=SC2016
set -euo pipefail
shopt -s nullglob

directory=$CONFIG_DIR/quick-ask
conversations=$directory/conversations
running=$directory/running
scripts=$(dirname "$0")
mkdir -p "$conversations"
[[ -f $directory/settings.json ]] || printf '{}' > "$directory/settings.json"

setting() { jq -r --arg key "$1" 'getpath($key | split(".")) // ""' "$directory/settings.json"; }
chosen_agent() {
  local agent
  agent=$(setting agent)
  printf '%s' "${agent:-claude}"
}
current() { cat "$directory/current" 2>/dev/null || true; }
update() {
  local file=$1
  shift
  local temporary
  temporary=$(mktemp "$file.XXXXXX")
  jq "$@" "$file" > "$temporary" && mv "$temporary" "$file"
}

# The StableBar running this action, so work that ends later can refresh it.
find_stablebar() {
  local pid=$PPID command
  while (( pid > 1 )); do
    command=$(ps -o comm= -p "$pid")
    if [[ $command == */StableBar ]]; then
      export QUICK_ASK_STABLEBAR=$command
      return
    fi
    pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
  done
}


stop() {
  if [[ -f $running/pid ]]; then
    kill -TERM -- "-$(cat "$running/pid")" 2>/dev/null || true
    for _ in $(seq 50); do
      [[ -d $running ]] || break
      sleep 0.1
    done
  fi
}

# Adds a turn to a conversation, new when `id` is empty, and starts the chosen agent on it in the background. The agent
# resumes its session when it answered the turn before, and otherwise reads the conversation so far.
ask() {
  local question=$1 id=$2 agent effort
  stop
  agent=$(chosen_agent)
  if [[ -z $id ]]; then
    id=$(date +%s)-$RANDOM
    jq -n --arg id "$id" '{id: $id, created: now, turns: []}' > "$conversations/$id.json"
  fi
  effort=$(setting "$agent.effort")
  if [[ $agent == claude ]]; then effort=${effort:-medium}; fi
  update "$conversations/$id.json" --arg question "$question" --arg agent "$agent" --arg model "$(setting "$agent.model")" --arg effort "$effort" '
    (.turns | last) as $previous
    | (($previous.agent // .agent) == $agent and ($previous.session // "") != "") as $resumes
    | .turns += [{question: $question, agent: $agent, model: $model, effort: $effort, answer: "",
        resume: (if $resumes then $previous.session else "" end),
        prompt: (if $resumes or $previous == null then $question else
          "This conversation began with another assistant. Here it is so far:\n\n"
          + (.turns | map("User: \(.question)\n\nAssistant: \(.answer)") | join("\n\n"))
          + "\n\nUser: \($question)" end)}]'
  printf '%s' "$id" > "$directory/current"
  printf chat > "$directory/view"
  mkdir -p "$running"
  printf '%s' "$id" > "$running/id"
  find_stablebar
  set -m
  "$scripts/run.sh" "$id" < /dev/null > /dev/null 2>&1 &
  printf '%s' "$!" > "$running/pid"
}

case $1 in
  choose)
    update "$directory/settings.json" --arg agent "$VALUE" --arg model "$OPTION" --arg effort "$LEVEL" \
      '.agent = $agent | .[$agent].model = $model | .[$agent].effort = $effort'
    ;;
  question)
    [[ -n $VALUE ]] || exit 0
    id=$(current)
    [[ -f $conversations/$id.json ]] || id=""
    ask "$VALUE" "$id"
    ;;
  retry)
    id=$(current)
    stop
    question=$(jq -r '.turns[-1].question' "$conversations/$id.json")
    update "$conversations/$id.json" '.turns |= .[:-1]'
    ask "$question" "$id"
    ;;
  replay)
    ask "$(jq -r '.turns[0].question' "$conversations/$2.json")" ""
    ;;
  star)
    update "$directory/settings.json" --arg agent "$VALUE" --arg model "$OPTION" --arg effort "$LEVEL" --argjson starred "$STARRED" '
      .stars = [(.stars // [])[] | select(.group != $agent or .option != $model)]
        + (if $starred then [{group: $agent, option: $model, level: $effort}] else [] end)'
    ;;
  open)
    printf '%s' "$2" > "$directory/current"
    printf chat > "$directory/view"
    ;;
  delete)
    [[ $(current) != "$2" ]] || : > "$directory/current"
    rm -f "$conversations/$2.json"
    ;;
  clear)
    stop
    rm -f "$conversations"/*.json
    : > "$directory/current"
    ;;
  new)
    : > "$directory/current"
    printf chat > "$directory/view"
    ;;
  stop)
    stop
    ;;
  copy)
    jq -j --argjson index "$2" '.turns[$index].answer' "$conversations/$(current).json" | pbcopy
    ;;
  view)
    printf '%s' "$2" > "$directory/view"
    ;;
  opened)
    rm -f "$directory/expiry"
    ;;
  closed)
    # A timer starts a new chat only if the popup stayed closed: opening it or closing it again replaces the token.
    rm -f "$directory/expiry"
    [[ $NEW_CHAT_AFTER != Never ]] || exit 0
    token=$RANDOM$RANDOM
    printf '%s' "$token" > "$directory/expiry"
    find_stablebar
    set -m
    (
      sleep $((NEW_CHAT_AFTER * 60))
      [[ $(cat "$directory/expiry" 2>/dev/null) == "$token" && ! -d $running ]] || exit 0
      rm -f "$directory/expiry"
      : > "$directory/current"
      printf chat > "$directory/view"
      "$QUICK_ASK_STABLEBAR" --trigger quick-ask
    ) < /dev/null > /dev/null 2>&1 &
    ;;
esac
