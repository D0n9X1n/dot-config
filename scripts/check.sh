#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
CHECK_STATE_DIR=""
CHECK_EVENTS=""
CHECK_CLAUDE_AGENT_STATE_DIR=""

run_bash_syntax() {
  local fail=0
  local file
  while IFS= read -r file; do
    echo "bash -n $file"
    bash -n "$file" || fail=1
  done < <(git ls-files '*.sh' | sort -u)
  [ "$fail" -eq 0 ]
}

run_statusline_smoke() {
  local out
  out="$(echo '{}' | bash claude/statusline.sh)"
  [ -n "$out" ] && echo "claude statusline ok: ${#out} bytes"

  out="$(echo '{"model":{"display_name":"Claude (xhigh)"}}' | bash copilot/statusline.sh)"
  [ -n "$out" ] && echo "copilot statusline ok: ${#out} bytes"
}

run_shellcheck() {
  local files
  command -v shellcheck >/dev/null 2>&1 || {
    echo "shellcheck not found" >&2
    return 1
  }

  files="$(find . -path './.git' -prune -o -type f \( \
    -name '*.bash' \
    -o -name '.bashrc' \
    -o -name 'bashrc' \
    -o -name '.bash_aliases' \
    -o -name '.bash_completion' \
    -o -name '.bash_login' \
    -o -name '.bash_logout' \
    -o -name '.bash_profile' \
    -o -name 'bash_profile' \
    -o -name '*.ksh' \
    -o -name 'suid_profile' \
    -o -name '*.zsh' \
    -o -name '.zlogin' \
    -o -name 'zlogin' \
    -o -name '.zlogout' \
    -o -name 'zlogout' \
    -o -name '.zprofile' \
    -o -name 'zprofile' \
    -o -name '.zsenv' \
    -o -name 'zsenv' \
    -o -name '.zshrc' \
    -o -name 'zshrc' \
    -o -name '*.sh' \
    -o -path '*/.profile' \
    -o -path '*/profile' \
    -o -name '*.shlib' \
    -o -name '*install.sh' \
  \) -print)"

  # shellcheck disable=SC2086
  shellcheck -S error -e SC1090 -e SC1091 -e SC2155 -e SC2148 $files
}

run_zsh_syntax() {
  command -v zsh >/dev/null 2>&1 || return 0
  zsh -n oh-my-zsh-custom/custom.zsh
}

run_subagent_smoke() {
  local state_dir payload out events
  state_dir="$(mktemp -d)"
  CHECK_STATE_DIR="$state_dir"
  CHECK_EVENTS=""
  trap 'rm -rf "${CHECK_STATE_DIR:-}" "${CHECK_EVENTS:-}"' EXIT

  payload='{"sessionId":"ci-session","toolCallId":"call_1","agentDisplayName":"Explorer","agentDescription":"trace subagents"}'
  printf '%s' "$payload" |
    COPILOT_STATUSLINE_SUBAGENT_STATE_DIR="$state_dir" bash copilot/subagent-state.sh start

  out="$(printf '{"sessionId":"ci-session","model":{"display_name":"Claude (xhigh)"}}' |
    COPILOT_STATUSLINE_SUBAGENT_STATE_DIR="$state_dir" COPILOT_STATUSLINE_NO_COLOR=1 bash copilot/statusline.sh)"
  printf '%s' "$out" | grep -q -- '----------------------------------------'
  printf '%s' "$out" | grep -q -- 'Explorer'
  printf '%s' "$out" | grep -q -- 'Tasks 1'

  printf '%s' '{"sessionId":"ci-session","toolCallId":"call_1","agentDisplayName":"Explorer"}' |
    COPILOT_STATUSLINE_SUBAGENT_STATE_DIR="$state_dir" bash copilot/subagent-state.sh stop
  out="$(printf '{"sessionId":"ci-session","model":{"display_name":"Claude (xhigh)"}}' |
    COPILOT_STATUSLINE_SUBAGENT_STATE_DIR="$state_dir" COPILOT_STATUSLINE_NO_COLOR=1 bash copilot/statusline.sh)"
  ! printf '%s' "$out" | grep -q -- 'Explorer'

  events="$(mktemp)"
  CHECK_EVENTS="$events"
  cat >"$events" <<'JSON'
{"type":"subagent.started","timestamp":"2026-06-07T19:30:00.000Z","data":{"toolCallId":"call_a","agentName":"explore","agentDisplayName":"Explore Agent","agentDescription":"review repo"}}
JSON
  out="$(printf '{"sessionId":"fallback-session","transcriptPath":"%s","model":{"display_name":"Claude (xhigh)"}}' "$events" |
    COPILOT_STATUSLINE_SUBAGENT_STATE_DIR="$state_dir-missing" COPILOT_STATUSLINE_NO_COLOR=1 bash copilot/statusline.sh)"
  printf '%s' "$out" | grep -q -- 'Explore Agent'
  printf '%s' "$out" | grep -q -- 'Tasks 1'
  echo "copilot subagent statusline ok"
}

run_claude_subagent_limit_smoke() {
  local hook state_dir session denied out i admitted state_count
  local tool_1 tool_2 tool_3 tool_4
  local pids=""
  hook="claude/hooks/subagent-counter.sh"
  state_dir="$(mktemp -d)"
  CHECK_CLAUDE_AGENT_STATE_DIR="$state_dir"
  session="limit-session"
  trap 'rm -rf "${CHECK_STATE_DIR:-}" "${CHECK_EVENTS:-}" "${CHECK_CLAUDE_AGENT_STATE_DIR:-}"' EXIT

  reserve() {
    local id="$1"
    printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"Agent","tool_use_id":"%s","tool_input":{}}' "$session" "$id" |
      CLAUDE_SUBAGENT_STATE_DIR="$state_dir" bash "$hook" reserve
  }

  complete_background() {
    local tool_id="$1" agent_id="$2"
    printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"Agent","tool_use_id":"%s","tool_input":{"run_in_background":true},"tool_response":{"status":"async_launched","agentId":"%s"}}' "$session" "$tool_id" "$agent_id" |
      CLAUDE_SUBAGENT_STATE_DIR="$state_dir" bash "$hook" complete
  }

  stop_agent() {
    local agent_id="$1"
    printf '{"session_id":"%s","hook_event_name":"SubagentStop","agent_id":"%s"}' "$session" "$agent_id" |
      CLAUDE_SUBAGENT_STATE_DIR="$state_dir" bash "$hook" stop
  }

  # More than 10 simultaneous PreToolUse events must still reserve exactly 10.
  i=1
  while [ "$i" -le 24 ]; do
    (reserve "race_$i" >"$state_dir/out.$i") &
    pids="$pids $!"
    i=$((i + 1))
  done
  for i in $pids; do
    wait "$i"
  done
  admitted="$(awk -F '\t' '$1 == "R" || $1 == "A" { count++ } END { print count + 0 }' "$state_dir/$session.state")"
  [ "$admitted" -eq 10 ]
  [ "$(cat "$state_dir/$session")" -eq 10 ]
  denied="$(grep -l 'permissionDecision.*deny' "$state_dir"/out.* | wc -l | tr -d ' ')"
  [ "$denied" -eq 14 ]
  tool_1="$(awk -F '\t' '($1 == "R" || $1 == "A") && ++count == 1 { print $2; exit }' "$state_dir/$session.state")"
  tool_2="$(awk -F '\t' '($1 == "R" || $1 == "A") && ++count == 2 { print $2; exit }' "$state_dir/$session.state")"
  tool_3="$(awk -F '\t' '($1 == "R" || $1 == "A") && ++count == 3 { print $2; exit }' "$state_dir/$session.state")"
  tool_4="$(awk -F '\t' '($1 == "R" || $1 == "A") && ++count == 4 { print $2; exit }' "$state_dir/$session.state")"
  [ -n "$tool_1" ] && [ -n "$tool_2" ] && [ -n "$tool_3" ] && [ -n "$tool_4" ]

  # A duplicate PreToolUse event is idempotent even when the cap is full.
  out="$(reserve "$tool_1")"
  [ -z "$out" ]
  state_count="$(awk -F '\t' '$1 == "R" || $1 == "A" { count++ } END { print count + 0 }' "$state_dir/$session.state")"
  [ "$state_count" -eq 10 ]

  # The 11th distinct call is denied with Claude Code's current hook schema.
  out="$(reserve overflow)"
  printf '%s' "$out" | jq -e '
    .hookSpecificOutput.hookEventName == "PreToolUse" and
    .hookSpecificOutput.permissionDecision == "deny" and
    (.hookSpecificOutput.permissionDecisionReason | contains("10"))
  ' >/dev/null

  # An async launch remains counted until SubagentStop, then a slot reopens.
  complete_background "$tool_1" agent_1
  grep -F "$(printf 'A\t%s\tagent_1' "$tool_1")" "$state_dir/$session.state" >/dev/null
  [ "$(cat "$state_dir/$session")" -eq 10 ]
  stop_agent agent_1
  stop_agent agent_1
  [ "$(cat "$state_dir/$session")" -eq 9 ]
  out="$(reserve replacement)"
  [ -z "$out" ]
  [ "$(cat "$state_dir/$session")" -eq 10 ]

  # SubagentStop may win the race with PostToolUse; the tombstone reconciles it.
  stop_agent agent_2
  complete_background "$tool_2" agent_2
  ! grep -Fq "$(printf 'R\t%s' "$tool_2")" "$state_dir/$session.state"
  ! grep -Fq "$(printf 'A\t%s\tagent_2' "$tool_2")" "$state_dir/$session.state"
  ! grep -Fq $'S\tagent_2' "$state_dir/$session.state"
  [ "$(cat "$state_dir/$session")" -eq 9 ]

  # A failed launch and a completed foreground call each release exactly once.
  printf '{"session_id":"%s","hook_event_name":"PostToolUseFailure","tool_name":"Agent","tool_use_id":"%s","tool_input":{},"error":"launch failed"}' "$session" "$tool_3" |
    CLAUDE_SUBAGENT_STATE_DIR="$state_dir" bash "$hook" fail
  [ "$(cat "$state_dir/$session")" -eq 8 ]
  printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"Agent","tool_use_id":"%s","tool_input":{"run_in_background":false},"tool_response":{"status":"completed","agentId":"agent_4"}}' "$session" "$tool_4" |
    CLAUDE_SUBAGENT_STATE_DIR="$state_dir" bash "$hook" complete
  [ "$(cat "$state_dir/$session")" -eq 7 ]

  # Admission fails closed for malformed/missing IDs, corrupt state, state-dir
  # failure, or lock timeout.
  out="$(printf '{bad json' | CLAUDE_SUBAGENT_STATE_DIR="$state_dir" bash "$hook" reserve)"
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
  out="$(printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{}}' "$session" |
    CLAUDE_SUBAGENT_STATE_DIR="$state_dir" bash "$hook" reserve)"
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
  printf 'invalid\n' >"$state_dir/$session.state"
  out="$(reserve corrupt_call)"
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
  : >"$state_dir/not-a-directory"
  out="$(printf '{"session_id":"storage-session","hook_event_name":"PreToolUse","tool_name":"Agent","tool_use_id":"storage_call","tool_input":{}}' |
    CLAUDE_SUBAGENT_STATE_DIR="$state_dir/not-a-directory" bash "$hook" reserve)"
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null

  session="locked-session"
  mkdir "$state_dir/$session.lock"
  out="$(reserve locked_call)"
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null

  echo "claude subagent limit ok: 10 admitted, 14 denied"
}

run_smoke() {
  run_bash_syntax
  run_statusline_smoke
  bash -n install.sh
  run_zsh_syntax
  run_subagent_smoke
  run_claude_subagent_limit_smoke
}

case "${1:-all}" in
  smoke) run_smoke ;;
  shellcheck) run_shellcheck ;;
  all) run_smoke; run_shellcheck ;;
  *)
    echo "usage: $0 [smoke|shellcheck|all]" >&2
    exit 2
    ;;
esac
