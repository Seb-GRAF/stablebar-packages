#!/bin/bash
set -euo pipefail
shopt -s nullglob

files=("$CONFIG_DIR/agent-status/"*.json)
if (( ${#files[@]} )); then
  jq -s '.' "${files[@]}"
else
  printf '[]\n'
fi | jq --arg filter "$SESSIONS" '
  sort_by(.project, .agent) as $sessions |
  ([$sessions[] | select(.status != "Working")] | length) as $waiting |
  {
    text: ($waiting | tostring),
    icon: "terminal",
    state: (if $waiting > 0 then "warning" else null end),
    fields: {hint: (if $sessions | length == 0 then "No sessions reported. Add the hooks in the package README." else "" end)},
    lists: {sessions: [$sessions[] | select($filter == "all" or .status != "Working") | {project, detail: "\(.agent) · \(.status)", bundle}]}
  }'
