#!/bin/sh

# Proton VPN's network extensions show up as VPN services labelled with its bundle ID, each line
# starting with the service's status. Proton can have several, so any one connected counts.
services=$(scutil --nc list | grep 'VPN (ch\.protonvpn\.mac)')
case $services in
  "")
    echo '{"text":"","hidden":true}'
    exit 0
    ;;
  *"(Connected)"*) symbol=checkmark.shield.fill state=active tooltip="Proton VPN connected" ;;
  *"(Connecting)"*) symbol=shield.lefthalf.filled state="" tooltip="Proton VPN connecting…" ;;
  *"(Disconnecting)"*) symbol=shield.lefthalf.filled state="" tooltip="Proton VPN disconnecting…" ;;
  *) symbol=shield state=muted tooltip="Proton VPN disconnected" ;;
esac
printf '{"text":"","fields":{"symbol":"%s"},"state":"%s","tooltip":"%s"}\n' "$symbol" "$state" "$tooltip"
