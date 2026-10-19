#!/bin/bash
set -euo pipefail

listeners=$(lsof -nP -a -u "$(id -un)" -iTCP:"$PORTS" -sTCP:LISTEN -Fpcn 2>&1) || {
  if [[ $? != 1 || -n $listeners ]]; then
    printf '%s\n' "$listeners" >&2
    exit 1
  fi
}

printf '%s' "$listeners" | jq -Rns '
  reduce (inputs | split("\n")[]) as $line ({pid: "", process: "", servers: []};
    if $line | startswith("p") then .pid = $line[1:]
    elif $line | startswith("c") then .process = $line[1:]
    elif $line | startswith("n") then
      ($line | split(":") | last | tonumber) as $port |
      .servers += [{port: $port, pid, process}]
    else . end
  ) |
  .servers | unique_by([.port, .pid]) |
  {
    text: (map(.port) | unique | length | tostring),
    icon: "server.rack",
    fields: {hint: (if length == 0 then "No listening ports in this range." else "" end)},
    lists: {servers: map({
      address: "localhost:\(.port)",
      process: "\(.process) · PID \(.pid)",
      link: "http://localhost:\(.port)",
      stop: ("\"$PACKAGE_DIR/scripts/stop.sh\" " + (.pid | @sh) + " " + (.port | tostring | @sh))
    })}
  }'
