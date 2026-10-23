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

stop() {
  if [[ -f $running/pid ]]; then
    kill -TERM -- "-$(cat "$running/pid")" 2>/dev/null || true
    for _ in $(seq 50); do
      [[ -d $running ]] || break
      sleep 0.1
    done
  fi
}

# Adds a turn to a conversation, new when `id` is empty, and starts the agent on it in the background.
ask() {
  local question=$1 id=$2 resume=$3 agent
  stop
  if [[ -n $id ]]; then
    agent=$(jq -r .agent "$conversations/$id.json")
  else
    agent=$(chosen_agent)
  fi
  if [[ -z $id ]]; then
    id=$(date +%s)-$RANDOM
    jq -n --arg id "$id" --arg agent "$agent" '{id: $id, created: now, agent: $agent, turns: []}' > "$conversations/$id.json"
  fi
  local effort
  effort=$(setting "$agent.effort")
  if [[ $agent == claude ]]; then effort=${effort:-medium}; fi
  update "$conversations/$id.json" --arg question "$question" --arg resume "$resume" --arg model "$(setting "$agent.model")" --arg effort "$effort" \
    '.turns += [{question: $question, resume: $resume, model: $model, effort: $effort, answer: ""}]'
  printf '%s' "$id" > "$directory/current"
  printf chat > "$directory/view"
  mkdir -p "$running"
  printf '%s' "$id" > "$running/id"
  # The StableBar running this action, so the agent's progress can refresh it.
  local pid=$PPID command
  while (( pid > 1 )); do
    command=$(ps -o comm= -p "$pid")
    if [[ $command == */StableBar ]]; then
      export QUICK_ASK_STABLEBAR=$command
      break
    fi
    pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
  done
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
    if [[ -n $id && -f $conversations/$id.json && $(jq -r .agent "$conversations/$id.json") == "$(chosen_agent)" ]]; then
      ask "$VALUE" "$id" "$(jq -r '.session // ""' "$conversations/$id.json")"
    else
      ask "$VALUE" "" ""
    fi
    ;;
  retry)
    id=$(current)
    stop
    question=$(jq -r '.turns[-1].question' "$conversations/$id.json")
    update "$conversations/$id.json" '.turns |= .[:-1] | .session = (.turns[-1].session // "")'
    ask "$question" "$id" "$(jq -r '.session' "$conversations/$id.json")"
    ;;
  replay)
    ask "$(jq -r '.turns[0].question' "$conversations/$2.json")" "" ""
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
    jq -j '.turns[-1].answer' "$conversations/$(current).json" | pbcopy
    ;;
  view)
    printf '%s' "$2" > "$directory/view"
    ;;
esac
