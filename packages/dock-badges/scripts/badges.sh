#!/bin/bash
set -euo pipefail

# lsappinfo on macOS 27 no longer returns StatusLabel, so the badge comes from the Dock's AXStatusLabel.
dock_badge() {
  osascript - "$1" 2>/dev/null <<'APPLESCRIPT' || true
on run argv
  tell application "System Events" to tell process "Dock"
    set label to value of attribute "AXStatusLabel" of UI element (item 1 of argv) of list 1
    if label is missing value then return ""
    return label
  end tell
end run
APPLESCRIPT
}

while IFS= read -r app; do
  info=$(lsappinfo info -only StatusLabel -only bundleID -only bundlepath "$app")
  bundle=$(printf '%s\n' "$info" | sed -n 's/^"CFBundleIdentifier"="\([^"]*\)"$/\1/p')
  if [[ -n $bundle ]]; then
    path=$(printf '%s\n' "$info" | sed -n 's/^"LSBundlePath"="\([^"]*\)"$/\1/p')
    badge=$(printf '%s\n' "$info" | sed -n 's/.*"label"="\([^"]*\)".*/\1/p')
  else
    bundle=$(printf '%s\n' "$info" | sed -n 's/^ *bundleID="\([^"]*\)".*/\1/p')
    [[ -n $bundle ]] || continue
    path=$(printf '%s\n' "$info" | sed -n 's/^ *bundle path="\([^"]*\)".*/\1/p')
    badge=$(dock_badge "$app")
  fi
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
