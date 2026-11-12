#!/bin/sh
set -e

# $1 is Connect or Disconnect, $2 a configuration's name. Both reach AppleScript as arguments.
osascript -e 'on run {action, vpn}' \
  -e 'tell application "Tunnelblick"' \
  -e 'if action is "Connect" then' \
  -e 'connect vpn' \
  -e 'else' \
  -e 'disconnect vpn' \
  -e 'end if' \
  -e 'end tell' \
  -e 'end run' "$1" "$2" > /dev/null
