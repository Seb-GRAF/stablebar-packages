#!/bin/bash
set -euo pipefail

dir=${1%/}

fail() {
  echo "$dir: $1" >&2
  exit 1
}

id=$(jq -r .id "$dir/package.json")
[[ $(basename "$dir") == "$id" ]] || fail "the folder name must equal the manifest id \"$id\""

while IFS= read -r -d '' file; do
  fail "$file is a symlink"
done < <(find "$dir" -type l -print0)

while IFS= read -r -d '' file; do
  [[ $(wc -c < "$file") -le 1048576 ]] || fail "$file is over 1 MiB"
  case $file in
    *.png | *.jpg | *.jpeg) continue ;;
  esac
  if [[ -s $file ]] && ! grep -Iq '' "$file"; then
    fail "$file is binary; only .png, .jpg and .jpeg files may be"
  fi
  if [[ -x $file && $(head -c 2 "$file") != '#!' ]]; then
    fail "$file is executable but has no shebang"
  fi
  case $file in
    *.json) ;;
    *) awk 'length > 300 { exit 1 }' "$file" || fail "$file has a line over 300 characters; minified code isn't accepted" ;;
  esac
done < <(find "$dir" -type f -print0)

[[ -n ${STABLEBAR:-} ]] || exit 0

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

"$STABLEBAR" --config "$scratch/config.json" --inspect-package "$dir"
"$STABLEBAR" --config "$scratch/config.json" --install-package "$dir"

if [[ $(jq -r '.kind // empty' "$dir/package.json") == theme ]]; then
  jq '{theme: {id, version}}' "$dir/package.json" > "$scratch/config.json"
else
  jq '{packages: [{id, version}]}' "$dir/package.json" > "$scratch/config.json"
fi
"$STABLEBAR" --validate "$scratch/config.json"
