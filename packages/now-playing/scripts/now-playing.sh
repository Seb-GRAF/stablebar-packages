#!/bin/sh
set -e

json_escape() {
  printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

track=""
for app in Music Spotify; do
  [ "$(osascript -e "application \"$app\" is running")" = true ] || continue
  result=$(osascript <<SCRIPT
tell application "$app"
  if player state is stopped then return ""
  return (player state as text) & linefeed & (name of current track) & linefeed & (artist of current track) & linefeed & (album of current track)
end tell
SCRIPT
)
  case $result in
    playing*) track=$result; break ;;
    paused*) [ -n "$track" ] || track=$result ;;
  esac
done

if [ -z "$track" ]; then
  printf '{"text":"","hidden":true}\n'
  exit 0
fi

{
  IFS= read -r state
  IFS= read -r title
  IFS= read -r artist
  IFS= read -r album
} <<TRACK || true
$track
TRACK

if [ "$state" = playing ]; then
  icon=music.note control=pause.fill
else
  icon=pause.circle control=play.fill
fi

title=$(json_escape "$title")
artist=$(json_escape "$artist")
album=$(json_escape "$album")
printf '{"text":"%s","icon":"%s","fields":{"title":"%s","artist":"%s","album":"%s","control":"%s"}}\n' \
  "$title" "$icon" "$title" "$artist" "$album" "$control"
