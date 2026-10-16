#!/bin/bash
set -euo pipefail

previous=${1:-}

sha256() {
  if command -v sha256sum > /dev/null; then
    sha256sum "$1" | cut -d ' ' -f 1
  else
    shasum -a 256 "$1" | cut -d ' ' -f 1
  fi
}

mkdir -p dist

for dir in packages/*/; do
  dir=${dir%/}
  id=$(basename "$dir")
  version=$(jq -r .version "$dir/package.json")

  entry=
  if [[ -n $previous ]]; then
    entry=$(jq -c --arg id "$id" --arg version "$version" '.packages[] | select(.id == $id and .version == $version)' "$previous")
  fi

  if [[ -z $entry ]]; then
    archive=$id-$version.tar.gz
    tar -czf "dist/$archive" -C "$dir" .
    entry=$(jq -c \
      --arg archive "$archive" \
      --arg sha256 "$(sha256 "dist/$archive")" \
      --arg raw "https://raw.githubusercontent.com/$GITHUB_REPOSITORY/$GITHUB_SHA/$dir" \
      --arg source "https://github.com/$GITHUB_REPOSITORY/tree/$GITHUB_SHA/$dir" '
      {
        id, name, version, kind, description, author, minimumVersion,
        screenshot: (if .screenshot then "\($raw)/\(.screenshot)" else null end),
        archive: $archive, sha256: $sha256, source: $source
      } | with_entries(select(.value != null))' "$dir/package.json")
  fi
  echo "$entry"
done | jq -s '{packages: sort_by(.id)}' > dist/index.json
