#!/bin/bash
# Tests check-versions.sh and build-index.sh on scratch repositories, which it deletes afterwards.
set -euo pipefail

scripts=$(cd "$(dirname "$0")" && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
failures=0

# Runs a command and reports whether it passed, or failed with the expected message: pass, or
# "fail:" followed by part of the message.
check() {
  local expected=$1 name=$2
  shift 2
  local result=pass
  "$@" > "$scratch/output" 2>&1 || result=fail
  local ok=false
  if [[ $expected == pass ]]; then
    [[ $result == pass ]] && ok=true
  elif [[ $result == fail ]] && grep -qF -- "${expected#fail:}" "$scratch/output"; then
    ok=true
  fi
  if $ok; then
    echo "ok - $name"
  else
    echo "not ok - $name: expected $expected, got $result" >&2
    sed 's/^/    /' "$scratch/output" >&2
    failures=$((failures + 1))
  fi
}

sha256() {
  if command -v sha256sum > /dev/null; then
    sha256sum "$1" | cut -d ' ' -f 1
  else
    shasum -a 256 "$1" | cut -d ' ' -f 1
  fi
}

# Starts a new, empty repository on main, replacing the previous one.
repository() {
  cd "$scratch"
  rm -rf repository
  mkdir repository
  cd repository
  git init --quiet --initial-branch main
  git config user.email test@example.com
  git config user.name Test
  git commit --quiet --allow-empty --message start
}

# Writes a package: its id, its version and the text of its script.
package() {
  mkdir -p "packages/$1"
  printf '{"id": "%s", "name": "%s", "version": "%s"}\n' "$1" "$1" "$2" > "packages/$1/package.json"
  printf '%s\n' "$3" > "packages/$1/widget.sh"
}

commit() {
  git add --all
  git commit --quiet --message "$1"
}

# Commits the changes as a pull request on its own branch and checks it against main.
pull_request() {
  local expected=$1 name=$2
  git switch --quiet --create "pull-request-$((++pull_requests))"
  commit "pull request"
  check "$expected" "versions: $name" "$scripts/check-versions.sh" main
  git switch --quiet main
}

pull_requests=0
repository
package weather 1.0.0 first
commit "add weather"

package weather 1.0.0 second
pull_request "fail:changed but is still version 1.0.0" "a changed package keeps its version"

package weather 1.0.1 second
pull_request pass "a changed package raises its version"

package weather 1.0.1 second
commit "weather 1.0.1"
package weather 1.0.0 first
pull_request "fail:lower than the 1.0.1 it already had" "a revert brings back an earlier version"

package weather 1.0.9 ninth
commit "weather 1.0.9"
package weather 1.0.10 tenth
pull_request pass "versions compare as numbers, so 1.0.10 is higher than 1.0.9"

package weather 1.0.9-fix fix
pull_request pass "a suffix after the same version is higher, as StableBar compares them"

package clock 1.0.0 tick
pull_request pass "a new package"

git rm --quiet -r packages/weather
commit "retire weather"
package weather 1.0.9 ninth
pull_request "fail:still version 1.0.9" "a retired package comes back with the version it had"

package weather 1.0.11 eleventh
pull_request pass "a retired package comes back with a higher version"

# build-index.sh writes dist/index.json, and an archive for each version that isn't published yet.
index() {
  rm -rf dist
  GITHUB_REPOSITORY=owner/store GITHUB_SHA=0123abc "$scripts/build-index.sh" "$@"
}

entry() {
  jq -r --arg id "$1" --arg key "$2" '.packages[] | select(.id == $id) | .[$key]' dist/index.json
}

keeps_the_indexed_entry() {
  index previous/index.json && [[ ! -e dist/weather-1.0.0.tar.gz && $(entry weather sha256) == kept ]]
}

archives_a_new_version() {
  index && [[ $(entry weather sha256) == $(sha256 dist/weather-1.0.0.tar.gz) ]]
}

uses_the_published_archive() {
  index "" published && [[ ! -e dist/weather-1.0.0.tar.gz && $(entry weather sha256) == $(sha256 published/weather-1.0.0.tar.gz) ]]
}

repository
package weather 1.0.0 first
mkdir previous published
echo '{"packages": [{"id": "weather", "version": "1.0.0", "archive": "weather-1.0.0.tar.gz", "sha256": "kept"}]}' > previous/index.json

check pass "index: a version in the previous index keeps its entry" keeps_the_indexed_entry
check pass "index: a new version gets an archive" archives_a_new_version

# A publish that uploaded the archive but failed to replace the index, or an index that was lost.
# Building the archive again gives other bytes, so the files are compared, not the archives.
tar -czf published/weather-1.0.0.tar.gz -C packages/weather .
touch -t 202001010000 packages/weather/widget.sh
check pass "index: an archive already published with the same files is used, not built again" uses_the_published_archive

chmod +x packages/weather/widget.sh
check "fail:weather-1.0.0.tar.gz is already on the store release with other files" \
  "index: an archive already published differs in an executable bit" index "" published

chmod -x packages/weather/widget.sh
package weather 1.0.0 changed
check "fail:weather-1.0.0.tar.gz is already on the store release with other files" \
  "index: an archive already published holds other files" index "" published

if ((failures)); then
  echo "$failures failed" >&2
  exit 1
fi
echo "All passed"
