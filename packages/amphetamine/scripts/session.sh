#!/bin/sh
set -e

if [ "$(osascript -e 'application "Amphetamine" is running')" = false ]; then
  printf '{"text":"Off","icon":"pill","fields":{"status":"Amphetamine is not running"}}\n'
  exit 0
fi

remaining=$(osascript -e 'tell application "Amphetamine" to session time remaining')
icon=pill.fill
case $remaining in
  -3) text=Off; icon=pill; status="No active session" ;;
  -2) text=Awake; status="Keeping awake for an app or until a set time" ;;
  -1) text=Awake; status="Keeping awake with a trigger" ;;
  0) text=Awake; status="Keeping awake indefinitely" ;;
  *)
    minutes=$(((remaining + 59) / 60))
    text="${minutes}m"
    status="Keeping awake for $minutes more minutes"
    ;;
esac

printf '{"text":"%s","icon":"%s","fields":{"status":"%s"}}\n' "$text" "$icon" "$status"
