#!/bin/bash
set -euo pipefail

provider=$1
config=$2

case $provider in
  claude)
    payload=$(cat)
    session=$(printf '%s' "$payload" | jq -r .session_id)
    case $(printf '%s' "$payload" | jq -r .hook_event_name) in
      Notification) status=Waiting ;;
      Stop) status=Finished ;;
      UserPromptSubmit) status=Working ;;
    esac
    agent='Claude Code'
    ;;
  codex)
    payload=$3
    session=$(printf '%s' "$payload" | jq -r '."thread-id"')
    status=Finished
    agent=Codex
    ;;
esac

directory=$(dirname "$config")/agent-status
mkdir -p "$directory"
temporary=$(mktemp "$directory/.session.XXXXXX")
trap 'rm -f "$temporary"' EXIT
printf '%s' "$payload" | jq \
  --arg agent "$agent" --arg status "$status" --arg bundle "${__CFBundleIdentifier:-}" \
  '{agent: $agent, project: .cwd, status: $status, bundle: $bundle}' > "$temporary"
mv "$temporary" "$directory/$provider-$session.json"

StableBar --config "$config" --trigger agent > /dev/null
