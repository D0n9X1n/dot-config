#!/usr/bin/env bash
# Maintain per-session Copilot subagent rows for the statusline.
#
# Wired from ~/.copilot/settings.json:
#   subagentStart -> start
#   subagentStop  -> stop
#   sessionStart/sessionEnd -> reset
#
# The statusline reads the tiny rows file written here first; if a hook payload
# is missed, it can fall back to a signature-cached events.jsonl scan.

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
  local expr="$1"
  shift
  local key
  if [ -n "$payload" ] && command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r "$expr // \"\"" 2>/dev/null
    return 0
  fi
  for key in "$@"; do
    if [[ "$payload" =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      printf '%s' "${BASH_REMATCH[1]}"
      return 0
    fi
  done
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

session_id="$(json_get '.sessionId // .session_id // .session.id // .sessionID' sessionId session_id sessionID)"
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
    agent_name="$(clean_field "$(json_get '.agentName // .agent_name' agentName agent_name)")"
    agent_display="$(clean_field "$(json_get '.agentDisplayName // .agent_display_name' agentDisplayName agent_display_name)")"
    agent_description="$(clean_field "$(json_get '.agentDescription // .agent_description' agentDescription agent_description)")"
    tool_call_id="$(clean_field "$(json_get '.toolCallId // .tool_call_id // .toolUseId // .tool_use_id' toolCallId tool_call_id toolUseId tool_use_id)")"
    display_name="${agent_display:-$agent_name}"
    [ -n "$display_name" ] || display_name="agent"
    started_at="$(date +%s 2>/dev/null || printf '0')"
    printf '%s%s%s%s%s%s%s\n' "$tool_call_id" "$us" "$display_name" "$us" "$agent_description" "$us" "$started_at" >>"$rows" 2>/dev/null || true
    ;;
  stop)
    [ -f "$rows" ] || exit 0
    agent_name="$(clean_field "$(json_get '.agentName // .agent_name' agentName agent_name)")"
    agent_display="$(clean_field "$(json_get '.agentDisplayName // .agent_display_name' agentDisplayName agent_display_name)")"
    tool_call_id="$(clean_field "$(json_get '.toolCallId // .tool_call_id // .toolUseId // .tool_use_id' toolCallId tool_call_id toolUseId tool_use_id)")"
    tmp="${rows}.$$"
    awk -v us="$us" -v id="$tool_call_id" -v name="$agent_name" -v display="$agent_display" '
      BEGIN { FS = us; OFS = us; removed = 0 }
      {
        row_id = $1
        row_name = $2
        # Backward compatibility for the old 3-field rows: name, purpose, started.
        if (NF == 3) {
          row_id = ""
          row_name = $1
        }
        if (!removed && ((id != "" && row_id == id) || (id == "" && name != "" && row_name == name) || (id == "" && display != "" && row_name == display) || (id == "" && name == "" && display == ""))) {
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
