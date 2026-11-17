#!/bin/sh

ts="$PACKAGE_DIR/scripts/tailscale.sh"
# StableBar expands $PACKAGE_DIR when it runs the click.
# shellcheck disable=SC2016
toggle=',"onClick":"\"$PACKAGE_DIR/scripts/toggle.sh\""'
open=',"onClick":"open -a Tailscale"'

# BackendState is Running, Starting, Stopped, NeedsLogin or NeedsMachineAuth; empty when
# Tailscale isn't running.
state=$("$ts" status --json 2> /dev/null | sed -n 's/.*"BackendState": *"\([^"]*\)".*/\1/p' | head -n 1)

case $state in
  Running)
    ip=$("$ts" ip -4 2> /dev/null | head -n 1)
    printf '{"text":"","icon":"circle.grid.3x3.fill","state":"active","tooltip":"Connected · %s"%s}\n' "$ip" "$toggle"
    ;;
  Starting)
    printf '{"text":"","icon":"circle.grid.3x3","tooltip":"Connecting…"%s}\n' "$toggle"
    ;;
  NeedsLogin | NeedsMachineAuth)
    printf '{"text":"","icon":"circle.grid.3x3","state":"warning","tooltip":"Log in to Tailscale"%s}\n' "$open"
    ;;
  "")
    printf '{"text":"","icon":"circle.grid.3x3","state":"muted","tooltip":"Tailscale is not running"%s}\n' "$open"
    ;;
  *)
    printf '{"text":"","icon":"circle.grid.3x3","state":"muted","tooltip":"Disconnected"%s}\n' "$toggle"
    ;;
esac
