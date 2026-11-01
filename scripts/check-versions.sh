#!/bin/bash
set -euo pipefail

base=$1

# Whether version $1 is higher than $2, compared as StableBar compares them to offer an update: runs
# of digits as numbers, other characters one by one. So 1.0.10 is higher than 1.0.9.
higher() {
  jq -en --arg a "$1" --arg b "$2" '
    def compare($x; $y):
      if $x == $y then 0
      elif $x == "" then -1
      elif $y == "" then 1
      elif ($x | test("^[0-9]")) and ($y | test("^[0-9]")) then
        ($x | capture("^(?<number>[0-9]+)(?<rest>.*)$")) as $p
        | ($y | capture("^(?<number>[0-9]+)(?<rest>.*)$")) as $q
        | if ($p.number | tonumber) != ($q.number | tonumber)
          then (if ($p.number | tonumber) < ($q.number | tonumber) then -1 else 1 end)
          else compare($p.rest; $q.rest) end
      elif $x[0:1] == $y[0:1] then compare($x[1:]; $y[1:])
      elif $x[0:1] < $y[0:1] then -1
      else 1 end;
    compare($a; $b) > 0' > /dev/null
}

# A changed package needs a version higher than every one it had on the base branch, even before it
# was retired: the store release keeps every archive it published, and StableBar offers only a higher
# version as an update.
while IFS= read -r id; do
  manifest=packages/$id/package.json
  [[ -f $manifest ]] || continue
  version=$(jq -r .version "$manifest")
  highest=
  while IFS= read -r commit; do
    earlier=$(git show "$commit:$manifest" 2> /dev/null | jq -r .version) || continue
    if [[ -z $highest ]] || higher "$earlier" "$highest"; then
      highest=$earlier
    fi
  done < <(git log --first-parent --format=%H "$base" -- "$manifest")
  [[ -n $highest ]] || continue
  if [[ $version == "$highest" ]]; then
    echo "packages/$id changed but is still version $version; any change needs a higher version" >&2
    failed=1
  elif ! higher "$version" "$highest"; then
    echo "packages/$id is version $version, lower than the $highest it already had; any change needs a higher version, a revert too" >&2
    failed=1
  fi
done < <(git diff --name-only "$base" -- packages | cut -d/ -f2 | sort -u)

exit "${failed:-0}"
