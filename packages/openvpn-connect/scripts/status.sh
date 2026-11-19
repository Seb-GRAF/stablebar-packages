#!/bin/sh
set -e

# OpenVPN Connect keeps its profiles in this file and rewrites it when they change.
store="$HOME/Library/Application Support/OpenVPN Connect/config.json"
# The app, whose icon the popup shows beside Open OpenVPN Connect, and its own menu bar icons, black
# for a light bar and white for a dark one. Without them, the widget shows SF Symbols.
app="/Applications/OpenVPN Connect/OpenVPN Connect.app"
icons="$app/Contents/Resources/app.asar.unpacked"
[ -d "$app" ] || app=""
[ -f "$icons/black_connected.ico" ] && [ -f "$icons/white_connected.ico" ] || icons=""
# StableBar can't recolor an image, so the Logo color setting picks the black or the white icons.
# Automatic takes BAR_SHADE when the package's profile for a theme whose bar keeps one shade, such
# as Notch's, sets it. Otherwise it follows macOS, which sets AppleInterfaceStyle to Dark in dark
# mode and removes it in light mode; the widget runs again when it switches.
case ${LOGO_COLOR:-Automatic} in
  Black) shade=black ;;
  White) shade=white ;;
  *)
    case ${BAR_SHADE:-} in
      dark) shade=white ;;
      light) shade=black ;;
      *)
        shade=black
        [ "$(defaults read -g AppleInterfaceStyle 2> /dev/null || true)" = Dark ] && shade=white
        ;;
    esac
    ;;
esac
# The tunnel's last byte counts and speeds, for the speeds and the graph.
traffic="${TMPDIR:-/tmp}/stablebar-openvpn-connect-traffic.json"

# Its tunnel is a VPN service labelled with its bundle ID: a line starts with the service's status
# in parentheses, then its ID. It connects one profile at a time, so at most one service is active.
active=$(scutil --nc list | sed -nE \
  's/^[^(]*\((Connected|Connecting|Reasserting|Disconnecting)\) +([0-9A-Fa-f-]+) +VPN \(org\.openvpn\.client\.app\).*/\1 \2/p' \
  | head -n 1)

if [ -z "$active" ] && ! pgrep -xq 'OpenVPN Connect'; then
  rm -f "$traffic"
  echo '{"text":"","hidden":true}'
  exit 0
fi

state=Disconnected
profile=""
interface=""
counters=""
if [ -n "$active" ]; then
  state=${active%% *}
  service=${active#* }
  # The service names the profile it carries by its ID.
  profile=$(scutil --nc show "$service" | sed -nE 's/^[[:space:]]*ovpnProfileId : (.+)$/\1/p' | head -n 1)
  if [ "$state" = Connected ]; then
    interface=$(scutil --nc status "$service" | sed -nE 's/^[[:space:]]*InterfaceName : (.+)$/\1/p' | head -n 1)
    # The bytes received and sent, from the interface's link row: the fifth and second last columns.
    if [ -n "$interface" ]; then
      counters=$(netstat -ibn -I "$interface" | awk '$3 ~ /^<Link#/ { print $(NF - 4), $(NF - 1); exit }')
    fi
  fi
fi

[ -n "$counters" ] || rm -f "$traffic"
previous=$(cat "$traffic" 2> /dev/null || true)
[ -r "$store" ] || store=/dev/null

# jq prints two lines: the traffic to keep for the next run, or null, then the widget's output.
# The app stores its state as JSON strings inside JSON. Profiles show by name; the command that
# toggles one passes its ID, quoted by @sh.
result=$(jq -n -c --arg state "$state" --arg active "$profile" --arg quick "${QUICK_CONNECT:-}" \
  --arg bar "${BAR_SHOWS:-Logo}" --arg app "$app" --arg icons "$icons" --arg shade "$shade" --arg interface "$interface" \
  --arg counters "$counters" --arg previous "$previous" '
  def describe:
    if . == "Connected" then {state: "Connected", action: "Disconnect", look: "connected"}
    elif . == "Connecting" or . == "Reasserting" then {state: "Connecting", action: "Disconnect", look: "connecting"}
    elif . == "Disconnecting" then {state: "Disconnecting", action: "Connect", look: "connecting"}
    else {state: "Disconnected", action: "Connect", look: "disconnected"}
    end;

  # OpenVPN Connect draws its logo filled while connected, circling arrows while connecting and an
  # outline while disconnected.
  def art:
    if $icons == "" then
      {logo: "", symbol: {connected: "lock.fill", connecting: "arrow.triangle.2.circlepath", disconnected: "lock.open"}[.]}
    else {logo: "\($icons)/\($shade)_\(.).ico", symbol: ""}
    end;

  # Bytes per second as StableBar writes network speeds, such as 240 KiB/s or 1.2 MiB/s.
  def rate:
    {value: ., unit: 0}
    | until(.value < 1024 or .unit == 3; {value: (.value / 1024), unit: (.unit + 1)})
    | ["B/s", "KiB/s", "MiB/s", "GiB/s"][.unit] as $unit
    | if .value < 10 and .unit > 0 then (.value * 10 | round) as $tenths | "\($tenths / 10 | floor).\($tenths % 10) \($unit)"
      else "\(.value | round) \($unit)"
      end;

  # The graph draws 0 to 1, so speeds scale to the fastest one shown, or 10 KiB/s while idle. It
  # draws the samples it has from the right, so a new connection starts from a line of zeros.
  def scaled: ((. + [10240]) | max) as $top | ([range(60 - length)] | map(0)) + map(. / $top);

  def valid: type == "object" and (.rx | type) == "number" and (.tx | type) == "number"
    and (.time | type) == "number" and (.download | type) == "array" and (.upload | type) == "array";

  ($counters | split(" ") | map(tonumber? // empty)) as $bytes
  | (try ($previous | fromjson) catch null) as $last
  | (if ($bytes | length) != 2 then null
      else now as $time
      | (if ($last | valid) and $last.interface == $interface and $bytes[0] >= $last.rx and $bytes[1] >= $last.tx
          and $time > $last.time
          then {down: (($bytes[0] - $last.rx) / ($time - $last.time)), up: (($bytes[1] - $last.tx) / ($time - $last.time)),
            download: ($last.download | map(numbers)), upload: ($last.upload | map(numbers))}
          else {down: 0, up: 0, download: [], upload: []}
          end) as $speed
      | {interface: $interface, time: $time, rx: $bytes[0], tx: $bytes[1],
          download: ($speed.download + [$speed.down])[-60:], upload: ($speed.upload + [$speed.up])[-60:]}
      end) as $traffic
  | (if $traffic then {downRate: ($traffic.download[-1] | rate), upRate: ($traffic.upload[-1] | rate)} else {} end) as $rates

  | ((try (input | ."persist:root" | fromjson | .status | fromjson | .profiles) catch null) // {})
  | [.[] | {
      id: (.id | tostring),
      name: ([.profileDisplayName, .profileName, .name] | map(select(type == "string" and . != "")) | first // "Profile")
    }]
  | sort_by(.name | ascii_downcase)
  | map(((if .id == $active then $state else "Disconnected" end) | describe) as $row
      | . + $row + ($row.look | art)
      | .toggle = "\"$PACKAGE_DIR/scripts/control.sh\" \(.action) \(.id | @sh)"
      | if .state == "Connected" then . + $rates else . end)
  | (map(select(.name == $quick)) | first) as $quickRow
  | (map(select(.id == $active)) | first | .name) as $activeName
  | ($state | describe) as $overall
  | ($bar == "Speeds" and $traffic != null) as $showSpeeds
  # The bar keeps the filled logo while disconnected, faded by the muted state.
  | ($overall.look == "disconnected") as $muted
  | $traffic,
    ({
      text: "",
      tooltip: (if $state == "Connected" and $activeName then "Connected to \($activeName)" else $overall.state end),
      fields: (
        (if $showSpeeds then {logo: "", symbol: "", speeds: "↓\($rates.downRate) ↑\($rates.upRate)"}
          else ((if $muted and $icons != "" then "connected" else $overall.look end) | art) + {speeds: ""} end)
        + $rates
        + {app: $app, appSymbol: (if $app == "" then "arrow.up.forward.app" else "" end)}
        + (if $quickRow then {
            quickName: $quickRow.name,
            quickState: $quickRow.state,
            quickAction: $quickRow.action,
            quickToggle: $quickRow.toggle,
            quickLogo: $quickRow.logo,
            quickSymbol: $quickRow.symbol,
            quickTraffic: (if $quickRow.downRate then "1" else "" end)
          } else {} end)),
      series: (if $traffic then {download: ($traffic.download | scaled), upload: ($traffic.upload | scaled)} else {} end),
      lists: {profiles: map(select(.id != $quickRow.id)
        | {name, state, action, toggle, logo, symbol, downRate: (.downRate // ""), upRate: (.upRate // "")})}
    } + (if $muted then {state: "muted"} else {} end) + (if $traffic then {interval: 2} else {} end))
' "$store")

{
  read -r keep
  read -r output
} << END
$result
END

if [ "$keep" != null ]; then
  temporary=$(mktemp "$traffic.XXXXXX")
  printf '%s\n' "$keep" > "$temporary"
  mv -f "$temporary" "$traffic"
fi
printf '%s\n' "$output"
