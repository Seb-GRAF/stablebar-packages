#!/bin/sh
set -e

target=""
for app in Music Spotify; do
  [ "$(osascript -e "application \"$app\" is running")" = true ] || continue
  case $(osascript -e "tell application \"$app\" to player state as text") in
    playing) target=$app; break ;;
    paused) [ -n "$target" ] || target=$app ;;
  esac
done

[ -z "$target" ] || osascript -e "tell application \"$target\" to $1"
