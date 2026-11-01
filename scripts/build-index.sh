#!/bin/bash
set -euo pipefail

previous=${1:-}
# Archives of the packages' versions that are already on the store release. A publish that failed
# after uploading them left them out of the index, so they're used as they are rather than built again.
published=${2:-}

sha256() {
  if command -v sha256sum > /dev/null; then
    sha256sum "$1" | cut -d ' ' -f 1
  else
    shasum -a 256 "$1" | cut -d ' ' -f 1
  fi
}

# Whether an archive holds the folder's files: the same paths, contents and executable bits.
same_files() {
  local extracted result=0
  extracted=$(mktemp -d)
  tar -xzf "$1" -C "$extracted" || result=1
  diff -r "$extracted" "$2" > /dev/null || result=1
  [[ $(executables "$extracted") == "$(executables "$2")" ]] || result=1
  rm -rf "$extracted"
  return "$result"
}

executables() {
  (cd "$1" && find . -type f -perm -u+x | sort)
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
    if [[ -n $published && -f $published/$archive ]]; then
      if ! same_files "$published/$archive" "$dir"; then
        echo "$archive is already on the store release with other files; raise the version of $dir" >&2
        exit 1
      fi
      file=$published/$archive
    else
      tar -czf "dist/$archive" -C "$dir" .
      file=dist/$archive
    fi
    entry=$(jq -c \
      --arg archive "$archive" \
      --arg sha256 "$(sha256 "$file")" \
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
