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

# Sets $json to the usage response for the curl arguments, saving it in $saved. When the request fails,
# it uses the response an earlier run saved, if any, and $note says why. $data_time is when it was fetched.
fetch() {
  wait_file="${saved%.json}-wait"
  if [ -f "$wait_file" ] && [ "$now" -lt "$(cat "$wait_file")" ]; then
    use_saved "$host is limiting requests; trying again at $(date -r "$(cat "$wait_file")" +%H:%M)"
    return
  fi
  # A setting change restarts the script at once. A response from the last minute is still current,
  # and asking again so soon is what makes Anthropic answer 429.
  if [ -f "$saved" ] && [ $((now - $(stat -f %m "$saved"))) -lt 60 ]; then
    json=$(cat "$saved")
    data_time=$(stat -f %m "$saved")
    note=""
    return
  fi
  result=$(curl -sS --max-time 12 -o "$saved.part" -w '%{http_code} %header{retry-after}' "$@") || true
  case ${result%% *} in
    200)
      mv "$saved.part" "$saved"
      json=$(cat "$saved")
      data_time=$now
      note=""
      return
      ;;
    429)
      wait=${result#* }
      case $wait in '' | *[!0-9]*) wait=300 ;; esac
      # Anthropic has answered 429 with Retry-After: 0.
      [ "$wait" -ge 60 ] || wait=60
      echo $((now + wait)) > "$wait_file"
      reason="$host is limiting requests; trying again at $(date -r $((now + wait)) +%H:%M)"
      ;;
    401 | 403) reason="$app's sign-in has expired; open $app to renew it" ;;
    *) reason="Couldn't reach $host" ;;
  esac
  rm -f "$saved.part"
  use_saved "$reason"
}

# Uses the response an earlier run saved in $saved, with $1 saying why, or no response if there is none.
use_saved() {
  if [ -f "$saved" ]; then
    json=$(cat "$saved")
    data_time=$(stat -f %m "$saved")
    note="$1. Showing data from $(date -r "$data_time" +%H:%M)."
  else
    json=""
    note="$1."
  fi
}

now=$(date +%s)
# The next refresh, in seconds, from a choice such as "Every 5 minutes".
interval=$(($(printf '%s' "$REFRESH" | tr -cd '0-9') * 60))
updated=$now
failures=""
summary=""
popup=""
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
  # A reset that has passed belongs to a saved response; the next refresh brings the new window.
  if [ -n "$4" ] && [ "$4" -gt "$now" ]; then
    countdown=$(duration $(($4 - now)))
    reset="Resets in $countdown"
    # Pace is noise in the first 3% of the week.
    if [ "$2" = weekly ] && [ $((604800 - ($4 - now))) -ge 18144 ]; then
      pace=$(weekly_pace "$3" $(($4 - now)))
    fi
    # Refresh a minute after the reset, when that comes before the next refresh; a response saved before
    # the reset is then more than a minute old, so it's fetched again.
    [ $(($4 - now + 60)) -ge "$interval" ] || interval=$(($4 - now + 60))
  fi
  rows="$rows${rows:+,}{\"title\":\"$title\",\"fraction\":\"$fraction\",\"detail\":\"$percent% $counted\",\"trailing\":\"$reset\",\"pace\":\"$pace\"}"
  if in_bar "$2"; then
    summary="$summary${summary:+ · }$provider $2 $percent% $counted"
    label=W
    [ "$2" = session ] && label=5h
    group="$group\"${2}Label\":\"$label\","
    [ "$METERS" = Hide ] || group="$group\"${2}Meter\":\"$fraction\","
    [ "$PERCENTAGES" = Hide ] || group="$group\"${2}Percent\":\"$percent%\","
    # A window without a countdown, such as a session that hasn't started, keeps its line in the
    # stacked layout, so the week's countdown stays on the week's line.
    [ "$RESET_TIMES" = Hide ] || group="$group\"${2}Reset\":\"${countdown:-–}\","
  fi
}

# Adds a provider's section to the popup and, with data, its group to the bar: $1 is its symbol, $2 its
# title, $3 its usage dashboard and $4 the account's name on the bar, if any.
add_provider() {
  plan=$(json_escape "$(printf '%s' "$plan" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')")
  divider=""
  [ -z "$popup" ] || divider=",\"divider\":\"1\""
  popup="$popup${popup:+,}{\"header\":\"$(json_escape "$2")\",\"plan\":\"$plan\"$divider}"
  [ -z "$note" ] || popup="$popup,{\"note\":\"$(json_escape "$note")\"}"
  popup="$popup${rows:+,}$rows,{\"dashboard\":\"$3\"}"
  if [ -n "$json" ]; then
    look=""
    [ -z "$note" ] || look=",\"look\":\"stale\""
    bar="$bar${bar:+,}{$group\"symbol\":\"$1\",\"name\":\"$(json_escape "$4")\",\"$arrangement\":\"1\"$columns$look}"
    [ "$data_time" -ge "$updated" ] || updated=$data_time
  else
    failures="$failures${failures:+ }$note"
  fi
  rows=""
  group=""
}

# Reads the usage of the Claude Code account whose Keychain sign-in is in $json.
claude_usage() {
  token=$(read_json claudeAiOauth.accessToken)
  plan=$(read_json claudeAiOauth.subscriptionType)
  expires=$(read_json claudeAiOauth.expiresAt)
  if [ $((expires / 1000)) -le "$now" ]; then
    use_saved "Claude Code's sign-in has expired; open Claude Code to renew it"
  else
    fetch -H "Authorization: Bearer $token" -H "anthropic-beta: oauth-2025-04-20" \
      "https://api.anthropic.com/api/oauth/usage"
  fi
  [ -n "$json" ] || return 0
  total=$(read_json limits)
  # Claude reports no session until one starts, so a session that hasn't started is unused.
  i=0
  while [ "$i" -lt "$total" ] && [ "$(read_json "limits.$i.kind")" != session ]; do i=$((i + 1)); done
  [ "$i" -lt "$total" ] || add_window Session session 0 ""
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
    spent=$(read_json extra_usage.used_credits 2>/dev/null || true)
    limit=$(read_json extra_usage.monthly_limit 2>/dev/null || true)
    # Without a cap above zero, there's no share of it to show.
    if [ -n "$spent" ] && awk -v limit="$limit" 'BEGIN { exit !(limit > 0) }'; then
      currency=$(json_escape "$(read_json extra_usage.currency)")
      fraction=$(awk -v spent="$spent" -v limit="$limit" -v usage="$counted" \
        'BEGIN { used = spent / limit; if (used > 1) used = 1; if (usage != "used") used = 1 - used; printf "%.2f", used }')
      detail=$(awk -v spent="$spent" -v limit="$limit" 'BEGIN { printf "%.2f / %.2f", spent / 100, limit / 100 }')
      rows="$rows,{\"title\":\"Extra usage\",\"fraction\":\"$fraction\",\"detail\":\"$detail $currency\",\"trailing\":\"This month\"}"
    fi
  fi
}

# Claude Code keeps the sign-in of the folder CLAUDE_CONFIG_DIR names in "Claude Code-credentials-"
# followed by the first 8 hex digits of the SHA-256 of that path, exactly as written, and the sign-in of
# its default folder, used without CLAUDE_CONFIG_DIR, in "Claude Code-credentials".
hashed() {
  printf -- '-%s' "$(printf '%s' "$1" | shasum -a 256 | cut -c 1-8)"
}
main_suffix=""
[ -z "$CLAUDE_CONFIG_DIR" ] || main_suffix=$(hashed "$CLAUDE_CONFIG_DIR")

# More Claude Code accounts, as entries such as "Work=~/.claude-work": a name and the folder that
# CLAUDE_CONFIG_DIR names for that account, or the folder alone. The Claude setting covers them too.
extras=""
[ "$CLAUDE" = Off ] || extras=$CLAUDE_ACCOUNTS

# With more than one account on, the widget shows the ones signed in on this Mac. One on alone must be.
show_claude=true
show_codex=true
[ "$CLAUDE" != Off ] || show_claude=false
[ "$CODEX" != Off ] || show_codex=false
both=false
$show_claude && { $show_codex || [ -n "$extras" ]; } && both=true

if $show_claude; then
  status=0
  credentials=$(security find-generic-password -s "Claude Code-credentials$main_suffix" -w 2>/dev/null) || status=$?
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

if ! $show_claude && ! $show_codex && [ -z "$extras" ]; then
  echo "Neither Claude Code nor Codex is signed in on this Mac." >&2
  exit 1
fi

if $show_claude; then
  provider=Claude app="Claude Code" host=api.anthropic.com saved="$CONFIG_DIR/ai-usage-claude$main_suffix.json"
  limits=$CLAUDE
  json=$credentials
  claude_usage
  add_provider asterisk Claude https://claude.ai/settings/usage ""
fi

# The Keychain items already shown, so that a folder listed twice, or the main account's, shows once.
seen="[$main_suffix]"
while IFS= read -r entry; do
  entry=$(printf '%s' "$entry" | sed 's/^ *//; s/ *$//')
  [ -n "$entry" ] || continue
  case $entry in
    *=*)
      name=$(printf '%s' "${entry%%=*}" | sed 's/ *$//')
      written=$(printf '%s' "${entry#*=}" | sed 's/^ *//')
      ;;
    *) name="" written=$entry ;;
  esac
  folder=$written
  case $folder in \~/*) folder="$HOME/${folder#\~/}" ;; esac
  suffix=""
  [ "$folder" = "$HOME/.claude" ] || suffix=$(hashed "$folder")
  case $seen in *"[$suffix]"*) continue ;; esac
  seen="${seen}[$suffix]"
  heading=${name:-$written}
  provider="Claude $heading" app="Claude Code" host=api.anthropic.com saved="$CONFIG_DIR/ai-usage-claude$suffix.json"
  limits=$CLAUDE
  plan=""
  status=0
  json=$(security find-generic-password -s "Claude Code-credentials$suffix" -w 2>/dev/null) || status=$?
  if [ "$status" = 0 ]; then
    claude_usage
  elif [ "$status" = 44 ]; then
    json="" note="Claude Code isn't signed in with $written."
  else
    json="" note="StableBar couldn't read the sign-in for $written from the Keychain."
  fi
  # Only a name the entry gives goes on the bar; the popup and the tooltip name the folder otherwise.
  add_provider asterisk "Claude · $heading" https://claude.ai/settings/usage "$name"
done <<END
$(printf '%s' "$extras" | tr ',' '\n')
END

if $show_codex; then
  provider=Codex app=Codex host=chatgpt.com saved="$CONFIG_DIR/ai-usage-codex.json"
  limits=$CODEX
  json=$(cat "$HOME/.codex/auth.json")
  token=$(read_json tokens.access_token)
  account=$(read_json tokens.account_id)
  fetch -H "Authorization: Bearer $token" -H "ChatGPT-Account-Id: $account" \
    "https://chatgpt.com/backend-api/wham/usage"
  plan=""
  if [ -n "$json" ]; then
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
  fi
  add_provider terminal Codex https://chatgpt.com/codex/settings/usage ""
fi

if [ -z "$bar" ]; then
  echo "$failures" >&2
  exit 1
fi

printf '{"text":"%s","tooltip":"%s","interval":%s,"styles":{"stale":{"opacity":0.55}},"fields":{"updated":"Updated at %s"},"lists":{"popup":[%s],"bar":[%s]}}\n' \
  "$summary" "$summary" "$interval" "$(date -r "$updated" +%H:%M)" "$popup" "$bar"
