#!/bin/bash
set -euo pipefail

while IFS= read -r app; do
  info=$(lsappinfo info -long "$app")
  bundle=$(printf '%s\n' "$info" | sed -n 's/^"CFBundleIdentifier"="\([^"]*\)"$/\1/p')
  [[ -n $bundle ]] || continue
  path=$(printf '%s\n' "$info" | sed -n 's/^"LSBundlePath"="\([^"]*\)"$/\1/p')
  badge=$(printf '%s\n' "$info" | sed -n 's/.*"label"="\([^"]*\)".*/\1/p')
  jq -cn --arg app "$app" --arg bundle "$bundle" --arg path "$path" --arg badge "$badge" '{app: $app, bundle: $bundle, path: $path, badge: $badge}'
done < <(printf '%s' "$APPS" | jq -Rrs 'split(",")[] | gsub("^ +| +$"; "") | select(length > 0)') |
  jq -s '
    map(. + {count: (if .badge | test("^[0-9]+$") then .badge | tonumber else 0 end)}) as $apps |
    ([$apps[].count] | add // 0 | tostring) as $total |
    {
      text: $total,
      icon: "app.badge",
      fields: {total: $total, hint: (if $apps | length == 0 then "No watched apps are running." else "Total counts numeric badges." end)},
      lists: {apps: [$apps[] | {app, bundle, path, badge: (if .badge == "" then "0" else .badge end)}]}
    }'
