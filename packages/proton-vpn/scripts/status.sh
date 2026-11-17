#!/bin/sh

# Proton VPN's network extension shows up as a VPN service named after its bundle ID. Its
# status line is one of Connected, Connecting, Disconnecting, Reasserting or Disconnected.
service=$(scutil --nc list | sed -n 's/.*[[:space:]]\([0-9A-F-]\{36\}\)[[:space:]]*VPN (ch\.protonvpn\.mac).*/\1/p' | head -n 1)
if [ -z "$service" ]; then
  echo '{"text":"","hidden":true}'
  exit 0
fi

status=$(scutil --nc status "$service" | head -n 1)
case $status in
  Connected) symbol=checkmark.shield.fill state=active tooltip="Proton VPN connected" ;;
  Connecting | Reasserting) symbol=shield.lefthalf.filled state="" tooltip="Proton VPN connecting…" ;;
  Disconnecting) symbol=shield.lefthalf.filled state="" tooltip="Proton VPN disconnecting…" ;;
  *) symbol=shield state=muted tooltip="Proton VPN disconnected" ;;
esac
printf '{"text":"","fields":{"symbol":"%s"},"state":"%s","tooltip":"%s"}\n' "$symbol" "$state" "$tooltip"
