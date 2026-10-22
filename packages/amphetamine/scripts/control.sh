#!/bin/sh
set -e

case $1 in
  hour) osascript -e 'tell application "Amphetamine" to start new session with options {duration:1, interval:hours}' ;;
  indefinitely) osascript -e 'tell application "Amphetamine" to start new session with options {duration:0, interval:0}' ;;
  stop) osascript -e 'tell application "Amphetamine" to end session' ;;
esac
