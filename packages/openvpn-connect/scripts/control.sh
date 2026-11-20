#!/bin/sh
set -e

# $1 is Connect or Disconnect, $2 a profile's ID.
#
# macOS runs OpenVPN Connect's tunnels as VPN services labelled with its bundle ID, each naming the
# profile it carries. Starting and stopping them through macOS, as System Settings does, leaves the
# app's window alone; the app follows their state. Its own command line shows its window first.

# One line per OpenVPN Connect service: its status and its ID.
services=$(scutil --nc list | sed -nE \
  's/^[^(]*\(([A-Za-z]+)\) +([0-9A-Fa-f-]+) +VPN \(org\.openvpn\.client\.app\).*/\1 \2/p')

# The service carrying the profile to connect, and its status. It stays empty for Disconnect.
target=""
target_status=""
if [ "$1" = Connect ]; then
  while read -r status service; do
    [ -n "$service" ] || continue
    profile=$(scutil --nc show "$service" | sed -nE 's/^[[:space:]]*ovpnProfileId : (.+)$/\1/p' | head -n 1)
    if [ "$profile" = "$2" ]; then
      target=$service
      target_status=$status
      break
    fi
  done << END
$services
END
fi

# It connects one profile at a time: every other active service stops.
while read -r status service; do
  if [ -n "$service" ] && [ "$service" != "$target" ] && [ "$status" != Disconnected ]; then
    scutil --nc stop "$service"
  fi
done << END
$services
END

[ "$1" = Connect ] || exit 0

if [ -n "$target" ]; then
  [ "$target_status" = Disconnected ] && scutil --nc start "$target"
  exit 0
fi

# No service carries the profile yet, as before its first connection: the app connects it.
open -n -g -b org.openvpn.client.app --args --connect-shortcut="$2"
