#!/bin/bash
set -euo pipefail

pid=$1
port=$2

if lsof -nP -a -u "$(id -un)" -p "$pid" -iTCP:"$port" -sTCP:LISTEN -t > /dev/null; then
  kill -TERM "$pid"
fi
