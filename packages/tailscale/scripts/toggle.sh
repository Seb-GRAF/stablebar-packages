#!/bin/sh
set -e

ts="$PACKAGE_DIR/scripts/tailscale.sh"
if "$ts" status --json 2> /dev/null | grep -q '"BackendState": *"Running"'; then
  "$ts" down
else
  "$ts" up
fi
