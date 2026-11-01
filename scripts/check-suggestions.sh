#!/bin/bash
set -euo pipefail

# Checks suggestions.json, the packages StableBar's setup suggests when it finds a command-line tool
# or an app on the Mac. build-index.sh copies the list into index.json as "suggestions".

file=suggestions.json
problems=()

jq empty "$file" || { echo "$file isn't valid JSON" >&2; exit 1; }

while IFS= read -r problem; do
  problems+=("$problem")
done < <(jq -r '
  def names($pattern): type == "array" and length > 0 and all(.[]; type == "string" and test($pattern));
  if type != "array" then "must be a list of suggestions"
  else
    to_entries[] | "suggestion \(.key + 1)" as $at | .value |
    if type != "object" then "\($at) must be an object"
    else
      (keys - ["when", "packages"] | .[] | "\($at) has an unknown key \"\(.)\""),
      (.packages | if names("^[A-Za-z0-9._-]+$") and (unique | length) == length then empty
        else "\($at): \"packages\" must list package IDs, each once" end),
      (.when | if type != "object" or ((has("tools") or has("apps")) | not)
        then "\($at): \"when\" needs \"tools\" or \"apps\""
        else
          (keys - ["tools", "apps"] | .[] | "\($at) has an unknown key \"when.\(.)\""),
          (if has("tools") and (.tools | names("^[A-Za-z0-9][A-Za-z0-9._+-]*$") | not)
            then "\($at): \"when.tools\" must list command names, such as brew" else empty end),
          (if has("apps") and (.apps | names("^[A-Za-z0-9-]+([.][A-Za-z0-9-]+)+$") | not)
            then "\($at): \"when.apps\" must list bundle IDs, such as com.if.Amphetamine" else empty end)
        end)
    end
  end' "$file")

if (( ${#problems[@]} == 0 )); then
  while IFS= read -r id; do
    dir=packages/$id
    if [[ ! -f $dir/package.json ]]; then
      problems+=("$id isn't a package in packages/")
      continue
    fi
    screenshot=$(jq -r '.screenshot // empty' "$dir/package.json")
    if [[ -z $screenshot || ! -f $dir/$screenshot ]]; then
      problems+=("$id has no preview; setup shows one with each suggestion")
    fi
    while IFS= read -r problem; do
      problems+=("$problem")
    done < <(jq -r --arg id "$id" '
      (select(.kind == "theme") | "\($id) is a theme; setup suggests packages that add widgets"),
      (.settings // {} | to_entries[] | select(.value.default == null)
        | "\($id): the setting \(.key) has no default, so the package needs setting up before it works")
    ' "$dir/package.json")
  done < <(jq -r '[.[].packages[]] | unique[]' "$file")
fi

if (( ${#problems[@]} )); then
  for problem in "${problems[@]}"; do
    echo "$file: $problem" >&2
  done
  exit 1
fi
