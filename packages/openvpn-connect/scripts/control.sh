#!/bin/sh
set -e

# $1 is Connect or Disconnect, $2 a profile's ID. OpenVPN Connect takes them on its command line: a
# new instance hands them to the running app and quits, or starts the app with them. It connects
# one profile at a time, so disconnecting needs no ID.
if [ "$1" = Connect ]; then
  open -n -g -b org.openvpn.client.app --args --connect-shortcut="$2"
else
  open -n -g -b org.openvpn.client.app --args --disconnect-shortcut
fi
