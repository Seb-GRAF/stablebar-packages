#!/bin/sh
set -e

json_escape() {
  printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

read_json() {
  printf '%s' "$json" | plutil -extract "$1" raw -o - -
}

duration() {
  if [ "$1" -ge 86400 ]; then
    printf '%dd %dh' $(($1 / 86400)) $(($1 % 86400 / 3600))
  elif [ "$1" -ge 3600 ]; then
    printf '%dh %dm' $(($1 / 3600)) $(($1 % 3600 / 60))
  else
    printf '%dm' $(($1 / 60))
  fi
}

weekly_pace() {
  elapsed=$((604800 - $2))
  [ "$elapsed" -gt 0 ] || elapsed=0
  delta=$(awk -v used="$1" -v elapsed="$elapsed" 'BEGIN { printf "%.0f", used - elapsed / 6048 }')
  if [ "$delta" -lt -2 ]; then
    printf '%d%% in reserve' $((-delta))
  elif [ "$delta" -gt 2 ]; then
    printf '%d%% in deficit' "$delta"
  else
    printf 'On pace'
  fi
  eta=$(awk -v used="$1" -v elapsed="$elapsed" 'BEGIN { if (used * 6048 > elapsed) printf "%d", (100 - used) * elapsed / used }')
  if [ -n "$eta" ]; then
    printf ' · Runs out in %s' "$(duration "$eta")"
  else
    printf ' · Lasts until reset'
  fi
}

now=$(date +%s)
summary=""
fields=""
lists=""
rows=""
group=""
bar=""

counted=left
[ "$PERCENTAGES_SHOW" = "What's used" ] && counted=used
arrangement=stacked
[ "$LAYOUT" = "One line" ] && arrangement=oneLine
# Which of the stacked layout's columns show.
columns=""
[ "$METERS" = Hide ] || columns="$columns,\"meters\":\"1\""
[ "$PERCENTAGES" = Hide ] || columns="$columns,\"percents\":\"1\""
[ "$RESET_TIMES" = Hide ] || columns="$columns,\"resets\":\"1\""

# Whether the bar shows window $1, session or weekly, of the provider whose choice is in $limits.
in_bar() {
  case $1:$limits in
    session:Session | weekly:Week | session:"Session and week" | weekly:"Session and week") return 0 ;;
  esac
  return 1
}

add_window() {
  title=$(json_escape "$1")
  used=$(awk -v used="$3" 'BEGIN { printf "%.0f", used }')
  if [ "$counted" = used ]; then
    percent=$used
  else
    percent=$((100 - used))
  fi
  fraction=$(awk -v percent="$percent" 'BEGIN { printf "%.2f", percent / 100 }')
  reset=""
  countdown=""
  pace=""
  if [ -n "$4" ]; then
    countdown=$(duration $(($4 - now)))
    reset="Resets in $countdown"
    if [ "$2" = weekly ]; then
      pace=$(weekly_pace "$3" $(($4 - now)))
    fi
  fi
  rows="$rows${rows:+,}{\"title\":\"$title\",\"fraction\":\"$fraction\",\"detail\":\"$percent% $counted\",\"trailing\":\"$reset\",\"pace\":\"$pace\"}"
  if in_bar "$2"; then
    summary="$summary${summary:+ · }$provider $2 $percent% $counted"
    label=W
    [ "$2" = session ] && label=5h
    group="$group\"${2}Label\":\"$label\","
    [ "$METERS" = Hide ] || group="$group\"${2}Meter\":\"$fraction\","
    [ "$PERCENTAGES" = Hide ] || group="$group\"${2}Percent\":\"$percent%\","
    if [ "$RESET_TIMES" = Show ] && [ -n "$countdown" ]; then
      group="$group\"${2}Reset\":\"$countdown\","
    fi
  fi
}

add_provider() {
  plan=$(json_escape "$(printf '%s' "$plan" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')")
  fields="$fields\"${1}Plan\":\"$plan\","
  lists="$lists${lists:+,}\"$1\":[$rows]"
  bar="$bar${bar:+,}{$group\"symbol\":\"$2\",\"$arrangement\":\"1\"$columns}"
  rows=""
  group=""
}

# With both providers on, the widget shows the ones signed in on this Mac. A provider on alone must be.
show_claude=true
show_codex=true
[ "$CLAUDE" != Off ] || show_claude=false
[ "$CODEX" != Off ] || show_codex=false
both=false
$show_claude && $show_codex && both=true

if $show_claude; then
  status=0
  credentials=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || status=$?
  # 44: the Keychain has no Claude Code sign-in.
  if [ "$status" = 44 ] && $both; then
    show_claude=false
  elif [ "$status" = 44 ]; then
    echo "Claude Code isn't signed in on this Mac. Sign in to Claude Code to see its limits." >&2
    exit 1
  elif [ "$status" != 0 ]; then
    echo "StableBar couldn't read Claude Code's sign-in from the Keychain." >&2
    exit 1
  fi
fi

if $show_codex && [ ! -f "$HOME/.codex/auth.json" ]; then
  if ! $both; then
    echo "Codex isn't signed in on this Mac. Sign in to Codex to see its limits." >&2
    exit 1
  fi
  show_codex=false
fi

if ! $show_claude && ! $show_codex; then
  echo "Neither Claude Code nor Codex is signed in on this Mac." >&2
  exit 1
fi

if $show_claude; then
  provider=Claude
  limits=$CLAUDE
  json=$credentials
  token=$(read_json claudeAiOauth.accessToken)
  plan=$(read_json claudeAiOauth.subscriptionType)
  expires=$(read_json claudeAiOauth.expiresAt)
  if [ $((expires / 1000)) -le "$now" ]; then
    echo "Claude Code's sign-in has expired. Open Claude Code to renew it." >&2
    exit 1
  fi
  if json=$(curl -fsS --max-time 12 \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage"); then
    printf '%s' "$json" > "$CONFIG_DIR/ai-usage-claude.json"
  elif [ -f "$CONFIG_DIR/ai-usage-claude.json" ]; then
    json=$(cat "$CONFIG_DIR/ai-usage-claude.json")
  else
    exit 1
  fi

  total=$(read_json limits)
  i=0
  while [ "$i" -lt "$total" ]; do
    used=$(read_json "limits.$i.percent")
    resets=$(read_json "limits.$i.resets_at" 2>/dev/null || true)
    if [ -n "$resets" ]; then
      resets=$(date -j -u -f %Y-%m-%dT%H:%M:%S "$(printf '%s' "$resets" | cut -c 1-19)" +%s)
    fi
    case $(read_json "limits.$i.kind") in
      session) add_window Session session "$used" "$resets" ;;
      weekly_all) add_window Weekly weekly "$used" "$resets" ;;
      weekly_scoped) add_window "$(read_json "limits.$i.scope.model.display_name") only" model "$used" "$resets" ;;
    esac
    i=$((i + 1))
  done

  if [ "$(read_json extra_usage.is_enabled 2>/dev/null || true)" = true ]; then
    spent=$(read_json extra_usage.used_credits)
    limit=$(read_json extra_usage.monthly_limit)
    currency=$(json_escape "$(read_json extra_usage.currency)")
    fraction=$(awk -v spent="$spent" -v limit="$limit" -v usage="$counted" \
      'BEGIN { used = spent / limit; if (used > 1) used = 1; if (usage != "used") used = 1 - used; printf "%.2f", used }')
    detail=$(awk -v spent="$spent" -v limit="$limit" 'BEGIN { printf "%.2f / %.2f", spent / 100, limit / 100 }')
    rows="$rows,{\"title\":\"Extra usage\",\"fraction\":\"$fraction\",\"detail\":\"$detail $currency\",\"trailing\":\"This month\"}"
  fi
  add_provider claude asterisk
fi

if $show_codex; then
  provider=Codex
  limits=$CODEX
  json=$(cat "$HOME/.codex/auth.json")
  token=$(read_json tokens.access_token)
  account=$(read_json tokens.account_id)
  json=$(curl -fsS --max-time 12 \
    -H "Authorization: Bearer $token" \
    -H "ChatGPT-Account-Id: $account" \
    "https://chatgpt.com/backend-api/wham/usage")
  plan=$(read_json plan_type)

  for window in primary_window secondary_window; do
    length=$(read_json "rate_limit.$window.limit_window_seconds" 2>/dev/null || true)
    [ -n "$length" ] || continue
    used=$(read_json "rate_limit.$window.used_percent")
    resets=$(read_json "rate_limit.$window.reset_at")
    if [ "$length" -lt 86400 ]; then
      add_window Session session "$used" "$resets"
    else
      add_window Weekly weekly "$used" "$resets"
    fi
  done
  add_provider codex terminal
fi

# The next refresh, in seconds, from a choice such as "Every 5 minutes".
interval=$(($(printf '%s' "$REFRESH" | tr -cd '0-9') * 60))
printf '{"text":"%s","tooltip":"%s","interval":%s,"fields":{%s"updated":"Updated at %s"},"lists":{%s,"bar":[%s]}}\n' \
  "$summary" "$summary" "$interval" "$fields" "$(date +%H:%M)" "$lists" "$bar"
