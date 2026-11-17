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
  # The package's earlier versions stay listed for StableBar releases that can't run this one.
  if [[ -n $previous ]]; then
    jq -c --arg id "$id" --arg version "$version" '.packages[] | select(.id == $id and .version != $version)' "$previous"
  fi
# StableBar's setup reads "suggestions" to offer packages for tools and apps it finds on the Mac, and its
# Store groups packages by their "category" and shows their "symbol". Versions that don't know the keys ignore them.
#
# Each package keeps its newest version for each minimumVersion, oldest requirement first, minus any version
# that one needing no newer StableBar outranks. StableBar 0.17 and earlier keep the first entry for an ID.
done | jq -s --slurpfile suggestions suggestions.json --slurpfile listing listing.json '
  # Orders versions as Semantic Versioning does: numbers as numbers, and a prerelease before its release.
  def precedence:
    if . == null then [] else
      capture("^(?<core>[^-+]*)(-(?<pre>[^+]*))?")
      | [(.core | split(".") | map(tonumber? // .)), (if .pre then 0 else 1 end), ((.pre // "") | split(".") | map(tonumber? // .))]
    end;
  def staircase:
    group_by(.minimumVersion | precedence) | map(max_by(.version | precedence))
    | reduce .[] as $entry ({newest: null, kept: []};
        ($entry.version | precedence) as $version
        | if $version > .newest then .newest = $version | .kept += [$entry] else . end)
    | .kept;
  {packages: map(del(.category, .symbol) + ($listing[0][.id] // {})) | group_by(.id) | map(staircase) | add // [],
   suggestions: $suggestions[0]}' > dist/index.json
