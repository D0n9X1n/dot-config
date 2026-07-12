#!/usr/bin/env bash
# Per-session Claude Code subagent admission guard.
#
# Modes are wired from ~/.claude/settings.json:
#   reserve  PreToolUse         Atomically reserve one of 10 slots.
#   complete PostToolUse        Release foreground runs or bind background
#                               tool_use_id -> agentId for SubagentStop.
#   fail     PostToolUseFailure Release a failed launch reservation.
#   stop     SubagentStop       Release by agent_id at actual completion.
#
# State lives under $TMPDIR/claude-subagents-$USER. The .state file is the
# authority; the integer file is retained for external readers. Records are:
#   R<TAB>tool_use_id                 reserved, launch response pending
#   A<TAB>tool_use_id<TAB>agent_id    launched and still running
#   S<TAB>agent_id                    stop observed; reconciles a late response
#
# Every read-modify-write is serialized with an atomic mkdir lock. Admission
# fails closed if input, state, locking, or persistence cannot be trusted.
# Release failures leak a slot rather than risk admitting an 11th subagent.
#
# Bash 3.2-compatible (macOS default).

set -euo pipefail
umask 077

limit=10
mode="${1:-}"
case "$mode" in
  reserve | complete | fail | stop) ;;
  *) exit 0 ;;
esac

state_dir=""
counter=""
state=""
seen=""
lock=""
tmp_state=""
lock_held=0

cleanup() {
  if [ -n "$tmp_state" ]; then
    rm -f "$tmp_state" 2>/dev/null || true
  fi
  if [ "$lock_held" -eq 1 ]; then
    rmdir "$lock" 2>/dev/null || true
  fi
  return 0
}
trap cleanup EXIT

deny_limit() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Claude Code subagent safety limit reached (10 running). Wait for an existing subagent to finish before starting another."}}'
  exit 0
}

deny_unavailable() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Subagent launch blocked because the 10-agent safety counter could not be verified. Restart Claude Code if the counter remains unavailable."}}'
  exit 0
}

safe_exit() {
  if [ "$mode" = "reserve" ]; then
    deny_unavailable
  fi
  exit 0
}

# Unexpected top-level failures during admission must deny, not silently allow.
# ERR is intentionally not inherited by command-substitution subshells: their
# statuses are checked explicitly so denial JSON cannot contaminate parsed data.
on_error() {
  set +e
  safe_exit
}
trap on_error ERR

on_signal() {
  set +e
  safe_exit
}
trap on_signal HUP INT TERM

valid_id() {
  case "$1" in
    '' | . | .. | *[!A-Za-z0-9_.:-]*) return 1 ;;
    *) return 0 ;;
  esac
}

payload=""
if [ ! -t 0 ]; then
  if ! payload="$(cat 2>/dev/null)"; then
    safe_exit
  fi
fi

# jq validates the complete JSON document. A regex fallback could extract IDs
# from malformed input and would therefore violate fail-closed admission.
if ! command -v jq >/dev/null 2>&1; then
  safe_exit
fi
separator=$'\037'
if ! parsed="$(printf '%s' "$payload" | jq -er '
  [
    (.session_id // ""),
    (.hook_event_name // ""),
    (.tool_name // ""),
    (.tool_use_id // ""),
    (.tool_response.status // ""),
    (.tool_response.agentId // .tool_response.agent_id // ""),
    (if ((.tool_input | type) == "object" and (.tool_input | has("run_in_background")))
      then (.tool_input.run_in_background | tostring)
      else "missing"
    end),
    (.agent_id // ""),
    "END"
  ]
  | map(if type == "string" then . else tostring end)
  | join("")
' 2>/dev/null)"; then
  safe_exit
fi

session_id=""
event_name=""
tool_name=""
tool_use_id=""
response_status=""
response_agent_id=""
background_mode=""
agent_id=""
end_marker=""
IFS="$separator" read -r session_id event_name tool_name tool_use_id \
  response_status response_agent_id background_mode agent_id end_marker <<EOF
$parsed
EOF

[ "$end_marker" = "END" ] || safe_exit
valid_id "$session_id" || safe_exit

case "$mode" in
  reserve)
    [ "$event_name" = "PreToolUse" ] || safe_exit
    case "$tool_name" in Agent | Task) ;; *) safe_exit ;; esac
    valid_id "$tool_use_id" || safe_exit
    ;;
  complete)
    [ "$event_name" = "PostToolUse" ] || exit 0
    case "$tool_name" in Agent | Task) ;; *) exit 0 ;; esac
    valid_id "$tool_use_id" || exit 0
    if [ -n "$response_agent_id" ]; then
      valid_id "$response_agent_id" || exit 0
    fi
    ;;
  fail)
    [ "$event_name" = "PostToolUseFailure" ] || exit 0
    case "$tool_name" in Agent | Task) ;; *) exit 0 ;; esac
    valid_id "$tool_use_id" || exit 0
    ;;
  stop)
    [ "$event_name" = "SubagentStop" ] || exit 0
    valid_id "$agent_id" || exit 0
    ;;
esac

if [ -n "${CLAUDE_SUBAGENT_STATE_DIR:-}" ]; then
  state_dir="$CLAUDE_SUBAGENT_STATE_DIR"
else
  state_dir="${TMPDIR:-/tmp}/claude-subagents-${USER:-default}"
fi
if ! mkdir -p "$state_dir" 2>/dev/null || ! chmod 700 "$state_dir" 2>/dev/null; then
  safe_exit
fi

counter="$state_dir/$session_id"
state="$counter.state"
seen="$counter.seen"
lock="$counter.lock"

i=0
while ! mkdir "$lock" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -gt 50 ]; then
    safe_exit
  fi
  if ! sleep 0.01; then
    safe_exit
  fi
done
lock_held=1

validate_state() {
  awk -F '\t' '
    BEGIN { count = 0; bad = 0 }
    function valid(value) {
      return value ~ /^[A-Za-z0-9_.:-]+$/ && value != "." && value != ".."
    }
    $1 == "R" && NF == 2 && valid($2) {
      if (tools[$2]++) bad = 1
      count++
      next
    }
    $1 == "A" && NF == 3 && valid($2) && valid($3) {
      if (tools[$2]++ || agents[$3]++) bad = 1
      count++
      next
    }
    $1 == "S" && NF == 2 && valid($2) {
      if (agents[$2]++) bad = 1
      next
    }
    { bad = 1 }
    END {
      if (bad) exit 1
      print count
    }
  ' "$1"
}

# A nonzero legacy counter cannot be correlated safely after upgrading from the
# old count-only format. Keep the session closed until restart rather than
# forgetting potentially live agents. A zero counter migrates to empty state.
if [ ! -e "$state" ]; then
  if [ -s "$seen" ]; then
    safe_exit
  fi
  if [ -e "$counter" ]; then
    legacy_count=""
    if [ ! -f "$counter" ] || [ -L "$counter" ] \
       || ! read -r legacy_count <"$counter"; then
      safe_exit
    fi
    case "$legacy_count" in '' | *[!0-9]*) safe_exit ;; esac
    [ "$legacy_count" -eq 0 ] || safe_exit
  fi
  if ! tmp_state="$(mktemp "$state.tmp.XXXXXX")"; then
    safe_exit
  fi
  if ! mv -f "$tmp_state" "$state"; then
    safe_exit
  fi
  tmp_state=""
fi

if [ ! -f "$state" ] || [ -L "$state" ]; then
  safe_exit
fi
if ! active_count="$(validate_state "$state")"; then
  safe_exit
fi

has_tool() {
  awk -F '\t' -v id="$1" '
    ($1 == "R" || $1 == "A") && $2 == id { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' "$state"
}

has_agent_mapping() {
  awk -F '\t' -v id="$1" '
    $1 == "A" && $3 == id { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' "$state"
}

has_tombstone() {
  awk -F '\t' -v id="$1" '
    $1 == "S" && $2 == id { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' "$state"
}


new_state() {
  tmp_state="$(mktemp "$state.tmp.XXXXXX")" || return 1
}

commit_state() {
  local next_count count_tmp
  if ! next_count="$(validate_state "$tmp_state")"; then
    return 1
  fi

  # With no active reservations, no future response can need a tombstone.
  # Clearing them bounds state growth from duplicate/late stop events.
  if [ "$next_count" -eq 0 ]; then
    : >"$tmp_state" || return 1
  fi

  mv -f "$tmp_state" "$state" || return 1
  tmp_state=""

  # The integer counter is compatibility/display data. Admission always derives
  # its count from the validated state file above, so this update is best-effort.
  count_tmp="$(mktemp "$counter.tmp.XXXXXX")" || return 0
  if ! printf '%s\n' "$next_count" >"$count_tmp" \
     || ! mv -f "$count_tmp" "$counter"; then
    rm -f "$count_tmp" 2>/dev/null || true
  fi
  if [ "$next_count" -eq 0 ]; then
    rm -f "$seen" 2>/dev/null || true
  fi
  return 0
}

remove_tool() {
  local id="$1" stopped_id="${2:-}"
  new_state || return 1
  awk -F '\t' -v OFS='\t' -v tool="$id" -v stopped="$stopped_id" '
    ($1 == "R" || $1 == "A") && $2 == tool { next }
    stopped != "" && $1 == "S" && $2 == stopped { next }
    { print }
  ' "$state" >"$tmp_state" || return 1
  commit_state
}

bind_or_reconcile() {
  local tool="$1" launched_agent="$2"
  new_state || return 1
  if has_tombstone "$launched_agent"; then
    awk -F '\t' -v OFS='\t' -v tool="$tool" -v agent="$launched_agent" '
      ($1 == "R" || $1 == "A") && $2 == tool { next }
      $1 == "S" && $2 == agent { next }
      { print }
    ' "$state" >"$tmp_state" || return 1
  else
    awk -F '\t' -v OFS='\t' -v tool="$tool" -v agent="$launched_agent" '
      $1 == "R" && $2 == tool { print "A", tool, agent; next }
      $1 == "A" && $2 == tool && $3 == agent { print; next }
      { print }
    ' "$state" >"$tmp_state" || return 1
  fi
  commit_state
}

case "$mode" in
  reserve)
    # Re-running PreToolUse for the same tool call is idempotent and does not
    # consume a second slot, even when all 10 slots are occupied.
    if has_tool "$tool_use_id"; then
      exit 0
    fi
    if [ "$active_count" -ge "$limit" ]; then
      deny_limit
    fi
    if ! new_state || ! cp "$state" "$tmp_state" \
       || ! printf 'R\t%s\n' "$tool_use_id" >>"$tmp_state" \
       || ! commit_state; then
      deny_unavailable
    fi
    ;;

  complete)
    if ! has_tool "$tool_use_id"; then
      exit 0
    fi

    if [ "$response_status" = "completed" ]; then
      # Foreground Agent calls reach PostToolUse only after actual completion.
      remove_tool "$tool_use_id" "$response_agent_id" || exit 0
    elif [ -n "$response_agent_id" ]; then
      # Background launch responses carry agentId. Bind it to the reservation;
      # if SubagentStop won the race, its tombstone releases the slot now.
      bind_or_reconcile "$tool_use_id" "$response_agent_id" || exit 0
    elif [ "$background_mode" = "false" ]; then
      # Compatibility path for older synchronous Task responses without IDs.
      remove_tool "$tool_use_id" || exit 0
    fi
    # Unknown successful launch responses deliberately retain their reservation.
    # A leaked slot is safer than admitting an 11th live agent.
    ;;

  fail)
    if has_tool "$tool_use_id"; then
      remove_tool "$tool_use_id" || exit 0
    fi
    ;;

  stop)
    if has_agent_mapping "$agent_id"; then
      new_state || exit 0
      awk -F '\t' -v OFS='\t' -v agent="$agent_id" '
        $1 == "A" && $3 == agent { next }
        { print }
      ' "$state" >"$tmp_state" || exit 0
      # Retain one stop marker while other reservations remain so a duplicate
      # SubagentStop cannot be mistaken for a new out-of-order completion.
      printf 'S\t%s\n' "$agent_id" >>"$tmp_state" || exit 0
      commit_state || exit 0
    elif ! has_tombstone "$agent_id"; then
      # PostToolUse for a background launch may still be in flight.
      new_state || exit 0
      cp "$state" "$tmp_state" || exit 0
      printf 'S\t%s\n' "$agent_id" >>"$tmp_state" || exit 0
      commit_state || exit 0
    fi
    ;;
esac

exit 0
