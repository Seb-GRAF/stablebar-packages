#!/bin/bash
# Tests check-versions.sh, check-one-package.sh, build-index.sh and check-package.sh on scratch
# repositories and packages, which it deletes afterwards.
set -euo pipefail
unset STABLEBAR STABLEBAR_RELEASE

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

# Commits the changes as a pull request on its own branch, and checks it against main with a script.
pull_request() {
  local script=$1 expected=$2 name=$3
  local label=${script#check-}
  git switch --quiet --create "pull-request-$((++pull_requests))"
  commit "pull request"
  check "$expected" "${label%.sh}: $name" "$scripts/$script" main
  git switch --quiet main
}

pull_requests=0
repository
package weather 1.0.0 first
commit "add weather"

package weather 1.0.0 second
pull_request check-versions.sh "fail:changed but is still version 1.0.0" "a changed package keeps its version"

package weather 1.0.1 second
pull_request check-versions.sh pass "a changed package raises its version"

package weather 1.0.1 second
commit "weather 1.0.1"
package weather 1.0.0 first
pull_request check-versions.sh "fail:lower than the 1.0.1 it already had" "a revert brings back an earlier version"

package weather 1.0.9 ninth
commit "weather 1.0.9"
package weather 1.0.10 tenth
pull_request check-versions.sh pass "versions compare as numbers, so 1.0.10 is higher than 1.0.9"

package weather 1.0.9-fix fix
pull_request check-versions.sh pass "a suffix after the same version is higher, as StableBar compares them"

package clock 1.0.0 tick
pull_request check-versions.sh pass "a new package"

git rm --quiet -r packages/weather
commit "retire weather"
package weather 1.0.9 ninth
pull_request check-versions.sh "fail:still version 1.0.9" "a retired package comes back with the version it had"

package weather 1.0.11 eleventh
pull_request check-versions.sh pass "a retired package comes back with a higher version"

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

# check-one-package.sh: a pull request changes one package, and README.md's package list with it.
repository
package weather 1.0.0 first
package clock 1.0.0 tick
echo "# Store" > README.md
commit "add weather and clock"

package weather 1.0.1 second
echo "# Store, with weather 1.0.1" > README.md
pull_request check-one-package.sh pass "a package and the package list"

package weather 1.0.1 second
package clock 1.0.1 tock
pull_request check-one-package.sh "fail:changes 2 packages: clock, weather" "two packages"

package weather 1.0.1 second
mkdir -p scripts
echo "echo checked" > scripts/check.sh
pull_request check-one-package.sh "fail:also changes scripts/check.sh" "a package and a script"

mkdir -p scripts .github
echo "echo checked" > scripts/check.sh
echo "name: CI" > .github/ci.yml
pull_request check-one-package.sh pass "CI and scripts without a package"

# check-package.sh: the file rules, then StableBar's checks with the binaries in STABLEBAR and
# STABLEBAR_RELEASE, here stand-ins that print a message and fail when given one.
bytes() {
  local number
  for number in "$@"; do
    printf '\\x%02x' "$number"
  done
}

# The start of a PNG or a JPEG of a width and height, which is all that `file` reads.
png() {
  printf '%b' "$(bytes 0x89 0x50 0x4e 0x47 0x0d 0x0a 0x1a 0x0a 0 0 0 13 0x49 0x48 0x44 0x52 \
    0 0 $(($1 >> 8)) $(($1 & 255)) 0 0 $(($2 >> 8)) $(($2 & 255)) 8 6 0 0 0 0 0 0 0)" > "$3"
}

jpeg() {
  printf '%b' "$(bytes 0xff 0xd8 0xff 0xe0 0 16 0x4a 0x46 0x49 0x46 0 1 1 0 0 1 0 1 0 0 \
    0xff 0xc0 0 17 8 $(($2 >> 8)) $(($2 & 255)) $(($1 >> 8)) $(($1 & 255)) 3 1 0x22 0 2 0x11 1 3 0x11 1 0xff 0xd9)" > "$3"
}

# A package with a shell script and a 520 × 144 preview. Its manifest adds the keys given as JSON.
store_package() {
  local folder=$scratch/store/$1 extra=${2:-'{}'}
  rm -rf "$folder"
  mkdir -p "$folder/scripts"
  jq -n --arg id "$1" --argjson extra "$extra" '{id: $id, name: $id, version: "1.0.0", screenshot: "preview.png"} + $extra' > "$folder/package.json"
  printf '#!/bin/bash\necho hello\n' > "$folder/scripts/widget.sh"
  png 520 144 "$folder/preview.png"
}

# A StableBar.app of a version whose binary fails every command with a message, or passes them all.
stablebar() {
  local app=$scratch/$1/StableBar.app
  rm -rf "${scratch:?}/$1"
  mkdir -p "$app/Contents/MacOS"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n    <key>CFBundleShortVersionString</key><string>%s</string>\n</dict>\n</plist>\n' "$2" > "$app/Contents/Info.plist"
  printf '%s' "${3:-}" > "$app/Contents/MacOS/error"
  cat > "$app/Contents/MacOS/StableBar" << 'END'
#!/bin/bash
error=$(cat "$(dirname "$0")/error")
[[ -z $error ]] || { echo "$error" >&2; exit 1; }
END
  chmod +x "$app/Contents/MacOS/StableBar"
}

checked() {
  local expected=$1 name=$2
  shift 2
  check "$expected" "package: $name" env "$@" "$scripts/check-package.sh" "$scratch/store/weather"
}

main=$scratch/main/StableBar.app/Contents/MacOS/StableBar
release=$scratch/release/StableBar.app/Contents/MacOS/StableBar

store_package weather
checked pass "a script and a preview"

printf '#!/bin/bash\necho hello\n' > "$scratch/store/weather/scripts/widget"
checked "fail:scripts/widget is a shell script; name it .sh" "a shell script not named .sh"

store_package weather
printf '#!/usr/bin/env bash\necho hello\n' > "$scratch/store/weather/scripts/widget"
checked "fail:scripts/widget is a shell script; name it .sh" "a script run by env bash, not named .sh"

store_package weather
printf '#!/usr/bin/osascript -l JavaScript\nfunction run() {}\n' > "$scratch/store/weather/scripts/widget.js"
checked pass "a JavaScript for osascript"

store_package weather
rm "$scratch/store/weather/preview.png"
checked "fail:preview.png isn't a file in the package" "the preview is missing"

store_package weather '{"screenshot": "../clock/preview.png"}'
store_package clock
checked "fail:../clock/preview.png is outside the package" "the preview is outside the package"

store_package weather
png 523 144 "$scratch/store/weather/preview.png"
checked "fail:preview.png is 523x144 pixels; previews are 520 × 144" "a preview of another size"

store_package weather '{"screenshot": "preview.jpg"}'
rm "$scratch/store/weather/preview.png"
jpeg 520 144 "$scratch/store/weather/preview.jpg"
checked pass "a JPEG preview"

store_package weather
echo "not an image" > "$scratch/store/weather/preview.png"
checked "fail:preview.png is not a PNG or JPEG image" "a preview that is no image"

store_package weather
stablebar main 0.0.0 "widgets.weather: Unknown property."
checked "fail:Unknown property." "it fails on main" STABLEBAR="$main"

stablebar main 0.0.0
stablebar release 0.9.0
checked pass "it works on main and the latest release" STABLEBAR="$main" STABLEBAR_RELEASE="$release"

stablebar release 0.9.0 "widgets.weather.popup.endStop: Unknown property."
checked "fail:fails on StableBar 0.9.0, the latest release" "it fails on the latest release" STABLEBAR="$main" STABLEBAR_RELEASE="$release"

store_package weather '{"minimumVersion": "0.10.0"}'
stablebar release 0.9.0 "Package weather needs StableBar 0.10.0 or later."
checked pass "the latest release refuses it for its minimumVersion" STABLEBAR="$main" STABLEBAR_RELEASE="$release"

store_package weather '{"minimumVersion": "0.5.0"}'
stablebar release 0.9.0 "widgets.weather.popup.endStop: Unknown property."
checked "fail:fails on StableBar 0.9.0, the latest release" "it fails on the latest release despite a minimumVersion" \
  STABLEBAR="$main" STABLEBAR_RELEASE="$release"

if ((failures)); then
  echo "$failures failed" >&2
  exit 1
fi
echo "All passed"
