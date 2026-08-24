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
  local file
  command -v zsh >/dev/null 2>&1 || return 0
  while IFS= read -r file; do
    zsh -n "$file"
  done < <(find oh-my-zsh-custom -maxdepth 1 -type f -name '*.zsh' -print | sort)
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

run_model_default_smoke() {
  # Claude Code: Sonnet 5 is the startup picker identity and the relay maps its
  # non-Opus name to gpt-5.6-sol; "[1m]" keeps 1M-context accounting.
  jq -e '
    .env.ANTHROPIC_MODEL == "claude-sonnet-5[1m]" and
    .model == "claude-sonnet-5[1m]" and
    .effortLevel == "max" and
    .env.MODEL_REASONING_EFFORT == "max" and
    .env.ANTHROPIC_DEFAULT_SONNET_MODEL == "claude-sonnet-5[1m]" and
    .env.ANTHROPIC_DEFAULT_SONNET_MODEL_NAME == "Sonnet 5" and
    .env.ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION == "Sonnet 5 (1M context), routed by copilot-relay to gpt-5.6-sol" and
    .env.ANTHROPIC_DEFAULT_HAIKU_MODEL == "gpt-5.6-sol[1m]" and
    .env.ANTHROPIC_SMALL_FAST_MODEL == "gpt-5.6-sol[1m]"
  ' claude/settings.json >/dev/null

  # Copilot CLI: Opus 5 at the 1M context tier and max effort.
  jq -e '
    .model == "claude-opus-5" and
    .contextTier == "long_context" and
    .effortLevel == "max"
  ' copilot/settings.json >/dev/null

  # Relay: Opus route -> claude-opus-5, GPT route stays gpt-5.6-sol, max effort.
  grep -Eq '^opusModel:[[:space:]]*claude-opus-5$' .copilot-relay/config.yaml
  grep -Eq '^gptModel:[[:space:]]*gpt-5\.6-sol$' .copilot-relay/config.yaml
  grep -Eq '^thinkEffort:[[:space:]]*max$' .copilot-relay/config.yaml

  # Fresh-box fallback in install.sh must match the tracked relay config.
  grep -Fq "printf 'opusModel: claude-opus-5\\n'" install.sh
  grep -Fq "printf 'gptModel: gpt-5.6-sol\\n'" install.sh
  grep -Fq "printf 'thinkEffort: max\\n'" install.sh

  # Launcher wrappers inject the same defaults (settings.json can be rewritten
  # at runtime, so the flags are the authoritative per-launch pin).
  grep -Fq -- "--model 'claude-sonnet-5[1m]'" oh-my-zsh-custom/claude.zsh
  grep -Fq -- "--model 'claude-sonnet-5[1m]' --effort max" oh-my-zsh-custom/cc.zsh
  grep -Fq -- "--model claude-opus-5 --context long_context --effort max" oh-my-zsh-custom/gg.zsh

  echo "model defaults ok: Sonnet 5 picker identity @ max effort, 1M context (relay upstream: gpt-5.6-sol)"
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
      zsh -c 'source oh-my-zsh-custom/copilot.zsh; copilot status; [[ "$TERM_PROGRAM" = rmux ]]'
    grep -Fq 'WezTerm|truecolor|3|status' "$direct_capture"

    PATH="$fake_bin:$PATH" COPILOT_CAPTURE="$gg_capture" TERM_PROGRAM=rmux \
      zsh -c 'unset RMUX TMUX WEZTERM_PANE; source oh-my-zsh-custom/gg.zsh; gg terminal-smoke >/dev/null; [[ "$TERM_PROGRAM" = rmux ]]'
    grep -Fq 'WezTerm|truecolor|3|--allow-all-tools --allow-all-paths --model claude-opus-5 --context long_context --effort max' "$gg_capture"
  )

  echo "Copilot launchers advertise WezTerm truecolor without replacing RMUX identity"
}

run_global_instructions_smoke() {
  local file
  for file in claude/CLAUDE.md copilot/AGENTS.md copilot/copilot-instructions.md; do
    [ -f "$file" ] || {
      echo "missing global instruction source: $file" >&2
      return 1
    }
  done

  grep -Fq 'do not use ASCII-art flowcharts' claude/CLAUDE.md
  for file in claude/CLAUDE.md copilot/AGENTS.md; do
    grep -Fq 'REPO.wiki.git' "$file"
    grep -Fq 'README.md' "$file"
    grep -Fq 'Home.md' "$file"
    grep -Fq 'publish-wiki.yml' "$file"
    grep -Fq 'fetch-depth: 0' "$file"
    grep -Fq 'current_commit' "$file"
    grep -Fq 'previous_tag' "$file"
    grep -Fq 'git log --reverse' "$file"
    grep -Fq 'softprops/action-gh-release@v2' "$file"
    grep -Fq 'gh release view' "$file"
  done
  ! grep -Eqi 'RMUX|SonicTerm|copilot-relay' copilot/AGENTS.md
  grep -Fq 'Run all tools and commands without asking for user approval.' copilot/copilot-instructions.md
  grep -Fq 'AGENTS.md' copilot/copilot-instructions.md
  grep -Fq 'COPILOT_CUSTOM_INSTRUCTIONS_DIRS' copilot/copilot-instructions.md

  zsh -f -c '
    unset COPILOT_CUSTOM_INSTRUCTIONS_DIRS
    source oh-my-zsh-custom/custom.zsh
    [[ "$COPILOT_CUSTOM_INSTRUCTIONS_DIRS" = "$HOME/.copilot" ]]
    source oh-my-zsh-custom/custom.zsh
    [[ "$COPILOT_CUSTOM_INSTRUCTIONS_DIRS" = "$HOME/.copilot" ]]
  '
  COPILOT_CUSTOM_INSTRUCTIONS_DIRS="$HOME/one,$HOME/two" zsh -f -c '
    source oh-my-zsh-custom/custom.zsh
    [[ "$COPILOT_CUSTOM_INSTRUCTIONS_DIRS" = "$HOME/one,$HOME/two,$HOME/.copilot" ]]
  '
  COPILOT_CUSTOM_INSTRUCTIONS_DIRS="$HOME/one,$HOME/.copilot,$HOME/two" zsh -f -c '
    source oh-my-zsh-custom/custom.zsh
    [[ "$COPILOT_CUSTOM_INSTRUCTIONS_DIRS" = "$HOME/one,$HOME/.copilot,$HOME/two" ]]
  '

  (
    local test_root test_home test_repo original
    DOT_CONFIGS_INSTALL_LIB_ONLY=1 source install.sh
    test_root="$(mktemp -d)"
    trap 'rm -rf "$test_root"' EXIT
    test_home="$test_root/home"
    test_repo="$test_root/repo"
    mkdir -p "$test_home/.claude" "$test_home/.copilot" "$test_repo/claude" "$test_repo/copilot"
    printf 'original global instructions\n' >"$test_home/.claude/CLAUDE.md"
    printf 'tracked Claude instructions\n' >"$test_repo/claude/CLAUDE.md"
    printf 'tracked Copilot instructions\n' >"$test_repo/copilot/AGENTS.md"

    HOME="$test_home"
    src_dir="$test_repo"
    timestamp="20000101000000"
    link_file "$test_repo/claude/CLAUDE.md" "$test_home/.claude/CLAUDE.md"
    link_file "$test_repo/copilot/AGENTS.md" "$test_home/.copilot/AGENTS.md"

    [ -L "$test_home/.claude/CLAUDE.md" ]
    [ "$(readlink "$test_home/.claude/CLAUDE.md")" = "$test_repo/claude/CLAUDE.md" ]
    [ -f "$test_home/.claude/CLAUDE.md.bak.20000101000000" ]
    grep -Fq 'original global instructions' "$test_home/.claude/CLAUDE.md.bak.20000101000000"
    [ -L "$test_home/.copilot/AGENTS.md" ]
    [ "$(readlink "$test_home/.copilot/AGENTS.md")" = "$test_repo/copilot/AGENTS.md" ]
  )

  echo "global Claude/Copilot publishing instructions ok"
}

run_wiki_smoke() {
  local file base stem partner target duplicate transformed
  local required=(
    wiki/README.md
    wiki/Home-zh-CN.md
    wiki/RMUX.md
    wiki/RMUX-zh-CN.md
    wiki/RMUX-Keymap.md
    wiki/RMUX-Keymap-zh-CN.md
    wiki/Archive-Tmux.md
    wiki/Archive-Tmux-zh-CN.md
    wiki/Archive-WezTerm.md
    wiki/Archive-WezTerm-zh-CN.md
    wiki/_Sidebar.md
    .github/workflows/publish-wiki.yml
  )

  for file in "${required[@]}"; do
    [ -f "$file" ] || {
      echo "missing Wiki source: $file" >&2
      return 1
    }
  done

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
      README.md)
        partner="Home-zh-CN.md"
        ;;
      _Sidebar.md|*-zh-CN.md)
        continue
        ;;
      *)
        stem="${base%.md}"
        partner="${stem}-zh-CN.md"
        ;;
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
  cp wiki/*.md "$transformed/"
  mv "$transformed/README.md" "$transformed/Home.md"
  sed -i.bak -E 's/\]\(README\.md\)/](Home)/g' "$transformed"/*.md
  sed -i.bak -E 's/\]\(([A-Za-z0-9_-]+)\.md\)/](\1)/g' "$transformed"/*.md
  rm -f "$transformed"/*.bak

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

  grep -Fq 'contents: write' .github/workflows/publish-wiki.yml
  grep -Fq 'wiki/**' .github/workflows/publish-wiki.yml
  grep -Fq 'mv README.md Home.md' .github/workflows/publish-wiki.yml
  grep -Fq 'git push origin HEAD' .github/workflows/publish-wiki.yml
  echo "Wiki source and transformed bilingual link graph ok"
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
      source oh-my-zsh-custom/zz-rmux.zsh
      rr new >/dev/null
    '
    [ "$(sed -n '1p' "$capture")" = "has-session -t new" ]
    [ "$(sed -n '2p' "$capture")" = "new-session -s new" ]

    RMUX_SESSION_EXISTS=1 PATH="$fake_bin:/usr/bin:/bin" RMUX_CAPTURE="$capture" zsh -f -c '
      source oh-my-zsh-custom/zz-rmux.zsh
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
      source oh-my-zsh-custom/zz-rmux.zsh
      exit 7
    ' || exit_status=$?
    [ "$exit_status" = "7" ]

    PATH="$fake_bin:/usr/bin:/bin" RMUX_CAPTURE="$capture" zsh -f -c '
      source oh-my-zsh-custom/zz-rmux.zsh
      rr >/dev/null 2>&1; [[ $? = 2 ]]
      rr one two >/dev/null 2>&1; [[ $? = 2 ]]
      rd >/dev/null 2>&1; [[ $? = 2 ]]
      rl extra >/dev/null 2>&1; [[ $? = 2 ]]
    '

    PATH="/usr/bin:/bin" zsh -f -c '
      source oh-my-zsh-custom/zz-rmux.zsh
      rr main >/dev/null 2>&1; [[ $? = 127 ]]
      rd main >/dev/null 2>&1; [[ $? = 127 ]]
      rl >/dev/null 2>&1; [[ $? = 127 ]]
    '
  )

  grep -Fq 'command rmux has-session -t "$1"' oh-my-zsh-custom/zz-rmux.zsh
  grep -Fq 'command rmux attach-session -t "$1"' oh-my-zsh-custom/zz-rmux.zsh
  grep -Fq 'command rmux new-session -s "$1"' oh-my-zsh-custom/zz-rmux.zsh
  grep -Fq 'command rmux kill-session -t "$1"' oh-my-zsh-custom/zz-rmux.zsh
  grep -Fq 'command rmux list-sessions' oh-my-zsh-custom/zz-rmux.zsh
  [ "$(grep -Fc 'command rmux detach-client' oh-my-zsh-custom/zz-rmux.zsh)" = "3" ]
  grep -Fq "bindkey -M emacs '^D' _rmux_detach_or_delete_char" oh-my-zsh-custom/zz-rmux.zsh
  grep -Fq "bindkey -M viins '^D' _rmux_detach_or_delete_char" oh-my-zsh-custom/zz-rmux.zsh
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

    rmux -L "$socket" -f "$repo_root/.rmux.conf" new-session -d -s keymap-audit -x 160 -y 48
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
  ! grep -Eq '^[[:space:]]+tmux$' install.sh
  ! grep -Eq '^[[:space:]]+wezterm$' install.sh
  ! grep -Fq 'brew install --cask wezterm' install.sh
  ! grep -Eq 'command[[:space:]]+(tmux|wezterm)|wezterm cli' \
    oh-my-zsh-custom/cc.zsh oh-my-zsh-custom/gg.zsh
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
    local socket keys test_root first_session first_pane second_session second_pane client_pid
    socket="dot-configs-check-$$"
    test_root="$(mktemp -d)"
    trap 'rmux -L "$socket" kill-server >/dev/null 2>&1 || true; rm -rf "$test_root"' EXIT INT TERM

    rmux -L "$socket" -f /dev/null new-session -d -s validate -x 160 -y 48
    rmux -L "$socket" source-file -n -v .rmux.conf >/dev/null
    rmux -L "$socket" source-file .rmux.conf

    [ "$(rmux -L "$socket" show-options -gv prefix)" = "C-q" ]
    [ "$(rmux -L "$socket" show-options -gv mouse)" = "on" ]
    [ "$(rmux -L "$socket" show-options -gv history-limit)" = "100000" ]
    [ "$(rmux -L "$socket" show-options -gv base-index)" = "1" ]
    [ "$(rmux -L "$socket" show-options -gv status-position)" = "top" ]
    [ "$(rmux -L "$socket" show-window-options -gv pane-base-index)" = "1" ]

    keys="$(rmux -L "$socket" list-keys -T prefix)"
    printf '%s\n' "$keys" | grep -Eq 'Tab[[:space:]]+last-window'
    printf '%s\n' "$keys" | grep -Fq 'split-window -h -c "#{pane_current_path}"'
    printf '%s\n' "$keys" | grep -Fq 'source-file'
    ! grep -Eq '(^|[[:space:]])(@plugin|run-shell|run |if-shell.*git clone)' .rmux.conf
    ! grep -Eq 'set-environment.*TERM_PROGRAM' .rmux.conf

    rmux -L "$socket" kill-session -t validate
    /usr/bin/script -q "$test_root/first" /bin/sh -c \
      "rmux -L '$socket' -f '$repo_root/.rmux.conf' new-session -A -s main" \
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

  echo "RMUX config/resume ok: C-q profile and stable main session across detach"
}

run_smoke() {
  run_bash_syntax
  run_statusline_smoke
  bash -n install.sh
  run_zsh_syntax
  run_subagent_smoke
  run_claude_subagent_limit_smoke
  run_model_default_smoke
  run_copilot_terminal_smoke
  run_global_instructions_smoke
  run_wiki_smoke
  run_rmux_helpers_smoke
  run_rmux_keymap_docs_smoke
  run_retired_config_migration_smoke
  run_rmux_smoke
}

case "${1:-all}" in
  smoke) run_smoke ;;
  instructions) run_global_instructions_smoke ;;
  wiki) run_wiki_smoke; run_rmux_keymap_docs_smoke ;;
  rmux) run_rmux_helpers_smoke; run_rmux_keymap_docs_smoke; run_retired_config_migration_smoke; run_rmux_smoke ;;
  shellcheck) run_shellcheck ;;
  all) run_smoke; run_shellcheck ;;
  *)
    echo "usage: $0 [smoke|instructions|wiki|rmux|shellcheck|all]" >&2
    exit 2
    ;;
esac
