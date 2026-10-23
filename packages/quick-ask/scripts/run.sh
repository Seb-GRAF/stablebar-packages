#!/bin/bash
# Asks the agent the last question of a conversation, then saves its answer there.
set -uo pipefail

directory=$CONFIG_DIR/quick-ask
scripts=$(cd "$(dirname "$0")" && pwd)
id=$1
conversation=$directory/conversations/$id.json
running=$directory/running
mkdir -p "$directory/workspace"

refresh() {
  if [[ -n ${QUICK_ASK_STABLEBAR:-} ]]; then
    "$QUICK_ASK_STABLEBAR" --trigger quick-ask
  else
    open -g -n -b org.stablebar.app --args --trigger quick-ask
  fi
}

turn() { jq -r --arg key "$1" '.turns[-1][$key] // ""' "$conversation"; }
agent=$(jq -r .agent "$conversation")
question=$(turn question)
model=$(turn model)
effort=$(turn effort)
resume=$(turn resume)

cd "$directory/workspace" || exit
case $agent in
  claude)
    arguments=(-p --safe-mode --tools "" --output-format stream-json --include-partial-messages --verbose)
    if [[ -n $model ]]; then arguments+=(--model "$model"); fi
    # Instant answers without thinking; other efforts let the model think as much as the question needs, and show it.
    if [[ $effort == instant ]]; then
      arguments+=(--effort low --thinking disabled)
    else
      arguments+=(--effort "$effort" --thinking-display summarized)
    fi
    if [[ -n $resume ]]; then arguments+=(--resume "$resume" --fork-session); fi
    claude "${arguments[@]}" -- "$question" > "$running/stream.jsonl" 2> "$running/error" &
    ;;
  codex)
    arguments=(exec)
    if [[ -n $resume ]]; then arguments+=(resume); fi
    arguments+=(--json --skip-git-repo-check -c 'sandbox_mode="read-only"' -c 'model_reasoning_summary="auto"')
    if [[ -n $model ]]; then arguments+=(-m "$model"); fi
    if [[ -n $effort ]]; then arguments+=(-c "model_reasoning_effort=\"$effort\""); fi
    if [[ -n $resume ]]; then arguments+=("$resume"); fi
    codex "${arguments[@]}" -- "$question" > "$running/stream.jsonl" 2> "$running/error" &
    ;;
esac
worker=$!
stopped=false
trap 'stopped=true; kill "$worker" 2>/dev/null' TERM

# Refresh the widget whenever the answer grows.
size=0
while kill -0 "$worker" 2>/dev/null; do
  sleep 0.3
  grown=$(stat -f %z "$running/stream.jsonl")
  if [[ $grown != "$size" ]]; then
    size=$grown
    refresh
  fi
done
wait "$worker"
status=$?

result=$(jq -n -R -f "$scripts/stream.jq" < "$running/stream.jsonl")
if [[ $stopped == false && $status != 0 && $(jq -r '.answer + .error' <<< "$result") == "" ]]; then
  result=$(jq --arg error "$(tail -n 5 "$running/error")" '.error = $error' <<< "$result")
fi
temporary=$(mktemp "$directory/conversations/.conversation.XXXXXX")
jq --argjson result "$result" --argjson stopped "$stopped" '
  .turns[-1] += {answer: $result.answer, thinking: $result.thinking, session: $result.session, error: $result.error, stopped: $stopped}
  | .session = $result.session
' "$conversation" > "$temporary" && mv "$temporary" "$conversation"
rm -rf "$running"
refresh
