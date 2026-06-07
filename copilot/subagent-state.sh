#!/usr/bin/env bash
# Maintain per-session Copilot subagent rows for the statusline.
#
# Wired from ~/.copilot/settings.json:
#   subagentStart -> start
#   subagentStop  -> stop
#   sessionStart/sessionEnd -> reset
#
# The statusline reads the tiny rows file written here instead of scanning
# events.jsonl on every redraw.

set -u

mode="${1:-}"
case "$mode" in
  start | stop | reset) ;;
  *) exit 0 ;;
esac

payload=""
if [ ! -t 0 ]; then
  payload="$(cat 2>/dev/null || true)"
fi

json_get() {
  local expr="$1" key="$2"
  if [ -n "$payload" ] && command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r "$expr // \"\"" 2>/dev/null
    return 0
  fi
  if [[ "$payload" =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

clean_field() {
  local value="$1"
  local us=$'\037'
  value="${value//$us/ }"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  value="${value//$'\t'/ }"
  printf '%s' "$value" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//; s/^(.{0,140}).*$/\1/'
}

session_id="$(json_get '.sessionId // .session_id' 'sessionId')"
[ -n "$session_id" ] || exit 0

dir="${COPILOT_STATUSLINE_SUBAGENT_STATE_DIR:-${TMPDIR:-/tmp}/copilot-subagents-${USER:-default}}"
mkdir -p "$dir" 2>/dev/null || exit 0
key="$(printf '%s' "$session_id" | cksum | awk '{print $1}')"
rows="$dir/$key.rows"
lock="$dir/$key.lock"
us=$'\037'

i=0
while ! mkdir "$lock" 2>/dev/null; do
  i=$((i + 1))
  [ "$i" -gt 50 ] && exit 0
  sleep 0.01 2>/dev/null || true
done
trap 'rmdir "$lock" 2>/dev/null || true' EXIT

case "$mode" in
  reset)
    rm -f "$rows" 2>/dev/null || true
    ;;
  start)
    agent_name="$(clean_field "$(json_get '.agentName // .agent_name' 'agentName')")"
    agent_display="$(clean_field "$(json_get '.agentDisplayName // .agent_display_name' 'agentDisplayName')")"
    agent_description="$(clean_field "$(json_get '.agentDescription // .agent_description' 'agentDescription')")"
    display_name="${agent_display:-$agent_name}"
    [ -n "$display_name" ] || display_name="agent"
    started_at="$(date +%s 2>/dev/null || printf '0')"
    printf '%s%s%s%s%s\n' "$display_name" "$us" "$agent_description" "$us" "$started_at" >>"$rows" 2>/dev/null || true
    ;;
  stop)
    [ -f "$rows" ] || exit 0
    agent_name="$(clean_field "$(json_get '.agentName // .agent_name' 'agentName')")"
    agent_display="$(clean_field "$(json_get '.agentDisplayName // .agent_display_name' 'agentDisplayName')")"
    tmp="${rows}.$$"
    awk -v us="$us" -v name="$agent_name" -v display="$agent_display" '
      BEGIN { FS = us; OFS = us; removed = 0 }
      {
        row_name = $1
        if (!removed && ((name != "" && row_name == name) || (display != "" && row_name == display) || (name == "" && display == ""))) {
          removed = 1
          next
        }
        print
      }
    ' "$rows" >"$tmp" 2>/dev/null && mv "$tmp" "$rows" 2>/dev/null || rm -f "$tmp"
    [ -s "$rows" ] || rm -f "$rows" 2>/dev/null || true
    ;;
esac

exit 0
