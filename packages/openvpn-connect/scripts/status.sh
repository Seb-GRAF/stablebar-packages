#!/bin/sh
set -e

# OpenVPN Connect keeps its profiles in this file and rewrites it when they change.
store="$HOME/Library/Application Support/OpenVPN Connect/config.json"

# Its tunnel is a VPN service labelled with its bundle ID: a line starts with the service's status
# in parentheses, then its ID. It connects one profile at a time, so at most one service is active.
active=$(scutil --nc list | sed -nE \
  's/^[^(]*\((Connected|Connecting|Reasserting|Disconnecting)\) +([0-9A-Fa-f-]+) +VPN \(org\.openvpn\.client\.app\).*/\1 \2/p' \
  | head -n 1)

if [ -z "$active" ] && ! pgrep -xq 'OpenVPN Connect'; then
  echo '{"text":"","hidden":true}'
  exit 0
fi

state=Disconnected
profile=""
if [ -n "$active" ]; then
  state=${active%% *}
  # The service names the profile it carries by its ID.
  profile=$(scutil --nc show "${active#* }" | sed -nE 's/^[[:space:]]*ovpnProfileId : (.+)$/\1/p' | head -n 1)
fi

[ -r "$store" ] || store=/dev/null

# The app stores its state as JSON strings inside JSON. Profiles show by name; the command that
# toggles one passes its ID, quoted by jq's @sh.
jq -n -c --arg state "$state" --arg active "$profile" --arg quick "${QUICK_CONNECT:-}" '
  def describe:
    if . == "Connected" then {symbol: "lock.shield.fill", state: "Connected", action: "Disconnect"}
    elif . == "Connecting" or . == "Reasserting" then
      {symbol: "shield.lefthalf.filled", state: "Connecting", action: "Disconnect"}
    elif . == "Disconnecting" then {symbol: "shield.lefthalf.filled", state: "Disconnecting", action: "Connect"}
    else {symbol: "shield.slash", state: "Disconnected", action: "Connect"}
    end;

  ((try (input | ."persist:root" | fromjson | .status | fromjson | .profiles) catch null) // {})
  | [.[] | {
      id: (.id | tostring),
      name: ([.profileDisplayName, .profileName, .name] | map(select(type == "string" and . != "")) | first // "Profile")
    }]
  | sort_by(.name | ascii_downcase)
  | map(. + ((if .id == $active then $state else "Disconnected" end) | describe)
      | .toggle = "\"$PACKAGE_DIR/scripts/control.sh\" \(.action) \(.id | @sh)")
  | (map(select(.name == $quick)) | first) as $quickRow
  | (map(select(.id == $active)) | first | .name) as $activeName
  | ($state | describe) as $overall
  | {
      text: "",
      icon: $overall.symbol,
      tooltip: (if $state == "Connected" and $activeName then "Connected to \($activeName)" else $overall.state end),
      fields: (if $quickRow then {
        quickName: $quickRow.name,
        quickState: $quickRow.state,
        quickSymbol: $quickRow.symbol,
        quickAction: $quickRow.action,
        quickToggle: $quickRow.toggle
      } else {} end),
      lists: {profiles: map(select(.id != $quickRow.id) | {name, state, symbol, toggle})}
    }
' "$store"
