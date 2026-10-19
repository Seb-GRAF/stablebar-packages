#!/bin/bash
set -euo pipefail

while IFS= read -r app; do
  info=$(lsappinfo info -only StatusLabel -only bundleID "$app")
  bundle=$(printf '%s\n' "$info" | sed -n 's/^"CFBundleIdentifier"="\([^"]*\)"$/\1/p')
  [[ -n $bundle ]] || continue
  badge=$(printf '%s\n' "$info" | sed -n 's/.*"label"="\([^"]*\)".*/\1/p')
  jq -cn --arg app "$app" --arg bundle "$bundle" --arg badge "$badge" '{app: $app, bundle: $bundle, badge: $badge}'
done < <(printf '%s' "$APPS" | jq -Rrs 'split(",")[] | gsub("^ +| +$"; "") | select(length > 0)') |
  jq -s '
    map(. + {count: (if .badge | test("^[0-9]+$") then .badge | tonumber else 0 end)}) as $apps |
    {
      text: ([$apps[].count] | add // 0 | tostring),
      icon: "app.badge",
      fields: {hint: (if $apps | length == 0 then "No watched apps are running." else "Only numeric badges count toward the total." end)},
      lists: {apps: [$apps[] | {app, bundle, badge: (if .badge == "" then "0" else .badge end)}]}
    }'
