#!/usr/bin/env bash
# Per-session running-subagent counter, driven by Claude Code hooks.
#
# Wired up in ~/.claude/settings.json under three events:
#   - PreToolUse  matcher=Task  -> mode=start
#   - PostToolUse matcher=Task  -> mode=stop
#   - SubagentStop              -> mode=stop  (covers background agents
#                                              whose PostToolUse fires
#                                              before the agent actually
#                                              finishes)
#
# Each hook invocation receives a JSON payload on stdin (we only need
# .session_id and .tool_use_id) and is passed the mode as $1. We maintain
# one counter file per session at:
#   $TMPDIR/claude-subagents-<session_id>
# containing a single integer (current count of running subagents).
#
# A sibling `seen` file (`<counter>.seen`) records tool_use_ids we've
# already counted, so duplicate events (PostToolUse + SubagentStop firing
# for the same id) don't double-decrement.
#
# Output is suppressed; hook stdout/stderr never reach the user UI in
# normal operation, but we explicitly `>/dev/null` to avoid any risk of
# polluting Claude Code's pane.
#
# Bash 3.2-compatible (macOS default). Exits 0 unconditionally so a
# transient failure (e.g. disk full, jq missing) never blocks Claude.

set -u

mode="${1:-}"
case "$mode" in
  start | stop) ;;
  *) exit 0 ;;
esac

payload=""
if [ ! -t 0 ]; then
  payload="$(cat 2>/dev/null || true)"
fi

# Extract session_id and tool_use_id. Prefer jq when available; fall back
# to a bash regex so the counter still works without jq on PATH.
session_id=""
tool_use_id=""
if [ -n "$payload" ]; then
  if command -v jq >/dev/null 2>&1; then
    session_id="$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null)"
    tool_use_id="$(printf '%s' "$payload" | jq -r '
      .tool_use_id //
      .tool_input.tool_use_id //
      .tool_response.tool_use_id //
      .tool_call_id //
      ""
    ' 2>/dev/null)"
  else
    if [[ "$payload" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
      session_id="${BASH_REMATCH[1]}"
    fi
    if [[ "$payload" =~ \"tool_use_id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
      tool_use_id="${BASH_REMATCH[1]}"
    fi
  fi
fi

# Without a session_id we can't isolate this run's counter. Bail quietly.
[ -n "$session_id" ] || exit 0

dir="${TMPDIR:-/tmp}/claude-subagents-${USER:-default}"
mkdir -p "$dir" 2>/dev/null || exit 0
counter="$dir/$session_id"
seen="$counter.seen"
lock="$counter.lock"

# Acquire a short lock (mkdir is atomic on POSIX). Spin briefly; bail
# rather than hang if something is wedged.
i=0
while ! mkdir "$lock" 2>/dev/null; do
  i=$((i + 1))
  [ "$i" -gt 50 ] && exit 0
  sleep 0.01 2>/dev/null || true
done
trap 'rmdir "$lock" 2>/dev/null || true' EXIT

# Stale-lock cleanup: if the dir is older than 5s, kill it next round.
# (Not done here since we already hold it; the next caller will if needed.)

cur=0
if [ -f "$counter" ]; then
  read -r cur <"$counter" 2>/dev/null || cur=0
fi
case "$cur" in '' | *[!0-9-]*) cur=0 ;; esac

case "$mode" in
  start)
    if [ -n "$tool_use_id" ]; then
      # Dedup: if we've already counted this tool_use_id, no-op.
      if [ -f "$seen" ] && grep -Fxq "start:$tool_use_id" "$seen" 2>/dev/null; then
        :
      else
        cur=$((cur + 1))
        printf 'start:%s\n' "$tool_use_id" >>"$seen"
      fi
    else
      # No id available; count it anyway (rare path).
      cur=$((cur + 1))
    fi
    ;;
  stop)
    if [ -n "$tool_use_id" ]; then
      # Only decrement if we previously counted a start for this id AND
      # haven't already counted a stop for it.
      if grep -Fxq "start:$tool_use_id" "$seen" 2>/dev/null \
         && ! grep -Fxq "stop:$tool_use_id" "$seen" 2>/dev/null; then
        cur=$((cur - 1))
        printf 'stop:%s\n' "$tool_use_id" >>"$seen"
      fi
    else
      # No id (e.g. SubagentStop without tool_use_id in some Claude
      # versions): conservative decrement, clamped at 0 below.
      cur=$((cur - 1))
    fi
    ;;
esac

[ "$cur" -lt 0 ] && cur=0
printf '%s\n' "$cur" >"$counter" 2>/dev/null || true

# Trim seen file when counter hits 0 to prevent unbounded growth.
if [ "$cur" -eq 0 ] && [ -f "$seen" ]; then
  : >"$seen" 2>/dev/null || true
fi

exit 0
