#!/bin/sh
set -e

json_escape() {
  printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# A single-quoted shell word, for a name inside a command string.
shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# The symbol, label and action of a state. EXITING means disconnected or disconnecting; other states
# are steps towards a connection.
describe() {
  case $1 in
    CONNECTED) symbol=lock.shield.fill label=Connected action=Disconnect ;;
    EXITING) symbol=shield.slash label=Disconnected action=Connect ;;
    *) symbol=shield.lefthalf.filled label=Connecting action=Disconnect ;;
  esac
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
overall=EXITING
quick=""
rows=""
while IFS=$tab read -r state name; do
  [ -n "$state" ] || continue
  [ "$state" = CONNECTED ] && connected="$connected${connected:+, }$name"
  # One connected configuration makes the widget connected; otherwise one connecting makes it connecting.
  if [ "$state" = CONNECTED ] || [ "$overall" = EXITING ]; then overall=$state; fi
  describe "$state"
  toggle=$(json_escape "\"\$PACKAGE_DIR/scripts/control.sh\" $action $(shell_quote "$name")")
  if [ "$name" = "$QUICK_CONNECT" ]; then
    quick="\"quickName\":\"$(json_escape "$name")\",\"quickState\":\"$label\",\"quickSymbol\":\"$symbol\",\"quickAction\":\"$action\",\"quickToggle\":\"$toggle\""
  else
    rows="$rows${rows:+,}{\"name\":\"$(json_escape "$name")\",\"state\":\"$label\",\"symbol\":\"$symbol\",\"toggle\":\"$toggle\"}"
  fi
done <<END
$configurations
END

describe "$overall"
tooltip=$label
[ -n "$connected" ] && tooltip="Connected to $connected"
printf '{"text":"","icon":"%s","tooltip":"%s","fields":{%s},"lists":{"configurations":[%s]}}\n' \
  "$symbol" "$(json_escape "$tooltip")" "$quick" "$rows"
