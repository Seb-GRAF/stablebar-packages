#!/bin/sh
set -e

json_escape() {
  printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Asking a Tunnelblick that isn't running would launch it.
if [ "$(osascript -e 'application "Tunnelblick" is running')" != true ]; then
  echo '{"text":"","hidden":true}'
  exit 0
fi

# One line per VPN configuration: its state, a tab and its name. Tunnelblick doesn't answer count,
# so a loop over its configurations fails; this pairs its list of states with its list of names.
configurations=$(osascript -e 'tell application "Tunnelblick"' \
  -e 'set states to state of configurations' \
  -e 'set names to name of configurations' \
  -e 'end tell' \
  -e 'set output to ""' \
  -e 'repeat with i from 1 to count of states' \
  -e 'set output to output & item i of states & tab & item i of names & linefeed' \
  -e 'end repeat' \
  -e 'return output')

tab=$(printf '\t')
connected=""
connecting=false
while IFS=$tab read -r state name; do
  # EXITING means disconnected or disconnecting; other states are steps towards a connection.
  case $state in
    CONNECTED) connected="$connected${connected:+, }$name" ;;
    EXITING | "") ;;
    *) connecting=true ;;
  esac
done <<END
$configurations
END

if [ -n "$connected" ]; then
  symbol=lock.shield.fill tooltip="Connected to $connected"
elif $connecting; then
  symbol=shield.lefthalf.filled tooltip=Connecting
else
  symbol=shield.slash tooltip=Disconnected
fi
printf '{"text":"","tooltip":"%s","fields":{"symbol":"%s"}}\n' "$(json_escape "$tooltip")" "$symbol"
