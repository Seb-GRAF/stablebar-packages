#!/bin/bash
set -euo pipefail

base=$1

while IFS= read -r id; do
  [[ -f packages/$id/package.json ]] || continue
  version=$(jq -r .version "packages/$id/package.json")
  if old=$(git show "$base:packages/$id/package.json" 2> /dev/null | jq -r .version) && [[ $version == "$old" ]]; then
    echo "packages/$id changed but is still version $version; any change needs a new version" >&2
    failed=1
  fi
done < <(git diff --name-only "$base" -- packages | cut -d/ -f2 | sort -u)

exit "${failed:-0}"
