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
text=""
top=""
bottom=""

add_window() {
  title=$(json_escape "$1")
  used=$(awk -v used="$3" 'BEGIN { printf "%.0f", used }')
  if [ "$USAGE" = used ]; then
    percent=$used counted=used
  else
    percent=$((100 - used)) counted=left
  fi
  fraction=$(awk -v percent="$percent" 'BEGIN { printf "%.2f", percent / 100 }')
  reset=""
  pace=""
  if [ -n "$4" ]; then
    reset="Resets in $(duration $(($4 - now)))"
    if [ "$2" = weekly ]; then
      pace=$(weekly_pace "$3" $(($4 - now)))
    fi
  fi
  rows="$rows${rows:+,}{\"title\":\"$title\",\"fraction\":\"$fraction\",\"detail\":\"$percent% $counted\",\"trailing\":\"$reset\",\"pace\":\"$pace\"}"
  case $2:$limits in
    session:session | session:both | weekly:weekly | weekly:both)
      summary="$summary${summary:+ · }$provider $2 $percent% $counted"
      text="$text${text:+ · }$percent%"
      if [ -z "$top" ]; then top=$fraction; else bottom=$fraction; fi
      ;;
  esac
}

add_provider() {
  plan=$(json_escape "$(printf '%s' "$plan" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')")
  fields="$fields\"${1}Plan\":\"$plan\","
  if [ "$SHOW" != percent ]; then
    fields="$fields\"${1}Top\":\"$top\",\"${1}Bottom\":\"$bottom\","
  fi
  if [ "$SHOW" != meters ]; then
    fields="$fields\"${1}Text\":\"$text\","
  fi
  lists="$lists${lists:+,}\"$1\":[$rows]"
  rows=""
  text=""
  top=""
  bottom=""
}

if [ "$PROVIDERS" != codex ]; then
  provider=Claude
  limits=$CLAUDE_LIMITS
  json=$(security find-generic-password -s "Claude Code-credentials" -w)
  token=$(read_json claudeAiOauth.accessToken)
  plan=$(read_json claudeAiOauth.subscriptionType)
  expires=$(read_json claudeAiOauth.expiresAt)
  if [ $((expires / 1000)) -le "$now" ]; then
    echo "Claude Code's sign-in has expired. Open Claude Code to renew it." >&2
    exit 1
  fi
  json=$(curl -fsS --max-time 12 \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage")

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
    fraction=$(awk -v spent="$spent" -v limit="$limit" -v usage="$USAGE" \
      'BEGIN { used = spent / limit; if (used > 1) used = 1; if (usage != "used") used = 1 - used; printf "%.2f", used }')
    detail=$(awk -v spent="$spent" -v limit="$limit" 'BEGIN { printf "%.2f / %.2f", spent / 100, limit / 100 }')
    rows="$rows,{\"title\":\"Extra usage\",\"fraction\":\"$fraction\",\"detail\":\"$detail $currency\",\"trailing\":\"This month\"}"
  fi
  add_provider claude
fi

if [ "$PROVIDERS" != claude ]; then
  provider=Codex
  limits=$CODEX_LIMITS
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
  add_provider codex
fi

printf '{"text":"%s","tooltip":"%s","fields":{%s"updated":"Updated at %s"},"lists":{%s}}\n' \
  "$summary" "$summary" "$fields" "$(date +%H:%M)" "$lists"
