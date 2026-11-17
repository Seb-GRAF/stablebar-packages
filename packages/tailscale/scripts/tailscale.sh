#!/bin/sh

# Runs Tailscale's command-line tool: the one on PATH, or the one inside the app, which
# answers the same commands when the CLI isn't installed.
if command -v tailscale > /dev/null 2>&1; then
  exec tailscale "$@"
fi
exec /Applications/Tailscale.app/Contents/MacOS/Tailscale "$@"
