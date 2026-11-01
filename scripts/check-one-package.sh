#!/bin/bash
# A pull request changes one package, along with README.md's package list, so that a review reads one
# package at a time. Changes to CI, the scripts or the guides get their own pull request.
set -euo pipefail

base=$1

changed=$(git diff --name-only --no-renames "$base")
packages=$(grep '^packages/' <<< "$changed" | cut -d/ -f2 | sort -u) || true
others=$(grep -v -e '^packages/' -e '^README\.md$' <<< "$changed") || true
count=$(grep -c . <<< "$packages") || true

if ((count > 1)); then
  echo "This pull request changes $count packages: ${packages//$'\n'/, }. Open one pull request per package." >&2
  exit 1
fi
if ((count == 1)) && [[ -n $others ]]; then
  echo "This pull request changes packages/$packages and also changes ${others//$'\n'/, }. Changes to CI, the scripts or the guides get their own pull request." >&2
  exit 1
fi
