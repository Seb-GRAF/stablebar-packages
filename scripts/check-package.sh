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

# A first line that runs sh, bash, zsh, dash or ksh, directly or through env.
shell='^#!.*[/[:space:]](sh|bash|zsh|dash|ksh)([[:space:]]|$)'

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
  # Lint runs ShellCheck on the files named .sh.
  if [[ $file != *.sh && $(head -n 1 "$file") =~ $shell ]]; then
    fail "${file#"$dir"/} is a shell script; name it .sh so ShellCheck checks it"
  fi
done < <(find "$dir" -type f -print0)

screenshot=$(jq -r '.screenshot // empty' "$dir/package.json")
if [[ -n $screenshot ]]; then
  case /$screenshot/ in
    //* | */../*) fail "the screenshot $screenshot is outside the package" ;;
  esac
  [[ -f $dir/$screenshot ]] || fail "the screenshot $screenshot isn't a file in the package"
  description=$(file -b "$dir/$screenshot")
  case $description in
    "PNG image data, "* | "JPEG image data"*) ;;
    *) fail "the screenshot $screenshot is not a PNG or JPEG image" ;;
  esac
  size=$(sed -nE -e 's/^PNG image data, ([0-9]+) x ([0-9]+),.*/\1x\2/p' \
    -e 's/^JPEG image data,.* precision [0-9]+, ([0-9]+)x([0-9]+),.*/\1x\2/p' <<< "$description")
  [[ $size == 520x144 ]] || fail "the screenshot $screenshot is ${size:-of unknown size} pixels; previews are 520 × 144"
fi

[[ -n ${STABLEBAR:-} || -n ${STABLEBAR_RELEASE:-} ]] || exit 0

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

# Inspects the package with the StableBar binary $1, installs it into a scratch configuration in the
# folder $2, and validates that configuration with the package turned on.
check_with() {
  local stablebar=$1 config=$2/config.json
  mkdir -p "$2"
  "$stablebar" --config "$config" --inspect-package "$dir" || return
  "$stablebar" --config "$config" --install-package "$dir" || return
  if [[ $(jq -r '.kind // empty' "$dir/package.json") == theme ]]; then
    jq '{theme: {id, version}}' "$dir/package.json" > "$config"
  else
    jq '{packages: [{id, version}]}' "$dir/package.json" > "$config"
  fi
  "$stablebar" --validate "$config"
}

if [[ -n ${STABLEBAR:-} ]]; then
  check_with "$STABLEBAR" "$scratch/main" || fail "fails with $STABLEBAR"
fi

# People install packages into a StableBar release, so the package also has to work with the latest
# one, unless its minimumVersion asks for a newer StableBar and that release refuses it.
if [[ -n ${STABLEBAR_RELEASE:-} ]]; then
  plist=$(dirname "$STABLEBAR_RELEASE")/../Info.plist
  release=
  if [[ -f $plist ]]; then
    release=$(tr -d '\n' < "$plist" | sed -nE 's|.*<key>CFBundleShortVersionString</key>[[:space:]]*<string>([^<]*)</string>.*|\1|p')
  fi
  latest="${release:+StableBar $release, }the latest release"
  minimum=$(jq -r '.minimumVersion // empty' "$dir/package.json")
  if ! check_with "$STABLEBAR_RELEASE" "$scratch/release" > "$scratch/release.log" 2>&1; then
    if [[ -n $minimum ]] && grep -qF "needs StableBar $minimum or later" "$scratch/release.log"; then
      echo "$dir: not checked on $latest, which its minimumVersion $minimum is above"
    else
      cat "$scratch/release.log" >&2
      fail "fails on $latest; if it uses something newer, set minimumVersion above ${release:-that release}"
    fi
  fi
fi
