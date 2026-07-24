#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
CHECK_STATE_DIR=""
CHECK_EVENTS=""

run_bash_syntax() {
  local fail=0
  local file
  while IFS= read -r file; do
    [ -f "$file" ] || continue
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
  jq -e '
    .env.CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS == "16" and
    ((.hooks // {}) | tostring | contains("subagent-counter.sh") | not)
  ' claude/settings.json >/dev/null
  [ ! -e claude/hooks/subagent-counter.sh ]

  (
    local test_root test_home test_repo fake_bin
    DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh
    version_at_least 2.1.217 2.1.217
    version_at_least 2.1.218 2.1.217
    version_at_least 2.10.0 2.9.999
    if version_at_least 2.1.216 2.1.217; then
      echo "version check admitted a below-minimum release" >&2
      exit 1
    fi
    if version_at_least 2.1 2.1.217; then
      echo "version check admitted a truncated release" >&2
      exit 1
    fi
    if version_at_least bad 2.1.217; then
      echo "version check admitted a malformed release" >&2
      exit 1
    fi

    test_root="$(mktemp -d)"
    trap 'rm -rf "$test_root"' EXIT
    test_home="$test_root/home"
    test_repo="$test_root/repo"
    fake_bin="$test_root/bin"
    mkdir -p "$test_home/.claude/hooks" "$test_repo/claude/hooks" "$fake_bin"
    cat >"$fake_bin/claude" <<'SH'
#!/usr/bin/env bash
printf '2.1.218 (Claude Code)\n'
SH
    cat >"$fake_bin/brew" <<'SH'
#!/usr/bin/env bash
: >"$BREW_CALLED"
exit 1
SH
    chmod +x "$fake_bin/claude" "$fake_bin/brew"
    [ "$(PATH="$fake_bin:$PATH" claude_code_version)" = "2.1.218" ]
    PATH="$fake_bin:$PATH" BREW_CALLED="$test_root/brew-called" \
      ensure_claude_code_min_version 2.1.217 >/dev/null
    [ ! -e "$test_root/brew-called" ]

    HOME="$test_home"
    src_dir="$test_repo"
    ln -s "$test_repo/claude/hooks/subagent-counter.sh" \
      "$test_home/.claude/hooks/subagent-counter.sh"
    printf 'keep\n' >"$test_home/.claude/hooks/user-hook.sh"
    remove_legacy_claude_subagent_hook >/dev/null
    [ ! -e "$test_home/.claude/hooks/subagent-counter.sh" ]
    [ -f "$test_home/.claude/hooks/user-hook.sh" ]

    ln -s "$test_root/other-hook.sh" "$test_home/.claude/hooks/subagent-counter.sh"
    remove_legacy_claude_subagent_hook >/dev/null
    [ -L "$test_home/.claude/hooks/subagent-counter.sh" ]
    [ -f "$test_home/.claude/hooks/user-hook.sh" ]
  )
  echo "claude native subagent limit config ok: 16 (requires v2.1.217+)"
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
