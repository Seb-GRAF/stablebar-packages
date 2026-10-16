#!/bin/sh
set -e

json_escape() {
  printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

read_json() {
  printf '%s' "$outdated" | plutil -extract "$1" raw -o - -
}

outdated=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --json=v2)

total=0
rows=""
for kind in formulae casks; do
  count=$(read_json "$kind")
  total=$((total + count))
  i=0
  while [ "$i" -lt "$count" ]; do
    name=$(json_escape "$(read_json "$kind.$i.name")")
    installed=$(json_escape "$(read_json "$kind.$i.installed_versions.0")")
    current=$(json_escape "$(read_json "$kind.$i.current_version")")
    rows="$rows${rows:+,}{\"name\":\"$name\",\"versions\":\"$installed → $current\"}"
    i=$((i + 1))
  done
done

if [ "$total" -eq 0 ]; then
  printf '{"text":"","hidden":true}\n'
  exit 0
fi

printf '{"text":"%s","icon":"shippingbox","fields":{"summary":"%s outdated"},"lists":{"outdated":[%s]}}\n' "$total" "$total" "$rows"
