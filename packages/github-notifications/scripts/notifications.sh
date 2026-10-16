#!/bin/sh
set -e

json_escape() {
  printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

read_json() {
  printf '%s' "$notifications" | plutil -extract "$1" raw -o - -
}

if [ -z "$GITHUB_TOKEN" ]; then
  printf '{"text":"Set token","icon":"bell.slash","fields":{"hint":"Set your GitHub token in Customize → Packages."}}\n'
  exit 0
fi

notifications=$(curl -fsS --max-time 10 \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/notifications?per_page=50")

count=$(printf '{"count":%s}' "$notifications" | plutil -extract count raw -o - -)

rows=""
i=0
while [ "$i" -lt "$count" ] && [ "$i" -lt 10 ]; do
  repository=$(json_escape "$(read_json "$i.repository.full_name")")
  title=$(json_escape "$(read_json "$i.subject.title")")
  api_url=$(read_json "$i.subject.url" 2>/dev/null || true)
  if [ -n "$api_url" ]; then
    link=$(printf '%s' "$api_url" | sed 's#^https://api.github.com/repos/#https://github.com/#; s#/pulls/#/pull/#; s#/commits/#/commit/#; s#/releases/[0-9]*$#/releases#')
  else
    link=$(read_json "$i.repository.html_url")
  fi
  rows="$rows${rows:+,}{\"repository\":\"$repository\",\"title\":\"$title\",\"link\":\"$link\"}"
  i=$((i + 1))
done

printf '{"text":"%s","icon":"bell","lists":{"notifications":[%s]}}\n' "$count" "$rows"
