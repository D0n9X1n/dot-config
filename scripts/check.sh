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
  out="$(echo '{}' | bash config/claude/statusline.sh)"
  [ -n "$out" ] && echo "claude statusline ok: ${#out} bytes"

  out="$(echo '{"model":{"display_name":"Claude (xhigh)"}}' | bash config/copilot/statusline.sh)"
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
    -o -name '*.zsh-theme' \
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
  local file
  command -v zsh >/dev/null 2>&1 || return 0
  while IFS= read -r file; do
    zsh -n "$file"
  done < <(find config/zsh -type f \( -name '*.zsh' -o -name '*.zsh-theme' \) -print | sort)
}

run_subagent_smoke() {
  local state_dir payload out events
  state_dir="$(mktemp -d)"
  CHECK_STATE_DIR="$state_dir"
  CHECK_EVENTS=""
  trap 'rm -rf "${CHECK_STATE_DIR:-}" "${CHECK_EVENTS:-}"' EXIT

  payload='{"sessionId":"ci-session","toolCallId":"call_1","agentDisplayName":"Explorer","agentDescription":"trace subagents"}'
  printf '%s' "$payload" |
    COPILOT_STATUSLINE_SUBAGENT_STATE_DIR="$state_dir" bash config/copilot/subagent-state.sh start

  out="$(printf '{"sessionId":"ci-session","model":{"display_name":"Claude (xhigh)"}}' |
    COPILOT_STATUSLINE_SUBAGENT_STATE_DIR="$state_dir" COPILOT_STATUSLINE_NO_COLOR=1 bash config/copilot/statusline.sh)"
  printf '%s' "$out" | grep -q -- '----------------------------------------'
  printf '%s' "$out" | grep -q -- 'Explorer'
  printf '%s' "$out" | grep -q -- 'Tasks 1'

  printf '%s' '{"sessionId":"ci-session","toolCallId":"call_1","agentDisplayName":"Explorer"}' |
    COPILOT_STATUSLINE_SUBAGENT_STATE_DIR="$state_dir" bash config/copilot/subagent-state.sh stop
  out="$(printf '{"sessionId":"ci-session","model":{"display_name":"Claude (xhigh)"}}' |
    COPILOT_STATUSLINE_SUBAGENT_STATE_DIR="$state_dir" COPILOT_STATUSLINE_NO_COLOR=1 bash config/copilot/statusline.sh)"
  if printf '%s' "$out" | grep -q -- 'Explorer'; then
    echo "stopped Copilot subagent still appears in the status line" >&2
    return 1
  fi

  events="$(mktemp)"
  CHECK_EVENTS="$events"
  cat >"$events" <<'JSON'
{"type":"subagent.started","timestamp":"2026-06-07T19:30:00.000Z","data":{"toolCallId":"call_a","agentName":"explore","agentDisplayName":"Explore Agent","agentDescription":"review repo"}}
JSON
  out="$(printf '{"sessionId":"fallback-session","transcriptPath":"%s","model":{"display_name":"Claude (xhigh)"}}' "$events" |
    COPILOT_STATUSLINE_SUBAGENT_STATE_DIR="$state_dir-missing" COPILOT_STATUSLINE_NO_COLOR=1 bash config/copilot/statusline.sh)"
  printf '%s' "$out" | grep -q -- 'Explore Agent'
  printf '%s' "$out" | grep -q -- 'Tasks 1'
  echo "copilot subagent statusline ok"
}

run_claude_subagent_limit_smoke() {
  jq -e '
    .env.CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS == "16" and
    ((.hooks // {}) | tostring | contains("subagent-counter.sh") | not)
  ' config/claude/settings.json >/dev/null
  [ ! -e config/claude/hooks/subagent-counter.sh ]

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

run_model_default_smoke() {
  jq -e '
    .env.ANTHROPIC_MODEL == "claude-sonnet-5[1m]" and
    .model == "sonnet" and
    (has("effortLevel") | not) and
    .env.MODEL_REASONING_EFFORT == "max" and
    .env.ANTHROPIC_DEFAULT_SONNET_MODEL == "claude-sonnet-5[1m]" and
    (.env | has("ANTHROPIC_DEFAULT_SONNET_MODEL_NAME") | not) and
    (.env | has("ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION") | not) and
    .env.ANTHROPIC_DEFAULT_HAIKU_MODEL == "claude-haiku-4-5-20251001" and
    .env.ANTHROPIC_SMALL_FAST_MODEL == "claude-haiku-4-5-20251001" and
    .env.ANTHROPIC_BASE_URL == "http://127.0.0.1:4142" and
    .env.CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS == "16" and
    .autoCompactEnabled == true and
    .autoCompactWindow == 120000 and
    .env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE == "75" and
    .feedbackDrafts == "off" and
    .skipDangerousModePermissionPrompt == true and
    .skipAutoPermissionPrompt == true and
    .theme == "custom:apollo" and
    .permissions.defaultMode == "auto" and
    .statusLine.command == "~/.claude/statusline.sh" and
    .enabledPlugins["clangd-lsp@claude-plugins-official"] == true
  ' config/claude/settings.json >/dev/null

  # No GPT identity may leak back into any Claude-facing selector or label.
  if jq -e '
      [(.env | to_entries[] | select(.key | test("^ANTHROPIC_.*MODEL")) | .value),
       .model]
      | map(select(type == "string") | ascii_downcase)
      | any(test("gpt"))
    ' config/claude/settings.json >/dev/null; then
    echo "config/claude/settings.json carries a GPT identity on a Claude selector" >&2
    return 1
  fi

  # Copilot CLI: GPT-6 Astra at the 1M context tier and max effort.
  jq -e '
    .model == "gpt-6-astra" and
    .contextTier == "long_context" and
    .effortLevel == "max"
  ' config/copilot/settings.json >/dev/null

  # Relay: Opus remains separate; every non-Opus route uses GPT-6 Astra.
  grep -Eq '^opusModel:[[:space:]]*claude-opus-5$' config/copilot-relay/config.yaml
  grep -Eq '^gptModel:[[:space:]]*gpt-6-astra$' config/copilot-relay/config.yaml
  grep -Eq '^thinkEffort:[[:space:]]*max$' config/copilot-relay/config.yaml

  grep -Fq $'link\tconfig/copilot-relay/config.yaml\t.copilot-relay/config.yaml' config/manifest.tsv

  # Launcher wrappers inject the same defaults (settings.json can be rewritten
  # at runtime, so the flags are the authoritative per-launch pin).
  grep -Fq -- "--model 'claude-sonnet-5[1m]'" config/zsh/claude.zsh
  grep -Fq -- "--model 'claude-sonnet-5[1m]' --effort max" config/zsh/cc.zsh
  grep -Fq -- "--model gpt-6-astra --context long_context --effort max" config/zsh/gg.zsh
  if grep -Fq 'gpt-6-astra' config/zsh/claude.zsh config/zsh/cc.zsh; then
    echo "Claude launchers must not pin a GPT model id" >&2
    return 1
  fi

  # The `claude` wrapper injects native defaults but yields to explicit flags.
  (
    local test_root fake_bin capture args
    test_root="$(mktemp -d)"
    trap 'rm -rf "$test_root"' EXIT
    fake_bin="$test_root/bin"
    capture="$test_root/capture"
    mkdir -p "$fake_bin"
    cat >"$fake_bin/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CLAUDE_CAPTURE"
SH
    chmod +x "$fake_bin/claude"

    PATH="$fake_bin:$PATH" CLAUDE_CAPTURE="$capture" \
      zsh -c 'source config/zsh/claude.zsh; claude'
    args="$(sed -n '1p' "$capture")"
    case "$args" in
      *"--model claude-sonnet-5[1m]"*) : ;;
      *) echo "claude wrapper default lost the native Sonnet pin: $args" >&2; exit 1 ;;
    esac
    case "$args" in
      *'--effort max'*) : ;;
      *) echo "claude wrapper default lost --effort max: $args" >&2; exit 1 ;;
    esac
    case "$args" in
      *'--permission-mode bypassPermissions'*) : ;;
      *) echo "claude wrapper default lost bypassPermissions: $args" >&2; exit 1 ;;
    esac

    : >"$capture"
    PATH="$fake_bin:$PATH" CLAUDE_CAPTURE="$capture" \
      zsh -c 'source config/zsh/claude.zsh; claude --model opus'
    args="$(sed -n '1p' "$capture")"
    case "$args" in
      *'claude-sonnet-5'*) echo "explicit --model was overridden: $args" >&2; exit 1 ;;
    esac

    : >"$capture"
    PATH="$fake_bin:$PATH" CLAUDE_CAPTURE="$capture" \
      zsh -c 'source config/zsh/claude.zsh; claude --model=opus'
    args="$(sed -n '1p' "$capture")"
    case "$args" in
      *'claude-sonnet-5'*) echo "explicit --model= was overridden: $args" >&2; exit 1 ;;
    esac

    : >"$capture"
    PATH="$fake_bin:$PATH" CLAUDE_CAPTURE="$capture" \
      zsh -c 'source config/zsh/claude.zsh; claude --effort low'
    args="$(sed -n '1p' "$capture")"
    case "$args" in
      *'--effort max'*) echo "explicit --effort was overridden: $args" >&2; exit 1 ;;
    esac
    case "$args" in
      *"--model claude-sonnet-5[1m]"*) : ;;
      *) echo "explicit --effort dropped the model default: $args" >&2; exit 1 ;;
    esac
  )

  echo "model defaults ok: native Sonnet/Haiku client ids, relay maps non-Opus to GPT-6 Astra"
}

run_claude_github_mcp_warning_smoke() {
  local test_root maker secret out digest_before digest_after case_dir case_output
  test_root="$(mktemp -d)"
  trap 'rm -rf "${test_root:-}"' RETURN
  secret='ghu_FAKE_NOT_A_REAL_TOKEN_0123456789'
  maker="$test_root/make-case.py"
  out="$test_root/out.log"
  : >"$out"

  cat >"$maker" <<'PY'
import json
import os
import sys

case, root, secret = sys.argv[1], sys.argv[2], sys.argv[3]
endpoint = "https://api.githubcopilot.com/mcp"
os.makedirs(root, exist_ok=True)
path = os.path.join(root, ".claude.json")


def http_github(url=endpoint, headers=None, extra=None):
    server = {"type": "http", "url": url}
    if headers is not None:
        server["headers"] = headers
    if extra:
        server.update(extra)
    return server


def authed(name="Authorization"):
    return {"mcpServers": {"github": http_github(headers={name: "Bearer " + secret})}}


weird_path = '/tmp/pro j\nsecond"q\\z'
doc = None
raw = None

if case == "headerless":
    doc = authed()
    doc["projects"] = {"/tmp/proj-a": {"mcpServers": {"github": http_github()}}}
elif case == "empty_headers":
    doc = authed()
    doc["projects"] = {"/tmp/proj-b": {"mcpServers": {"github": http_github(headers={})}}}
elif case == "whitespace_auth":
    doc = authed()
    doc["projects"] = {
        "/tmp/proj-c": {"mcpServers": {"github": http_github(headers={"Authorization": "   \t "})}}
    }
elif case == "lowercase_global":
    doc = authed(name="authorization")
    doc["projects"] = {"/tmp/proj-d": {"mcpServers": {"github": http_github()}}}
elif case == "trailing_slash":
    doc = {"mcpServers": {"github": http_github(url=endpoint + "/", headers={"Authorization": "Bearer " + secret})}}
    doc["projects"] = {"/tmp/proj-e": {"mcpServers": {"github": http_github()}}}
elif case == "weird_path":
    doc = authed()
    doc["projects"] = {weird_path: {"mcpServers": {"github": http_github()}}}
elif case == "no_github_global":
    doc = {"mcpServers": {"other": http_github()}}
    doc["projects"] = {"/tmp/proj-f": {"mcpServers": {"github": http_github()}}}
elif case == "unauthenticated_global":
    doc = {"mcpServers": {"github": http_github()}}
    doc["projects"] = {"/tmp/proj-g": {"mcpServers": {"github": http_github()}}}
elif case == "non_bearer_global":
    doc = {"mcpServers": {"github": http_github(headers={"Authorization": "Basic " + secret})}}
    doc["projects"] = {"/tmp/proj-basic": {"mcpServers": {"github": http_github()}}}
elif case == "empty_bearer_global":
    doc = {"mcpServers": {"github": http_github(headers={"Authorization": "Bearer   "})}}
    doc["projects"] = {"/tmp/proj-empty": {"mcpServers": {"github": http_github()}}}
elif case == "authenticated_local":
    doc = authed()
    doc["projects"] = {
        "/tmp/proj-h": {"mcpServers": {"github": http_github(headers={"Authorization": "Bearer " + secret})}}
    }
elif case == "lowercase_local":
    doc = authed()
    doc["projects"] = {"/tmp/proj-lower": {"mcpServers": {"github": http_github(headers={"authorization": "Bearer " + secret})}}}
elif case == "different_url":
    doc = authed()
    doc["projects"] = {
        "/tmp/proj-i": {"mcpServers": {"github": http_github(url="https://example.invalid/mcp")}}
    }
elif case == "oauth":
    doc = authed()
    doc["projects"] = {
        "/tmp/proj-j": {"mcpServers": {"github": http_github(extra={"oauth": {"clientId": "x"}})}}
    }
elif case == "headers_helper":
    doc = authed()
    doc["projects"] = {
        "/tmp/proj-k": {"mcpServers": {"github": http_github(extra={"headersHelper": "/bin/echo"})}}
    }
elif case == "no_projects":
    doc = authed()
elif case == "malformed":
    raw = '{"mcpServers": {"github": {"type": "http", ' + secret + '\n'
else:
    raise SystemExit("unknown case: " + case)

with open(path, "w", encoding="utf-8") as handle:
    if raw is not None:
        handle.write(raw)
    else:
        json.dump(doc, handle)
        handle.write("\n")

if case == "weird_path":
    with open(os.path.join(root, "expected.txt"), "w", encoding="utf-8") as handle:
        handle.write(json.dumps(weird_path) + "\n")
PY

  run_case() {
    local case_name="$1"
    local dir="$test_root/$case_name"
    [ -f "$dir/.claude.json" ] || python3 "$maker" "$case_name" "$dir" "$secret" || return 1
    cp "$dir/.claude.json" "$dir/before.json" || return 1
    (
      HOME="$dir"
      DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh || exit 1
      warn_claude_github_mcp_overrides
    ) >"$test_root/$case_name.out" 2>"$test_root/$case_name.err" || return 1
    cmp -s "$dir/before.json" "$dir/.claude.json" || {
      echo "GitHub MCP warning changed state for case: $case_name" >&2
      return 1
    }
    cat "$test_root/$case_name.out" "$test_root/$case_name.err" >>"$out"
    cat "$test_root/$case_name.out" "$test_root/$case_name.err"
  }

  # Warns: an unauthenticated local override shadows the authenticated global.
  for case_dir in headerless empty_headers whitespace_auth lowercase_global trailing_slash; do
    if ! run_case "$case_dir" | grep -Fq 'claude mcp remove github --scope local'; then
      echo "expected a github MCP override warning for case: $case_dir" >&2
      return 1
    fi
  done
  run_case headerless | grep -Fq '"/tmp/proj-a"'

  # Silent: nothing to warn about, or the override is deliberate.
  for case_dir in no_github_global unauthenticated_global non_bearer_global empty_bearer_global \
      authenticated_local lowercase_local different_url oauth headers_helper no_projects; do
    case_output="$(run_case "$case_dir")" || return 1
    if [ -n "$case_output" ]; then
      echo "unexpected github MCP warning for case: $case_dir" >&2
      return 1
    fi
  done

  # A project path with a newline or quote stays on one escaped line.
  run_case weird_path >/dev/null
  if ! grep -Fq "$(cat "$test_root/weird_path/expected.txt")" "$test_root/weird_path.out"; then
    echo "project path was not JSON-escaped in the warning" >&2
    return 1
  fi
  [ "$(grep -Fc 'claude mcp remove github --scope local' "$test_root/weird_path.out")" = "1" ]

  # Malformed JSON: one generic diagnostic, never a dump of the file.
  run_case malformed >/dev/null
  if ! cat "$test_root/malformed.out" "$test_root/malformed.err" | grep -Fq 'could not inspect'; then
    echo "malformed .claude.json did not produce a generic diagnostic" >&2
    return 1
  fi

  # Missing state file and missing jq are both silent successes.
  mkdir -p "$test_root/absent" "$test_root/nojq-bin"
  if [ -n "$(
      HOME="$test_root/absent"
      DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh
      warn_claude_github_mcp_overrides 2>&1
    )" ]; then
    echo "missing ~/.claude.json must stay silent" >&2
    return 1
  fi
  (
    HOME="$test_root/headerless"
    DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh
    # Assignment clears Bash 3.2's command cache; a function-prefix override does not.
    PATH="$test_root/nojq-bin"
    warn_claude_github_mcp_overrides
  ) >"$test_root/nojq.out" 2>"$test_root/nojq.err"
  if [ -s "$test_root/nojq.out" ] || [ -s "$test_root/nojq.err" ]; then
    echo "missing jq must stay silent" >&2
    return 1
  fi

  # Read-only and idempotent: bytes never change, output repeats exactly.
  digest_before="$(shasum -a 256 "$test_root/headerless/.claude.json" | awk '{print $1}')"
  run_case headerless >"$test_root/first.txt"
  run_case headerless >"$test_root/second.txt"
  digest_after="$(shasum -a 256 "$test_root/headerless/.claude.json" | awk '{print $1}')"
  [ "$digest_before" = "$digest_after" ] || {
    echo "github MCP inspection modified ~/.claude.json" >&2
    return 1
  }
  cmp -s "$test_root/first.txt" "$test_root/second.txt" || {
    echo "github MCP warning is not idempotent" >&2
    return 1
  }

  # The bearer token never reaches stdout or stderr.
  if grep -Fq "$secret" "$out" "$test_root/first.txt" "$test_root/second.txt"; then
    echo "github MCP warning leaked an authorization value" >&2
    return 1
  fi

  unset -f run_case
  echo "claude github MCP override warning ok: read-only, escaped, secret-free"
}

run_copilot_terminal_smoke() {
  (
    local test_root fake_bin direct_capture gg_capture
    test_root="$(mktemp -d)"
    trap 'rm -rf "$test_root"' EXIT
    fake_bin="$test_root/bin"
    direct_capture="$test_root/direct"
    gg_capture="$test_root/gg"
    mkdir -p "$fake_bin"

    cat >"$fake_bin/copilot" <<'SH'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' \
  "${TERM_PROGRAM:-}" "${COLORTERM:-}" "${FORCE_COLOR:-}" "$*" \
  >>"$COPILOT_CAPTURE"
SH
    chmod +x "$fake_bin/copilot"

    PATH="$fake_bin:$PATH" COPILOT_CAPTURE="$direct_capture" TERM_PROGRAM=rmux \
      zsh -c 'source config/zsh/copilot.zsh; copilot status; [[ "$TERM_PROGRAM" = rmux ]]'
    grep -Fq 'WezTerm|truecolor|3|status' "$direct_capture"

    PATH="$fake_bin:$PATH" COPILOT_CAPTURE="$gg_capture" TERM_PROGRAM=rmux \
      zsh -c 'unset RMUX TMUX WEZTERM_PANE; source config/zsh/gg.zsh; gg terminal-smoke >/dev/null; [[ "$TERM_PROGRAM" = rmux ]]'
    grep -Fq 'WezTerm|truecolor|3|--allow-all-tools --allow-all-paths --model gpt-6-astra --context long_context --effort max' "$gg_capture"
  )

  echo "Copilot launchers advertise WezTerm truecolor without replacing RMUX identity"
}

run_global_instructions_smoke() {
  local file lines pattern
  local project_files=(
    .claude/CLAUDE.md
    .github/copilot-instructions.md
  )
  local global_files=(
    config/claude/CLAUDE.md
    config/copilot/AGENTS.md
    config/copilot/copilot-instructions.md
  )

  for file in "${project_files[@]}" "${global_files[@]}"; do
    [ -f "$file" ] || {
      echo "missing instruction source: $file" >&2
      return 1
    }
  done

  for file in "${project_files[@]}"; do
    grep -Fq 'wiki/README.md' "$file"
    grep -Fq 'config/manifest.tsv' "$file"
    grep -Fq 'scripts/check.sh all' "$file"
    grep -Fq 'full source of truth' "$file"
    grep -Fq -- '-zh-CN' "$file"
    grep -Fq 'root README' "$file"
    grep -Fq 'globally synced' "$file"
    grep -Fq 'repo-only' "$file"
    grep -Fq 'claude-sonnet-5' "$file"
    grep -Fq 'claude-haiku-4-5-20251001' "$file"
    grep -Fq 'gptModel' "$file"
    grep -Fq 'gpt-6-astra' "$file"
    grep -Fq 'claude-opus-5' "$file"
    grep -Fq 'display override' "$file"
    lines="$(wc -l <"$file" | tr -d ' ')"
    [ "$lines" -le 60 ] || {
      echo "$file must stay short" >&2
      return 1
    }
  done

  grep -Fq 'Do not use ASCII-art flowcharts' config/claude/CLAUDE.md
  for file in config/claude/CLAUDE.md config/copilot/copilot-instructions.md; do
    grep -Fq 'Keep conversational prose concise by default.' "$file"
    grep -Fq 'Lead with the answer.' "$file"
    grep -Fq 'Match detail to the' "$file"
    grep -Fq 'Keep code, commands, diffs' "$file"
    grep -Fq 'Preserve necessary caveats' "$file"
    grep -Fq 'Use headings or other structure' "$file"
  done
  for file in "${global_files[@]}"; do
    grep -Fq '~/Public/dot-configs' "$file"
    for pattern in \
      'wiki/README.md' \
      'Development-and-Releases' \
      'scripts/check.sh' \
      '-zh-CN' \
      'root README' \
      'D0n9X1n/dot-config'; do
      if grep -Fq -e "$pattern" "$file"; then
        echo "$file must not carry repo-only directive: $pattern" >&2
        return 1
      fi
    done
    if grep -Eq '^@' "$file"; then
      echo "$file must not use an @import" >&2
      return 1
    fi
    lines="$(wc -l <"$file" | tr -d ' ')"
    [ "$lines" -le 40 ] || {
      echo "$file must stay a short global" >&2
      return 1
    }
  done

  grep -Fq 'Run tools and commands without asking for approval.' config/copilot/copilot-instructions.md
  grep -Fq 'Work on the task directly.' config/copilot/copilot-instructions.md
  # Copilot does not reliably inline the global AGENTS.md.
  grep -Fq '~/.copilot/AGENTS.md' config/copilot/copilot-instructions.md
  if grep -Fq 'COPILOT_CUSTOM_INSTRUCTIONS_DIRS' config/copilot/copilot-instructions.md; then
    echo "config/copilot/copilot-instructions.md must not carry loader internals" >&2
    return 1
  fi

  zsh -f -c '
    unset COPILOT_CUSTOM_INSTRUCTIONS_DIRS
    source config/zsh/custom.zsh
    [[ "$COPILOT_CUSTOM_INSTRUCTIONS_DIRS" = "$HOME/.copilot" ]]
    source config/zsh/custom.zsh
    [[ "$COPILOT_CUSTOM_INSTRUCTIONS_DIRS" = "$HOME/.copilot" ]]
  '
  COPILOT_CUSTOM_INSTRUCTIONS_DIRS="$HOME/one,$HOME/two" zsh -f -c '
    source config/zsh/custom.zsh
    [[ "$COPILOT_CUSTOM_INSTRUCTIONS_DIRS" = "$HOME/one,$HOME/two,$HOME/.copilot" ]]
  '
  COPILOT_CUSTOM_INSTRUCTIONS_DIRS="$HOME/one,$HOME/.copilot,$HOME/two" zsh -f -c '
    source config/zsh/custom.zsh
    [[ "$COPILOT_CUSTOM_INSTRUCTIONS_DIRS" = "$HOME/one,$HOME/.copilot,$HOME/two" ]]
  '

  (
    local test_root test_home test_repo
    DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh
    test_root="$(mktemp -d)"
    trap 'rm -rf "$test_root"' EXIT
    test_home="$test_root/home"
    test_repo="$test_root/repo"
    mkdir -p "$test_home/.claude" "$test_home/.copilot" \
      "$test_repo/config/claude" "$test_repo/config/copilot"
    printf 'original global instructions\n' >"$test_home/.claude/CLAUDE.md"
    printf 'tracked Claude instructions\n' >"$test_repo/config/claude/CLAUDE.md"
    printf 'tracked Copilot instructions\n' >"$test_repo/config/copilot/AGENTS.md"
    printf 'tracked native Copilot instructions\n' \
      >"$test_repo/config/copilot/copilot-instructions.md"

    HOME="$test_home"
    timestamp="20000101000000"
    link_file "$test_repo/config/claude/CLAUDE.md" "$test_home/.claude/CLAUDE.md"
    link_file "$test_repo/config/copilot/AGENTS.md" "$test_home/.copilot/AGENTS.md"
    link_file "$test_repo/config/copilot/copilot-instructions.md" \
      "$test_home/.copilot/copilot-instructions.md"

    [ -L "$test_home/.claude/CLAUDE.md" ]
    [ "$(readlink "$test_home/.claude/CLAUDE.md")" = "$test_repo/config/claude/CLAUDE.md" ]
    [ -f "$test_home/.claude/CLAUDE.md.bak.20000101000000" ]
    grep -Fq 'original global instructions' "$test_home/.claude/CLAUDE.md.bak.20000101000000"
    [ -L "$test_home/.copilot/AGENTS.md" ]
    [ "$(readlink "$test_home/.copilot/AGENTS.md")" = "$test_repo/config/copilot/AGENTS.md" ]
    [ -L "$test_home/.copilot/copilot-instructions.md" ]
    [ "$(readlink "$test_home/.copilot/copilot-instructions.md")" \
      = "$test_repo/config/copilot/copilot-instructions.md" ]
  )

  echo "global/project instruction scope, native model policy, and links ok"
}

run_wiki_smoke() {
  local file base stem partner target duplicate transformed count lines
  local required=(
    wiki/README.md
    wiki/Home-zh-CN.md
    wiki/Getting-Started.md
    wiki/Getting-Started-zh-CN.md
    wiki/Repository-Operations.md
    wiki/Repository-Operations-zh-CN.md
    wiki/Claude-Code.md
    wiki/Claude-Code-zh-CN.md
    wiki/Copilot-CLI.md
    wiki/Copilot-CLI-zh-CN.md
    wiki/RMUX.md
    wiki/RMUX-zh-CN.md
    wiki/RMUX-Keymap.md
    wiki/RMUX-Keymap-zh-CN.md
    wiki/SonicTerm-and-Shell.md
    wiki/SonicTerm-and-Shell-zh-CN.md
    wiki/Services-and-Automation.md
    wiki/Services-and-Automation-zh-CN.md
    wiki/Development-and-Releases.md
    wiki/Development-and-Releases-zh-CN.md
    wiki/Apollo-Theme.md
    wiki/Apollo-Theme-zh-CN.md
    wiki/Archive-Tmux.md
    wiki/Archive-Tmux-zh-CN.md
    wiki/Archive-WezTerm.md
    wiki/Archive-WezTerm-zh-CN.md
    wiki/_Sidebar.md
    scripts/wiki-render.sh
    scripts/wiki-publish.sh
    scripts/release-notes.sh
    .github/workflows/publish-wiki.yml
    .github/workflows/release.yml
  )

  for file in "${required[@]}"; do
    [ -f "$file" ] || {
      echo "missing Wiki or pipeline source: $file" >&2
      return 1
    }
  done

  [ ! -e QUICKREF.md ]
  [ ! -e claude/README.md ]
  [ ! -e themes ]
  [ ! -e wiki/Operations.md ]
  [ ! -e wiki/Operations-zh-CN.md ]

  lines="$(wc -l <ReadMe.md | tr -d ' ')"
  [ "$lines" -le 90 ] || {
    echo "ReadMe.md must stay at 90 lines or fewer" >&2
    return 1
  }
  grep -Fq 'config/manifest.tsv' ReadMe.md
  grep -Fq 'GitHub Wiki' ReadMe.md
  grep -Fq 'GitHub Release' ReadMe.md

  if grep -RFn 'QUICKREF.md' .claude/CLAUDE.md .github/copilot-instructions.md \
      config/claude config/copilot wiki ReadMe.md archive; then
    echo "retired QUICKREF.md is still referenced" >&2
    return 1
  fi

  if find wiki -mindepth 2 -type f -print -quit | grep -q .; then
    echo "wiki/ must remain flat" >&2
    return 1
  fi

  while IFS= read -r file; do
    base="$(basename "$file")"
    case "$base" in
      *[!A-Za-z0-9_.-]*)
        echo "unsafe Wiki filename: $file" >&2
        return 1
        ;;
    esac
  done < <(find wiki -maxdepth 1 -type f -name '*.md' -print | sort)

  duplicate="$(find wiki -maxdepth 1 -type f -name '*.md' -print |
    while IFS= read -r file; do basename "$file" | tr '[:upper:]' '[:lower:]'; done |
    sort | uniq -d | sed -n '1p')"
  if [ -n "$duplicate" ]; then
    echo "case-insensitive Wiki filename collision: $duplicate" >&2
    return 1
  fi

  while IFS= read -r file; do
    base="$(basename "$file")"
    case "$base" in
      README.md) partner="Home-zh-CN.md" ;;
      _Sidebar.md|*-zh-CN.md) continue ;;
      *) stem="${base%.md}"; partner="${stem}-zh-CN.md" ;;
    esac
    [ -f "wiki/$partner" ] || {
      echo "missing Simplified Chinese Wiki pair for $base" >&2
      return 1
    }
    grep -Fq "]($partner)" "$file" || {
      echo "$base does not link to $partner" >&2
      return 1
    }
  done < <(find wiki -maxdepth 1 -type f -name '*.md' -print | sort)

  while IFS= read -r file; do
    base="$(basename "$file")"
    if [ "$base" = "Home-zh-CN.md" ]; then
      partner="README.md"
    else
      stem="${base%-zh-CN.md}"
      partner="${stem}.md"
    fi
    [ -f "wiki/$partner" ] || {
      echo "missing English Wiki pair for $base" >&2
      return 1
    }
    grep -Fq "]($partner)" "$file" || {
      echo "$base does not link to $partner" >&2
      return 1
    }
  done < <(find wiki -maxdepth 1 -type f -name '*-zh-CN.md' -print | sort)

  while IFS= read -r file; do
    base="$(basename "$file")"
    [ "$base" = "_Sidebar.md" ] && continue
    count="$(grep -Fc "]($base)" wiki/_Sidebar.md || true)"
    [ "$count" = "1" ] || {
      echo "$base must appear exactly once in wiki/_Sidebar.md" >&2
      return 1
    }
  done < <(find wiki -maxdepth 1 -type f -name '*.md' -print | sort)

  if grep -REn '\]\([A-Za-z0-9_-]+\.md#[^)]+\)' wiki/*.md; then
    echo "cross-page Wiki links must not include .md anchors" >&2
    return 1
  fi

  while IFS= read -r target; do
    [ -f "wiki/$target" ] || {
      echo "unresolved Wiki source link: $target" >&2
      return 1
    }
  done < <(grep -EhRo '\]\([A-Za-z0-9_-]+\.md\)' wiki/*.md |
    sed -E 's/^.*\]\(([^)]+)\)$/\1/' | sort -u)

  transformed="$(mktemp -d)"
  trap 'rm -rf "${transformed:-}"' RETURN
  scripts/wiki-render.sh wiki "$transformed"
  [ -f "$transformed/Home.md" ]
  [ ! -f "$transformed/README.md" ]

  if grep -REn '\]\([A-Za-z0-9_-]+\.md\)' "$transformed"/*.md; then
    echo "published Wiki graph still contains source .md links" >&2
    return 1
  fi
  while IFS= read -r target; do
    [ -f "$transformed/$target.md" ] || {
      echo "unresolved published Wiki link: $target" >&2
      return 1
    }
  done < <(grep -EhRo '\]\([A-Za-z0-9_-]+\)' "$transformed"/*.md |
    sed -E 's/^.*\]\(([^)]+)\)$/\1/' | sort -u)
  rm -rf "$transformed"
  transformed=""
  trap - RETURN

  grep -Fq 'bash scripts/wiki-publish.sh' .github/workflows/publish-wiki.yml
  if grep -Eq 'git clone|sed -i|find wiki-repo|git push' .github/workflows/publish-wiki.yml; then
    echo "Wiki workflow contains publish logic that belongs in scripts/" >&2
    return 1
  fi
  grep -Fq 'bash scripts/release-notes.sh' .github/workflows/release.yml
  if grep -Eq 'git describe|git log --reverse|current_commit=' .github/workflows/release.yml; then
    echo "release workflow contains note logic that belongs in scripts/" >&2
    return 1
  fi
  echo "Wiki source, bilingual pairs, sidebar, and rendered graph ok"
}

run_manifest_smoke() {
  (
    local test_root test_repo test_home foreign before after config_files manifest_config_files duplicate_source
    DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh
    validate_manifest

    if grep -Ev '^(#|$)' config/manifest.tsv | cut -f2 | grep -Eq '^archive/'; then
      echo "manifest contains an archive source" >&2
      return 1
    fi
    duplicate_source="$(grep -Ev '^(#|$)' config/manifest.tsv | cut -f2 | sort | uniq -d | sed -n '1p')"
    [ -z "$duplicate_source" ] || {
      echo "duplicate manifest source: $duplicate_source" >&2
      return 1
    }
    config_files="$(find config -type f ! -path 'config/manifest.tsv' -print | sort)"
    manifest_config_files="$(grep -Ev '^(#|$)' config/manifest.tsv | cut -f2 | grep '^config/' | sort)"
    [ "$config_files" = "$manifest_config_files" ] || {
      echo "config/ files and manifest sources differ" >&2
      diff -u <(printf '%s\n' "$config_files") <(printf '%s\n' "$manifest_config_files") >&2 || true
      return 1
    }
    [ "$(manifest_source_for_destination link .config/git/ignore)" = \
      "$repo_root/config/git/ignore" ]
    [ "$(manifest_source_for_destination merge .config/github-copilot/mcp.json)" = \
      "$repo_root/config/mcp/mcp-shared.json" ]
    [ "$(manifest_source_for_destination render Library/LaunchAgents/com.d0n9x1n.npm-cache-clean.plist)" = \
      "$repo_root/config/launchd/com.d0n9x1n.npm-cache-clean.plist" ]

    test_root="$(mktemp -d)"
    trap 'rm -rf "$test_root"' EXIT
    test_repo="$test_root/repo"
    test_home="$test_root/home"
    mkdir -p "$test_repo/config/rmux" "$test_repo/config/claude" \
      "$test_repo/config/copilot" "$test_home/.claude" "$test_home/.copilot"
    printf 'new rmux\n' >"$test_repo/config/rmux/rmux.conf"
    printf 'new claude\n' >"$test_repo/config/claude/settings.json"
    printf 'new copilot\n' >"$test_repo/config/copilot/settings.json"
    cat >"$test_repo/config/manifest.tsv" <<'TSV'
# type	source	destination
link	config/rmux/rmux.conf	.rmux.conf
link	config/claude/settings.json	.claude/settings.json
link	config/copilot/settings.json	.copilot/settings.json
TSV

    repo_root="$test_repo"
    config_root="$test_repo/config"
    manifest="$test_repo/config/manifest.tsv"
    HOME="$test_home"
    timestamp="20000101000000"
    validate_manifest

    ln -s "$test_repo/.rmux.conf" "$test_home/.rmux.conf"
    printf 'user settings\n' >"$test_home/.claude/settings.json"
    foreign="$test_root/foreign-copilot.json"
    printf 'foreign\n' >"$foreign"
    ln -s "$foreign" "$test_home/.copilot/settings.json"

    link_manifest_files
    [ "$(readlink "$test_home/.rmux.conf")" = "$test_repo/config/rmux/rmux.conf" ]
    [ "$(readlink "$test_home/.claude/settings.json")" = "$test_repo/config/claude/settings.json" ]
    grep -Fq 'user settings' "$test_home/.claude/settings.json.bak.20000101000000"
    [ "$(readlink "$test_home/.copilot/settings.json.bak.20000101000000")" = "$foreign" ]
    [ "$(readlink "$test_home/.copilot/settings.json")" = "$test_repo/config/copilot/settings.json" ]

    before="$(find "$test_home" -name '*.bak.*' -type f -o -name '*.bak.*' -type l | sort)"
    link_manifest_files
    after="$(find "$test_home" -name '*.bak.*' -type f -o -name '*.bak.*' -type l | sort)"
    [ "$before" = "$after" ]

    printf 'config/claude/settings.json\n' >"$test_repo/config/extra.json"
    cat >"$test_repo/config/manifest.tsv" <<'TSV'
link	config/rmux/rmux.conf	.same
link	config/claude/settings.json	.other
link	config/copilot/settings.json	.same
TSV
    if validate_manifest >/dev/null 2>&1; then
      echo "manifest accepted a non-adjacent duplicate destination" >&2
      return 1
    fi

    cat >"$test_repo/config/manifest.tsv" <<'TSV'
link	archive/old.conf	.old
TSV
    mkdir -p "$test_repo/archive"
    printf 'old\n' >"$test_repo/archive/old.conf"
    if validate_manifest >/dev/null 2>&1; then
      echo "manifest accepted an archive source" >&2
      return 1
    fi
  )

  echo "config manifest and safe link migration ok"
}

run_launchd_template_smoke() {
  (
    local test_root original_repo template rendered file fake_bin capture
    DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh
    test_root="$(mktemp -d)"
    trap 'rm -rf "$test_root"' EXIT
    original_repo="$repo_root"
    HOME="$test_root/home&lab"
    repo_root="$test_root/repo&lab"
    mkdir -p "$HOME" "$repo_root"
    template="$test_root/template.plist"
    rendered="$test_root/rendered.plist"
    cat >"$template" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Home</key><string>__HOME__</string>
<key>Repo</key><string>__REPO_ROOT__/scripts/launchd/job.sh</string>
</dict></plist>
PLIST
    render_launchd_template "$template" "$rendered" >/dev/null
    if grep -Eq '__HOME__|__REPO_ROOT__' "$rendered"; then
      echo "rendered launchd fixture contains an unresolved placeholder" >&2
      return 1
    fi
    grep -Fq 'home&amp;lab' "$rendered"
    grep -Fq 'repo&amp;lab/scripts/launchd/job.sh' "$rendered"
    if command -v plutil >/dev/null 2>&1; then
      plutil -lint "$rendered" >/dev/null
    fi

    HOME="$test_root/home"
    repo_root="$original_repo"
    mkdir -p "$HOME"
    for file in config/launchd/*.plist; do
      rendered="$test_root/$(basename "$file")"
      render_launchd_template "$file" "$rendered" >/dev/null
      if grep -Eq '__HOME__|__REPO_ROOT__' "$rendered"; then
        echo "$file rendered with an unresolved placeholder" >&2
        return 1
      fi
      if command -v plutil >/dev/null 2>&1; then
        plutil -lint "$rendered" >/dev/null
      fi
    done
    grep -Fq "$original_repo/scripts/launchd/copilot-relay-healthcheck.sh" \
      "$test_root/com.d0n9x1n.copilot-relay-healthcheck.plist"
    grep -Fq "$original_repo/scripts/launchd/clean-npm-caches.sh" \
      "$test_root/com.d0n9x1n.npm-cache-clean.plist"

    fake_bin="$test_root/bin"
    capture="$test_root/launchctl"
    mkdir -p "$fake_bin"
    cat >"$fake_bin/launchctl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$LAUNCHCTL_CAPTURE"
[ "$1" = "print" ]
SH
    chmod +x "$fake_bin/launchctl"
    HOME="$test_root/missing-relay-home"
    mkdir -p "$HOME"
    PATH="$fake_bin:/usr/bin:/bin" LAUNCHCTL_CAPTURE="$capture" \
      install_copilot_relay_healthcheck 501 >/dev/null
    grep -Fq 'bootout gui/501/com.d0n9x1n.copilot-relay-healthcheck' "$capture"
    grep -Fq "$original_repo/scripts/launchd/copilot-relay-healthcheck.sh" \
      "$HOME/Library/LaunchAgents/com.d0n9x1n.copilot-relay-healthcheck.plist"
  )

  echo "launchd templates render valid paths"
}

run_pipeline_scripts_smoke() {
  (
    local test_root remote seed checkout published before after notes repo
    test_root="$(mktemp -d)"
    trap 'rm -rf "$test_root"' EXIT
    remote="$test_root/wiki.git"
    seed="$test_root/seed"
    checkout="$test_root/wiki-checkout"
    published="$test_root/published"

    git init --bare --initial-branch=main "$remote" >/dev/null
    git clone "$remote" "$seed" >/dev/null 2>&1
    git -C "$seed" config user.name test
    git -C "$seed" config user.email test@example.com
    printf '# old\n' >"$seed/Old.md"
    git -C "$seed" add Old.md
    git -C "$seed" commit -m 'seed wiki' >/dev/null
    git -C "$seed" push origin HEAD >/dev/null 2>&1

    WIKI_REMOTE_URL="$remote" GITHUB_SHA=1234567890abcdef \
      scripts/wiki-publish.sh wiki "$checkout" >/dev/null
    git clone "$remote" "$published" >/dev/null 2>&1
    [ -f "$published/Home.md" ]
    [ ! -f "$published/README.md" ]
    [ ! -f "$published/Old.md" ]
    if grep -REn '\]\([A-Za-z0-9_-]+\.md\)' "$published"/*.md; then
      echo "published Wiki fixture still contains source .md links" >&2
      return 1
    fi
    [ "$(git -C "$published" log -1 --format=%s)" = "Publish wiki from 1234567" ]

    before="$(git -C "$checkout" rev-list --count HEAD)"
    WIKI_REMOTE_URL="$remote" GITHUB_SHA=1234567890abcdef \
      scripts/wiki-publish.sh wiki "$checkout" >/dev/null
    after="$(git -C "$checkout" rev-list --count HEAD)"
    [ "$before" = "$after" ]

    git -C "$seed" pull --ff-only >/dev/null
    printf '\nREMOTE_ONLY_WIKI_SENTINEL\n' >>"$seed/Home.md"
    git -C "$seed" add Home.md
    git -C "$seed" commit -m 'browser edit' >/dev/null
    git -C "$seed" push origin HEAD >/dev/null 2>&1
    printf 'keep local\n' >"$checkout/stray.txt"
    WIKI_REMOTE_URL="$remote" GITHUB_SHA=abcdef1234567890 \
      scripts/wiki-publish.sh wiki "$checkout" >/dev/null
    [ -f "$checkout/stray.txt" ]
    git -C "$published" pull --ff-only >/dev/null
    [ ! -e "$published/stray.txt" ]
    if grep -Fq 'REMOTE_ONLY_WIKI_SENTINEL' "$published/Home.md"; then
      echo "source publish did not replace a remote Wiki edit" >&2
      return 1
    fi

    repo="$test_root/release"
    notes="$test_root/release-notes.md"
    git init --initial-branch=main "$repo" >/dev/null
    git -C "$repo" config user.name test
    git -C "$repo" config user.email test@example.com
    printf 'one\n' >"$repo/file"
    git -C "$repo" add file
    git -C "$repo" commit -m 'first change' >/dev/null
    git -C "$repo" tag -a v1.0.0 -m v1.0.0
    printf 'two\n' >>"$repo/file"
    git -C "$repo" commit -am 'second change' >/dev/null
    printf 'three\n' >>"$repo/file"
    git -C "$repo" commit -am 'third change' >/dev/null
    git -C "$repo" tag -a v1.1.0 -m v1.1.0

    RELEASE_REPO_ROOT="$repo" scripts/release-notes.sh v1.1.0 "$notes"
    cat >"$test_root/expected" <<'NOTES'
## Changes since v1.0.0

- second change
- third change
NOTES
    cmp -s "$test_root/expected" "$notes"

    RELEASE_REPO_ROOT="$repo" scripts/release-notes.sh v1.0.0 "$notes"
    cat >"$test_root/expected" <<'NOTES'
## Changes

- first change
NOTES
    cmp -s "$test_root/expected" "$notes"
  )

  echo "Wiki publish and release-note scripts ok"
}

run_structure_smoke() {
  local retired_tracked=""
  local staged_deleted=""
  local file=""

  [ -f config/manifest.tsv ]
  [ -f config/rmux/rmux.conf ]
  [ -f config/sonicterm/sonicterm.toml ]
  [ -f config/claude/settings.json ]
  [ -f config/copilot/settings.json ]
  [ -f config/copilot-relay/config.yaml ]
  [ -f config/mcp/mcp-shared.json ]
  [ -f scripts/launchd/clean-npm-caches.sh ]
  [ -f archive/tmux/.tmux.conf ]
  [ -f archive/wezterm/wezterm.lua ]

  [ ! -f .rmux.conf ]
  [ ! -f .sonicterm/sonicterm.toml ]
  [ ! -f oh-my-zsh-custom/zz-rmux.zsh ]
  [ ! -f claude/settings.json ]
  [ ! -f copilot/settings.json ]
  [ ! -f launchd/com.d0n9x1n.npm-cache-clean.plist ]
  [ ! -f mcp-shared.json ]

  staged_deleted="$(git diff --cached --name-only --diff-filter=D -- \
    '.rmux.conf' '.sonicterm/*' '.copilot-relay/*' 'claude/*' 'copilot/*' \
    'oh-my-zsh-custom/*' 'launchd/*' 'mcp-shared.json')"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if ! printf '%s\n' "$staged_deleted" | grep -Fxq "$file"; then
      retired_tracked="${retired_tracked}${retired_tracked:+$'\n'}${file}"
    fi
  done < <(git ls-files -- \
    '.rmux.conf' '.sonicterm/*' '.copilot-relay/*' 'claude/*' 'copilot/*' \
    'oh-my-zsh-custom/*' 'launchd/*' 'mcp-shared.json')
  [ -z "$retired_tracked" ] || {
    echo "active files remain tracked at retired paths:" >&2
    printf '%s\n' "$retired_tracked" >&2
    return 1
  }

  if grep -Ev '^(#|$)' config/manifest.tsv | cut -f2 | grep -Eq '^archive/'; then
    echo "manifest contains an archive source" >&2
    return 1
  fi
  grep -Fq '.sonicterm/' .gitignore
  grep -Fq '.copilot-relay/' .gitignore
  grep -Fq 'wiki-repo/' .gitignore
  grep -Fq '*.save.lock' .gitignore
  grep -Fq $'link\tconfig/git/ignore\t.config/git/ignore' config/manifest.tsv
  grep -Eq '^[[:space:]]+shellcheck$' install.sh
  grep -Fq -- '--allow-all-tools --allow-all-paths' wiki/Copilot-CLI.md
  grep -Fq -- '--allow-all-tools --allow-all-paths' wiki/Copilot-CLI-zh-CN.md
  if grep -RFn '__SRC''_DIR__' install.sh config scripts wiki ReadMe.md; then
    echo "retired launchd placeholder is still present" >&2
    return 1
  fi
  echo "active config tree and archive boundary ok"
}

run_rmux_helpers_smoke() {
  (
    local test_root fake_bin capture exit_status
    test_root="$(mktemp -d)"
    trap 'rm -rf "$test_root"' EXIT
    fake_bin="$test_root/bin"
    capture="$test_root/capture"
    mkdir -p "$fake_bin"

    cat >"$fake_bin/rmux" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$RMUX_CAPTURE"
if [ "$1" = "has-session" ]; then
  [ "${RMUX_SESSION_EXISTS:-0}" = "1" ]
fi
SH
    chmod +x "$fake_bin/rmux"

    PATH="$fake_bin:/usr/bin:/bin" RMUX_CAPTURE="$capture" zsh -f -c '
      source config/zsh/zz-rmux.zsh
      rr new >/dev/null
    '
    [ "$(sed -n '1p' "$capture")" = "has-session -t new" ]
    [ "$(sed -n '2p' "$capture")" = "new-session -s new" ]

    RMUX_SESSION_EXISTS=1 PATH="$fake_bin:/usr/bin:/bin" RMUX_CAPTURE="$capture" zsh -f -c '
      source config/zsh/zz-rmux.zsh
      rr main >/dev/null
      rd main
      rl
      RMUX=socket exit
      RMUX=socket logout
      bindkey -M emacs "^D"
      bindkey -M viins "^D"
    '
    [ "$(sed -n '3p' "$capture")" = "has-session -t main" ]
    [ "$(sed -n '4p' "$capture")" = "attach-session -t main" ]
    [ "$(sed -n '5p' "$capture")" = "kill-session -t main" ]
    [ "$(sed -n '6p' "$capture")" = "list-sessions" ]
    [ "$(sed -n '7p' "$capture")" = "detach-client" ]
    [ "$(sed -n '8p' "$capture")" = "detach-client" ]
    [ "$(wc -l <"$capture" | tr -d ' ')" = "8" ]

    exit_status=0
    PATH="$fake_bin:/usr/bin:/bin" RMUX_CAPTURE="$capture" zsh -f -c '
      source config/zsh/zz-rmux.zsh
      exit 7
    ' || exit_status=$?
    [ "$exit_status" = "7" ]

    PATH="$fake_bin:/usr/bin:/bin" RMUX_CAPTURE="$capture" zsh -f -c '
      source config/zsh/zz-rmux.zsh
      rr >/dev/null 2>&1; [[ $? = 2 ]]
      rr one two >/dev/null 2>&1; [[ $? = 2 ]]
      rd >/dev/null 2>&1; [[ $? = 2 ]]
      rl extra >/dev/null 2>&1; [[ $? = 2 ]]
    '

    PATH="/usr/bin:/bin" zsh -f -c '
      source config/zsh/zz-rmux.zsh
      rr main >/dev/null 2>&1; [[ $? = 127 ]]
      rd main >/dev/null 2>&1; [[ $? = 127 ]]
      rl >/dev/null 2>&1; [[ $? = 127 ]]
    '
  )

  grep -Fq 'command rmux has-session -t "$1"' config/zsh/zz-rmux.zsh
  grep -Fq 'command rmux attach-session -t "$1"' config/zsh/zz-rmux.zsh
  grep -Fq 'command rmux new-session -s "$1"' config/zsh/zz-rmux.zsh
  grep -Fq 'command rmux kill-session -t "$1"' config/zsh/zz-rmux.zsh
  grep -Fq 'command rmux list-sessions' config/zsh/zz-rmux.zsh
  [ "$(grep -Fc 'command rmux detach-client' config/zsh/zz-rmux.zsh)" = "3" ]
  grep -Fq "bindkey -M emacs '^D' _rmux_detach_or_delete_char" config/zsh/zz-rmux.zsh
  grep -Fq "bindkey -M viins '^D' _rmux_detach_or_delete_char" config/zsh/zz-rmux.zsh
  echo "RMUX helpers ok: rr/rd/rl and exit/logout/Ctrl-D detach protection"
}

run_rmux_keymap_docs_smoke() {
  if ! command -v rmux >/dev/null 2>&1; then
    echo "rmux not found; skipping keymap snapshot runtime check"
    return 0
  fi

  (
    local socket test_root table page block effective count
    socket="dot-configs-keymap-$$"
    test_root="$(mktemp -d)"
    trap 'rmux -L "$socket" kill-server >/dev/null 2>&1 || true; rm -rf "$test_root"' EXIT INT TERM

    rmux -L "$socket" -f "$repo_root/config/rmux/rmux.conf" new-session -d -s keymap-audit -x 160 -y 48
    for table in prefix copy-mode-vi copy-mode root; do
      effective="$test_root/$table.effective"
      rmux -L "$socket" list-keys -T "$table" |
        sed "s|$HOME/.rmux.conf|~/.rmux.conf|g" >"$effective"
      case "$table" in
        prefix) count=90 ;;
        copy-mode-vi) count=89 ;;
        copy-mode) count=75 ;;
        root) count=24 ;;
      esac
      [ "$(wc -l <"$effective" | tr -d ' ')" = "$count" ]

      for page in wiki/RMUX-Keymap.md wiki/RMUX-Keymap-zh-CN.md; do
        block="$test_root/$(basename "$page").$table"
        sed -n "/<!-- BEGIN GENERATED $table -->/,/<!-- END GENERATED $table -->/p" "$page" |
          sed '1,2d;$d' | sed '$d' >"$block"
        cmp -s "$effective" "$block" || {
          echo "$page key table '$table' is out of date" >&2
          diff -u "$effective" "$block" >&2 || true
          return 1
        }
      done
    done
  )

  grep -Fq '`exit`, `logout`, and Ctrl+D at an empty prompt are protected' wiki/RMUX-Keymap.md
  grep -Fq '`exit`、`logout` 以及空提示符上的 Ctrl+D 都有保护' wiki/RMUX-Keymap-zh-CN.md
  echo "RMUX keymap docs ok: 278 effective bindings in English and Chinese"
}

run_retired_config_migration_smoke() {
  (
    local test_root exact other regular
    DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh
    test_root="$(mktemp -d)"
    trap 'rm -rf "$test_root"' EXIT
    exact="$test_root/exact"
    other="$test_root/other"
    regular="$test_root/regular"

    ln -s "$test_root/repo/.tmux.conf" "$exact"
    remove_repo_symlink "$exact" "$test_root/repo/.tmux.conf" "test config" >/dev/null
    [ ! -e "$exact" ] && [ ! -L "$exact" ]
    remove_repo_symlink "$exact" "$test_root/repo/.tmux.conf" "test config" >/dev/null

    ln -s "$test_root/user.conf" "$other"
    remove_repo_symlink "$other" "$test_root/repo/.tmux.conf" "test config" >/dev/null
    [ -L "$other" ] && [ "$(readlink "$other")" = "$test_root/user.conf" ]

    printf 'keep\n' >"$regular"
    remove_repo_symlink "$regular" "$test_root/repo/.tmux.conf" "test config" >/dev/null
    grep -Fq 'keep' "$regular"
  )

  grep -Eq '^[[:space:]]+rmux$' install.sh
  if grep -Eq '^[[:space:]]+tmux$' install.sh; then
    echo "installer still installs tmux" >&2
    return 1
  fi
  if grep -Eq '^[[:space:]]+wezterm$|brew install --cask wezterm' install.sh; then
    echo "installer still installs WezTerm" >&2
    return 1
  fi
  if grep -Eq 'command[[:space:]]+(tmux|wezterm)|wezterm cli' \
      config/zsh/cc.zsh config/zsh/gg.zsh; then
    echo "active launchers still call retired tmux or WezTerm commands" >&2
    return 1
  fi
  [ -f archive/tmux/.tmux.conf ]
  [ -f archive/wezterm/wezterm.lua ]
  [ ! -f .tmux.conf ]
  [ ! -f wezterm/wezterm.lua ]
  echo "retired tmux/WezTerm link migration ok"
}

run_rmux_smoke() {
  if ! command -v rmux >/dev/null 2>&1; then
    echo "rmux not found; skipping local config runtime check"
    return 0
  fi

  (
    local socket keys root_keys terminal_features parse_output parse_status expected_parse_output test_root test_home first_session first_pane second_session second_pane client_pid
    socket="dot-configs-check-$$"
    test_root="$(mktemp -d)"
    test_home="$test_root/home"
    mkdir -p "$test_home/.config/rmux-apollo-theme"
    cat >"$test_home/.config/rmux-apollo-theme/apollo-rmux.conf" <<'RMUX_THEME'
set-option -g status-style "bg=default,fg=default"
set-option -g status-left-style "bg=default,fg=default,bold"
set-window-option -g window-status-current-style "bg=default,fg=default,bold"
set-option -g pane-active-border-style "fg=default"
set-option -g message-style "bg=default,fg=default,bold"
set-window-option -g mode-style "bg=default,fg=default,bold"
RMUX_THEME
    export HOME="$test_home"
    trap 'rmux -L "$socket" kill-server >/dev/null 2>&1 || true; rm -rf "$test_root"' EXIT INT TERM

    rmux -L "$socket" -f /dev/null new-session -d -s validate -x 160 -y 48
    parse_status=0
    parse_output="$(rmux -L "$socket" source-file -n -v config/rmux/rmux.conf 2>&1)" || parse_status=$?
    if [ "$parse_status" -ne 0 ]; then
      expected_parse_output="$repo_root/config/rmux/rmux.conf:1: target form {mouse} is recognized but deferred until mouse event state reaches the command queue"
      if [ "$parse_status" -ne 1 ] || [ "$parse_output" != "$expected_parse_output" ]; then
        printf '%s\n' "$parse_output" >&2
        return 1
      fi
    fi
    rmux -L "$socket" source-file config/rmux/rmux.conf

    [ "$(rmux -L "$socket" show-options -gv prefix)" = "C-q" ]
    [ "$(rmux -L "$socket" show-options -gv mouse)" = "on" ]
    [ "$(rmux -L "$socket" show-options -gv history-limit)" = "100000" ]
    [ "$(rmux -L "$socket" show-options -gv base-index)" = "1" ]
    [ "$(rmux -L "$socket" show-options -gv status-position)" = "top" ]
    [ "$(rmux -L "$socket" show-options -gv status-style)" = "bg=default,fg=default" ]
    [ "$(rmux -L "$socket" show-options -gv pane-active-border-style)" = "fg=default" ]
    [ "$(rmux -L "$socket" show-window-options -gv mode-style)" = "bg=default,fg=default,bold" ]
    [ "$(rmux -L "$socket" show-options -gv set-titles)" = "on" ]
    [ "$(rmux -L "$socket" show-window-options -gv pane-base-index)" = "1" ]
    terminal_features="$(rmux -L "$socket" show-options -gv terminal-features)"
    printf '%s\n' "$terminal_features" | grep -Fxq 'xterm-256color:RGB:osc7'

    keys="$(rmux -L "$socket" list-keys -T prefix)"
    printf '%s\n' "$keys" | grep -Eq 'Tab[[:space:]]+last-window'
    printf '%s\n' "$keys" | grep -Fq 'split-window -h -c "#{pane_current_path}"'
    printf '%s\n' "$keys" | grep -Fq 'source-file'
    root_keys="$(rmux -L "$socket" list-keys -T root)"
    printf '%s\n' "$root_keys" | grep -Fq 'MouseDown1Pane            select-pane -t = \; send-keys -M'
    printf '%s\n' "$root_keys" | grep -Fq 'if-shell -F "#{||:#{pane_in_mode},#{mouse_any_flag}}" { send-keys -M } { copy-mode -M }'
    grep -Fq 'bind -n MouseDown1Pane { select-pane -t=; send -M }' config/rmux/rmux.conf
    grep -Fq "bind -n MouseDrag1Pane { if -F '#{||:#{pane_in_mode},#{mouse_any_flag}}' { send -M } { copy-mode -M } }" config/rmux/rmux.conf
    if grep -Eq '(^|[[:space:]])(@plugin|run-shell|run |if-shell.*git clone)' config/rmux/rmux.conf; then
      echo "RMUX config contains a plugin or shell bootstrap" >&2
      return 1
    fi
    if grep -Eq 'set-environment.*TERM_PROGRAM' config/rmux/rmux.conf; then
      echo "RMUX config overrides RMUX's terminal identity" >&2
      return 1
    fi

    rmux -L "$socket" kill-session -t validate
    /usr/bin/script -q "$test_root/first" /bin/sh -c \
      "rmux -L '$socket' -f '$repo_root/config/rmux/rmux.conf' new-session -A -s main" \
      >/dev/null 2>&1 &
    client_pid=$!
    for _ in 1 2 3 4 5; do
      rmux -L "$socket" has-session -t main >/dev/null 2>&1 && break
      sleep 1
    done
    first_session="$(rmux -L "$socket" list-sessions -F '#{session_name}|#{session_id}|#{session_attached}')"
    first_pane="$(rmux -L "$socket" list-panes -t main -F '#{pane_id}')"
    printf '%s\n' "$first_session" | grep -Eq '^main\|[^|]+\|1$'
    rmux -L "$socket" detach-client -s main
    wait "$client_pid" || true
    [ "$(rmux -L "$socket" list-sessions -F '#{session_name}|#{session_attached}')" = "main|0" ]

    /usr/bin/script -q "$test_root/second" /bin/sh -c \
      "rmux -L '$socket' new-session -A -s main" >/dev/null 2>&1 &
    client_pid=$!
    for _ in 1 2 3 4 5; do
      [ "$(rmux -L "$socket" list-sessions -F '#{session_attached}')" = "1" ] && break
      sleep 1
    done
    second_session="$(rmux -L "$socket" list-sessions -F '#{session_name}|#{session_id}|#{session_attached}')"
    second_pane="$(rmux -L "$socket" list-panes -t main -F '#{pane_id}')"
    [ "${first_session%|1}" = "${second_session%|1}" ]
    [ "$first_pane" = "$second_pane" ]
    [ "$(rmux -L "$socket" list-sessions -F '#{session_name}' | grep -c '^main$')" -eq 1 ]
    rmux -L "$socket" detach-client -s main
    wait "$client_pid" || true
    rmux -L "$socket" has-session -t main

    /usr/bin/script -q "$test_root/closed-tab" /bin/sh -c \
      "rmux -L '$socket' attach-session -t main" >/dev/null 2>&1 &
    client_pid=$!
    for _ in 1 2 3 4 5; do
      [ "$(rmux -L "$socket" list-sessions -F '#{session_attached}')" = "1" ] && break
      sleep 1
    done
    kill "$client_pid" 2>/dev/null || true
    wait "$client_pid" 2>/dev/null || true
    sleep 1
    rmux -L "$socket" has-session -t main
    [ "$(rmux -L "$socket" list-sessions -F '#{session_name}|#{session_id}|#{session_attached}')" = "${first_session%|1}|0" ]
    [ "$(rmux -L "$socket" list-panes -t main -F '#{pane_id}')" = "$first_pane" ]
  )

  echo "RMUX config/resume ok: C-q profile, Apollo status, OSC 7 path relay, and stable main session across detach"
}

run_apollo_smoke() {
  local test_root fixtures fake_bin test_home lock bad_lock first_current curl_count_before curl_count_after out

  [ -f scripts/apollo-releases.tsv ]
  [ -f scripts/apollo-theme.sh ]
  [ ! -d themes/apollo ]
  [ ! -f config/sonicterm/themes/wezterm.toml ]
  grep -Fq 'theme = "apollo"' config/sonicterm/sonicterm.toml
  grep -Fq 'apollo-rmux.conf' config/rmux/rmux.conf
  grep -Fq 'EZA_CONFIG_DIR' config/zsh/custom.zsh
  grep -Fq 'ZSH_THEME=apollo' config/zsh/custom.zsh
  grep -Fq 'FAST_WORK_DIR' config/zsh/custom.zsh
  grep -Fq $'link\tconfig/zsh/themes/apollo.zsh-theme\t.oh-my-zsh/custom/themes/apollo.zsh-theme' config/manifest.tsv
  jq -e '.theme == "custom:apollo"' config/claude/settings.json >/dev/null
  jq -e '.theme == "default"' config/copilot/settings.json >/dev/null

  if grep -En '#[0-9a-fA-F]{6}|38;2;|48;2;' \
      config/rmux/rmux.conf \
      config/claude/statusline.sh \
      config/copilot/statusline.sh \
      config/zsh/themes/apollo.zsh-theme; then
    echo "tracked active theme consumers contain embedded palette colors" >&2
    return 1
  fi

  test_root="$(mktemp -d)"
  trap 'rm -rf "${test_root:-}"' RETURN
  fixtures="$test_root/fixtures"
  fake_bin="$test_root/bin"
  test_home="$test_root/home"
  lock="$test_root/releases.tsv"
  bad_lock="$test_root/releases-bad.tsv"
  mkdir -p "$fixtures" "$fake_bin" "$test_home/.claude" "$test_home/.sonicterm/themes"

  python3 - "$fixtures/palette.json" <<'PY'
import json
import sys

color = lambda value: f"#{value:06x}"
colors = {
    "background": color(1),
    "surface": color(2),
    "surfaceHover": color(3),
    "selection": color(4),
    "foreground": color(5),
    "foregroundSecondary": color(6),
    "foregroundInactive": color(7),
    "foregroundBright": color(8),
    "accent": color(9),
    "danger": color(10),
    "success": color(11),
    "info": color(12),
    "magenta": color(13),
    "cyan": color(14),
    "ansiBrightBlack": color(15),
}
palette = {
    "schemaVersion": 1,
    "id": "apollo",
    "name": "Apollo",
    "appearance": "dark",
    "colors": colors,
    "roles": {
        "canvas": "{colors.background}",
        "textPrimary": "{colors.foreground}",
        "textSecondary": "{colors.foregroundSecondary}",
        "textInactive": "{colors.foregroundInactive}",
        "focus": "{colors.accent}",
        "error": "{colors.danger}",
        "warning": "{colors.accent}",
        "success": "{colors.success}",
        "information": "{colors.info}",
    },
    "terminal": {
        "foreground": colors["foreground"],
        "background": colors["background"],
        "cursor": colors["accent"],
        "cursorText": colors["background"],
        "selection": {"color": colors["selection"], "alpha": 0.5, "foregroundMode": "preserve"},
        "ansi": [color(value) for value in range(16, 24)],
        "bright": [color(value) for value in range(24, 32)],
    },
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(palette, handle, separators=(",", ":"))
    handle.write("\n")
PY
  printf 'name = "Apollo"\n' >"$fixtures/apollo.toml"
  printf 'set-option -g status-style "bg=default,fg=default"\n' >"$fixtures/apollo-rmux.conf"
  printf 'colourful: true\n' >"$fixtures/theme.yml"

  {
    printf '# id\tkind\trepository\ttag\tartifact\tsha256\n'
    printf 'palette\traw\texample/apollo-theme\tv1.0.0\tpalette/apollo.json\t%s\n' "$(shasum -a 256 "$fixtures/palette.json" | awk '{print $1}')"
    printf 'sonicterm\trelease\texample/sonicterm-apollo-theme\tv1.0.0\tapollo.toml\t%s\n' "$(shasum -a 256 "$fixtures/apollo.toml" | awk '{print $1}')"
    printf 'rmux\trelease\texample/rmux-apollo-theme\tv1.0.0\tapollo-rmux.conf\t%s\n' "$(shasum -a 256 "$fixtures/apollo-rmux.conf" | awk '{print $1}')"
    printf 'eza\trelease\texample/eza-apollo-theme\tv1.0.0\ttheme.yml\t%s\n' "$(shasum -a 256 "$fixtures/theme.yml" | awk '{print $1}')"
  } >"$lock"

  cat >"$fake_bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
url=""
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    http*) url=$1; shift ;;
    *) shift ;;
  esac
done
printf '%s\n' "$url" >>"$APOLLO_TEST_CURL_LOG"
case "$url" in
  */palette/apollo.json) source_file="$APOLLO_TEST_FIXTURES/palette.json" ;;
  */apollo.toml) source_file="$APOLLO_TEST_FIXTURES/apollo.toml" ;;
  */apollo-rmux.conf) source_file="$APOLLO_TEST_FIXTURES/apollo-rmux.conf" ;;
  */theme.yml) source_file="$APOLLO_TEST_FIXTURES/theme.yml" ;;
  *) exit 22 ;;
esac
cp "$source_file" "$out"
SH
  chmod +x "$fake_bin/curl"
  printf '{"keep":true}\n' >"$test_home/.claude.json"
  printf 'user theme\n' >"$test_home/.sonicterm/themes/apollo.toml"

  (
    export HOME="$test_home"
    export PATH="$fake_bin:$PATH"
    export APOLLO_RELEASES_FILE="$lock"
    export APOLLO_ROOT="$test_home/.local/share/dot-configs/apollo"
    export APOLLO_TEST_FIXTURES="$fixtures"
    export APOLLO_TEST_CURL_LOG="$test_root/curl.log"
    export APOLLO_SKIP_FSH=1
    DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh
    timestamp="20000101000000"
    apollo_validate_lock "$APOLLO_RELEASES_FILE"
    install_apollo_themes
    printf '{"keep":true,"theme":"custom:apollo","second":true}\n' >"$test_home/.claude.json.next"
    backup_path_once "$test_home/.claude.json"
    mv "$test_home/.claude.json.next" "$test_home/.claude.json"
  )

  jq -e '.keep == true and (has("theme") | not)' \
    "$test_home/.claude.json.bak.20000101000000" >/dev/null
  jq -e '.theme == "custom:apollo" and .second == true' "$test_home/.claude.json" >/dev/null
  [ -L "$test_home/.local/share/dot-configs/apollo/current" ]
  first_current="$(readlink "$test_home/.local/share/dot-configs/apollo/current")"
  mkdir -p "$test_root/blocked-home"
  printf 'blocked\n' >"$test_root/blocked-home/.sonicterm"
  printf 'adapter-v2\n' >"$test_root/adapter-v2"
  if (
    export HOME="$test_root/blocked-home"
    export PATH="$fake_bin:$PATH"
    export APOLLO_RELEASES_FILE="$lock"
    export APOLLO_ROOT="$test_home/.local/share/dot-configs/apollo"
    export APOLLO_THEME_SCRIPT="$test_root/adapter-v2"
    export APOLLO_TEST_FIXTURES="$fixtures"
    export APOLLO_TEST_CURL_LOG="$test_root/curl.log"
    export APOLLO_SKIP_FSH=1
    DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh
    install_apollo_themes
  ) >/dev/null 2>&1; then
    echo "Apollo activation unexpectedly succeeded with a blocked consumer path" >&2
    return 1
  fi
  [ "$(readlink "$test_home/.local/share/dot-configs/apollo/current")" = "$first_current" ]

  mkdir -p "$test_home/.local/share/dot-configs/apollo/sets/switch-test"
  (
    export HOME="$test_home"
    DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh
    apollo_switch_current "$test_home/.local/share/dot-configs/apollo" "sets/switch-test"
  )
  [ "$(readlink "$test_home/.local/share/dot-configs/apollo/current")" = "sets/switch-test" ]
  (
    export HOME="$test_home"
    DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh
    apollo_switch_current "$test_home/.local/share/dot-configs/apollo" "$first_current"
  )
  [ "$(readlink "$test_home/.local/share/dot-configs/apollo/current")" = "$first_current" ]
  [ -L "$test_home/.sonicterm/themes/apollo.toml" ]
  grep -Fq 'user theme' "$test_home/.sonicterm/themes/apollo.toml.bak."*
  [ -L "$test_home/.config/rmux-apollo-theme/apollo-rmux.conf" ]
  [ -L "$test_home/.config/eza-apollo-theme/theme.yml" ]
  [ -L "$test_home/.claude/themes/apollo.json" ]
  jq -e '.keep == true and .theme == "custom:apollo"' "$test_home/.claude.json" >/dev/null
  jq -e '
    .name == "Apollo" and
    .base == "dark-ansi" and
    (.overrides | type == "object") and
    .overrides.diffAdded == "#000004" and
    .overrides.diffRemoved == "#000003" and
    .overrides.diffAddedDimmed == "#000003" and
    .overrides.diffRemovedDimmed == "#000002" and
    .overrides.diffAddedWord == "#000005" and
    .overrides.diffRemovedWord == "#000004" and
    .overrides.diffAdded != .overrides.success and
    .overrides.diffRemoved != .overrides.error
  ' "$test_home/.claude/themes/apollo.json" >/dev/null
  bash -n "$test_home/.local/share/dot-configs/apollo/current/generated/statusline-colors.sh"
  zsh -n "$test_home/.local/share/dot-configs/apollo/current/generated/zsh-colors.zsh"

  curl_count_before="$(wc -l <"$test_root/curl.log" | tr -d ' ')"
  (
    export HOME="$test_home"
    export PATH="$fake_bin:$PATH"
    export APOLLO_RELEASES_FILE="$lock"
    export APOLLO_ROOT="$test_home/.local/share/dot-configs/apollo"
    export APOLLO_TEST_FIXTURES="$fixtures"
    export APOLLO_TEST_CURL_LOG="$test_root/curl.log"
    export APOLLO_SKIP_FSH=1
    DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh
    install_apollo_themes
  )
  curl_count_after="$(wc -l <"$test_root/curl.log" | tr -d ' ')"
  [ "$curl_count_before" = "$curl_count_after" ]
  [ "$first_current" = "$(readlink "$test_home/.local/share/dot-configs/apollo/current")" ]
  [ "$(find "$test_home/.sonicterm/themes" -name 'apollo.toml.bak.*' | wc -l | tr -d ' ')" = "1" ]

  awk -F '\t' 'BEGIN { OFS="\t" } $1 == "palette" { $6 = "0000000000000000000000000000000000000000000000000000000000000000" } { print }' \
    "$lock" >"$bad_lock"
  if (
    export HOME="$test_home"
    export PATH="$fake_bin:$PATH"
    export APOLLO_RELEASES_FILE="$bad_lock"
    export APOLLO_ROOT="$test_home/.local/share/dot-configs/apollo"
    export APOLLO_TEST_FIXTURES="$fixtures"
    export APOLLO_TEST_CURL_LOG="$test_root/curl.log"
    export APOLLO_SKIP_FSH=1
    DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh
    install_apollo_themes
  ) >/dev/null 2>&1; then
    echo "Apollo installer accepted a checksum mismatch" >&2
    return 1
  fi
  [ "$first_current" = "$(readlink "$test_home/.local/share/dot-configs/apollo/current")" ]

  out="$(printf '{}' | HOME="$test_home" bash config/claude/statusline.sh)"
  printf '%s' "$out" | grep -q $'\033\[38;2;'
  out="$(printf '{}' | HOME="$test_home" CLAUDE_STATUSLINE_NO_COLOR=1 bash config/claude/statusline.sh)"
  if printf '%s' "$out" | grep -q $'\033\['; then
    echo "Claude no-color status line still emits ANSI escapes" >&2
    return 1
  fi

  local colors_file payload old_home pct code rows
  colors_file="$test_home/.local/share/dot-configs/apollo/current/generated/statusline-colors.sh"
  grep -Fq "C_FG_BRIGHT=" "$colors_file" || {
    echo "generated statusline colors are missing C_FG_BRIGHT" >&2
    return 1
  }
  (
    # shellcheck disable=SC1090
    . "$colors_file"
    [ "$C_FG_BRIGHT" = "$(printf '\033[38;2;0;0;8m')" ] || {
      echo "C_FG_BRIGHT was not generated from foregroundBright" >&2
      exit 1
    }
    [ "$C_FG" = "$(printf '\033[38;2;0;0;5m')" ]
    [ "$C_FG_DIM" = "$(printf '\033[38;2;0;0;7m')" ]
  )

  # Selected segments use the bright role for values; labels keep their roles.
  payload='{"model":{"display_name":"Claude Sonnet 4.5 (max)"},"workspace":{"current_dir":"'"$test_home"'"},"context_window":{"used_percentage":50,"context_window_size":100000}}'
  out="$(printf '%s' "$payload" | HOME="$test_home" \
    COPILOT_STATUSLINE_NO_ICONS=1 \
    COPILOT_STATUSLINE_SEGMENTS='model effort ctx \n path' \
    bash config/copilot/statusline.sh)"
  printf '%s' "$out" | grep -Fq $'\033[38;2;0;0;9mModel\033[0m \033[38;2;0;0;8mSonnet 4.5\033[0m' || {
    echo "Model segment lost the yellow label / bright value styling" >&2
    return 1
  }
  printf '%s' "$out" | grep -Fq $'\033[38;2;0;0;13mEffort\033[0m \033[38;2;0;0;8mmax\033[0m' || {
    echo "Effort segment lost the bright value styling" >&2
    return 1
  }
  printf '%s' "$out" | grep -Fq $'\033[38;2;0;0;14mPath\033[0m \033[38;2;0;0;8m~\033[0m' || {
    echo "Path segment lost the aqua label / bright value styling" >&2
    return 1
  }
  # Capacity suffix and ordinary separators use the dim foreground, not C_DIM.
  printf '%s' "$out" | grep -Fq $'\033[38;2;0;0;7m/100k\033[0m' || {
    echo "context capacity is not using the dim foreground role" >&2
    return 1
  }
  printf '%s' "$out" | grep -Fq $'\033[38;2;0;0;7m │ \033[0m' || {
    echo "ordinary separators are not using the dim foreground role" >&2
    return 1
  }
  if printf '%s' "$out" | grep -Fq $'\033[2m'; then
    echo "ordinary status-line row still emits the bare C_DIM attribute" >&2
    return 1
  fi

  # Numeric context boundaries keep green / yellow / red.
  while IFS=' ' read -r pct code; do
    [ -n "$pct" ] || continue
    out="$(printf '{"context_window":{"used_percentage":%s}}' "$pct" | HOME="$test_home" \
      COPILOT_STATUSLINE_NO_ICONS=1 COPILOT_STATUSLINE_SEGMENTS='ctx' \
      bash config/copilot/statusline.sh)"
    printf '%s' "$out" | grep -Fq "$(printf '\033[38;2;0;0;%sm%s%%' "$code" "$pct")" || {
      echo "context color boundary changed at ${pct}%" >&2
      return 1
    }
  done <<'BOUNDS'
49 11
50 9
80 10
BOUNDS

  # A file preserves the trailing newline of an empty last row.
  printf '%s' "$payload" | HOME="$test_home" bash config/copilot/statusline.sh \
    >"$test_root/default-line.txt"
  rows="$(tr -dc '\n' <"$test_root/default-line.txt" | wc -c | tr -d ' ')"
  [ "$rows" = "4" ] || {
    echo "default Copilot status line is no longer five rows (separators: $rows)" >&2
    return 1
  }

  # No-color, legacy no-dim, and a missing include all stay plain text.
  for mode in COPILOT_STATUSLINE_NO_COLOR COPILOT_STATUSLINE_NO_DIM; do
    out="$(printf '%s' "$payload" | HOME="$test_home" \
      env "$mode=1" bash config/copilot/statusline.sh)"
    if printf '%s' "$out" | grep -q $'\033\['; then
      echo "$mode=1 still emits ANSI escapes" >&2
      return 1
    fi
    printf '%s' "$out" | grep -Fq 'Sonnet 4.5'
  done
  out="$(printf '%s' "$payload" | HOME="$test_root/blocked-home" bash config/copilot/statusline.sh)"
  if printf '%s' "$out" | grep -q $'\033\['; then
    echo "a missing color include still emits ANSI escapes" >&2
    return 1
  fi

  # An older include without C_FG_BRIGHT falls back to C_FG, never to empty.
  old_home="$test_root/old-include-home"
  mkdir -p "$old_home/.local/share/dot-configs/apollo/current/generated"
  grep -v 'C_FG_BRIGHT=' "$colors_file" \
    >"$old_home/.local/share/dot-configs/apollo/current/generated/statusline-colors.sh"
  out="$(printf '%s' "$payload" | HOME="$old_home" \
    COPILOT_STATUSLINE_NO_ICONS=1 COPILOT_STATUSLINE_SEGMENTS='model' \
    bash config/copilot/statusline.sh)"
  printf '%s' "$out" | grep -Fq $'\033[38;2;0;0;9mModel\033[0m \033[38;2;0;0;5mSonnet 4.5\033[0m' || {
    echo "an older color include did not fall back to C_FG" >&2
    return 1
  }

  # The shared generator must not change Claude's status line.
  if grep -Fq 'C_FG_BRIGHT' config/claude/statusline.sh; then
    echo "Claude status line must not adopt the bright foreground role" >&2
    return 1
  fi
  out="$(printf '{}' | HOME="$test_home" bash config/claude/statusline.sh)"
  if printf '%s' "$out" | grep -Fq $'\033[38;2;0;0;8m'; then
    echo "Claude status line started emitting the bright foreground color" >&2
    return 1
  fi

  rm -rf "$test_root"
  test_root=""
  trap - RETURN
  echo "Apollo release bundle, generated adapters, and safe activation ok"
}

run_smoke() {
  run_bash_syntax
  run_apollo_smoke
  run_statusline_smoke
  bash -n install.sh
  run_zsh_syntax
  run_structure_smoke
  run_manifest_smoke
  run_launchd_template_smoke
  run_subagent_smoke
  run_claude_subagent_limit_smoke
  run_model_default_smoke
  run_claude_github_mcp_warning_smoke
  run_copilot_terminal_smoke
  run_global_instructions_smoke
  run_wiki_smoke
  run_pipeline_scripts_smoke
  run_rmux_helpers_smoke
  run_rmux_keymap_docs_smoke
  run_retired_config_migration_smoke
  run_rmux_smoke
}

case "${1:-all}" in
  smoke) run_smoke ;;
  apollo) run_apollo_smoke ;;
  apollo-online) DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh; verify_apollo_release_pins ;;
  instructions) run_global_instructions_smoke ;;
  models) run_model_default_smoke ;;
  mcp) run_claude_github_mcp_warning_smoke ;;
  wiki) run_wiki_smoke; run_pipeline_scripts_smoke; run_rmux_keymap_docs_smoke ;;
  rmux) run_rmux_helpers_smoke; run_rmux_keymap_docs_smoke; run_retired_config_migration_smoke; run_rmux_smoke ;;
  shellcheck) run_shellcheck ;;
  all) run_smoke; run_shellcheck ;;
  *)
    echo "usage: $0 [smoke|apollo|apollo-online|instructions|models|mcp|wiki|rmux|shellcheck|all]" >&2
    exit 2
    ;;
esac
