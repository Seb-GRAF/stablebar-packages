#!/bin/bash
set -euo pipefail
shopt -s nullglob

directory=$CONFIG_DIR/quick-ask
scripts=$(dirname "$0")
settings=$(cat "$directory/settings.json" 2>/dev/null || printf '{}')
view=$(cat "$directory/view" 2>/dev/null || printf chat)
current=$(cat "$directory/current" 2>/dev/null || true)
conversation=null
if [[ -n $current && -f $directory/conversations/$current.json ]]; then
  conversation=$(cat "$directory/conversations/$current.json")
fi
live=null
if [[ -f $directory/running/stream.jsonl && $(cat "$directory/running/id" 2>/dev/null) == "$current" ]]; then
  live=$(jq -n -R -f "$scripts/stream.jq" < "$directory/running/stream.jsonl")
fi
files=("$directory"/conversations/*.json)
history='[]'
if (( ${#files[@]} )); then
  history=$(jq -s 'sort_by(-.created) | .[:40]' "${files[@]}")
fi
codex_models='[]'
if [[ -f $HOME/.codex/models_cache.json ]]; then
  codex_models=$(jq '[.models[] | select(.visibility == "list")] | sort_by(.priority)
    | map({title: .display_name, value: .slug, detail: .description, effort: .default_reasoning_level,
           efforts: [.supported_reasoning_levels[].effort]})' "$HOME/.codex/models_cache.json")
fi
codex_setting() { sed -n "s/^$1 *= *\"\(.*\)\"/\1/p" "$HOME/.codex/config.toml" 2>/dev/null | head -n 1; }

jq -n -f "$scripts/status.jq" --argjson settings "$settings" --arg view "$view" --argjson conversation "$conversation" \
  --argjson live "$live" --argjson history "$history" --argjson codexModels "$codex_models" \
  --arg codexDefault "$(codex_setting model)" --arg codexEffort "$(codex_setting model_reasoning_effort)" \
  --arg claudePath "$(command -v claude | sed "s|^$HOME|~|")" --arg codexPath "$(command -v codex | sed "s|^$HOME|~|")"
