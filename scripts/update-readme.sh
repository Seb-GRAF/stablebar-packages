#!/bin/bash
set -euo pipefail

table=$(
  echo '| Preview | Package | Access |'
  echo '| --- | --- | --- |'
  for dir in packages/*/; do
    dir=${dir%/}
    jq -r --arg dir "$dir" '[
      (if .screenshot then "<img src=\"\($dir)/\(.screenshot)\" width=\"260\" alt=\"\">" else "" end),
      "**[\(.name)](\($dir))**<br>\(.description)",
      ([
        (if .kind then "No commands" else "Runs commands" end),
        (.requires | values | "Needs \(join(", "))"),
        (.permissions | values | "Permissions: \(join(", "))"),
        (.hosts | values | "Contacts \(join(", "))")
      ] | join("<br>"))
    ] | "| \(join(" | ")) |"' "$dir/package.json"
  done
)

TABLE=$table awk '
  /^<!-- \/packages -->$/ { print ENVIRON["TABLE"]; skip = 0 }
  !skip { print }
  /^<!-- packages -->$/ { skip = 1 }
' README.md > README.md.new
mv README.md.new README.md
