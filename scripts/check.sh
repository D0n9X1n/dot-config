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
  done < <(find config/zsh -maxdepth 1 -type f -name '*.zsh' -print | sort)
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
  ' config/claude/settings.json >/dev/null

  # Copilot CLI: Opus 5 at the 1M context tier and max effort.
  jq -e '
    .model == "claude-opus-5" and
    .contextTier == "long_context" and
    .effortLevel == "max"
  ' config/copilot/settings.json >/dev/null

  # Relay: Opus route -> claude-opus-5, GPT route stays gpt-5.6-sol, max effort.
  grep -Eq '^opusModel:[[:space:]]*claude-opus-5$' config/copilot-relay/config.yaml
  grep -Eq '^gptModel:[[:space:]]*gpt-5\.6-sol$' config/copilot-relay/config.yaml
  grep -Eq '^thinkEffort:[[:space:]]*max$' config/copilot-relay/config.yaml

  grep -Fq $'link\tconfig/copilot-relay/config.yaml\t.copilot-relay/config.yaml' config/manifest.tsv

  # Launcher wrappers inject the same defaults (settings.json can be rewritten
  # at runtime, so the flags are the authoritative per-launch pin).
  grep -Fq -- "--model 'claude-sonnet-5[1m]'" config/zsh/claude.zsh
  grep -Fq -- "--model 'claude-sonnet-5[1m]' --effort max" config/zsh/cc.zsh
  grep -Fq -- "--model claude-opus-5 --context long_context --effort max" config/zsh/gg.zsh

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
      zsh -c 'source config/zsh/copilot.zsh; copilot status; [[ "$TERM_PROGRAM" = rmux ]]'
    grep -Fq 'WezTerm|truecolor|3|status' "$direct_capture"

    PATH="$fake_bin:$PATH" COPILOT_CAPTURE="$gg_capture" TERM_PROGRAM=rmux \
      zsh -c 'unset RMUX TMUX WEZTERM_PANE; source config/zsh/gg.zsh; gg terminal-smoke >/dev/null; [[ "$TERM_PROGRAM" = rmux ]]'
    grep -Fq 'WezTerm|truecolor|3|--allow-all-tools --allow-all-paths --model claude-opus-5 --context long_context --effort max' "$gg_capture"
  )

  echo "Copilot launchers advertise WezTerm truecolor without replacing RMUX identity"
}

run_global_instructions_smoke() {
  local file lines
  local files=(
    .claude/CLAUDE.md
    .github/copilot-instructions.md
    config/claude/CLAUDE.md
    config/copilot/AGENTS.md
    config/copilot/copilot-instructions.md
  )

  for file in "${files[@]}"; do
    [ -f "$file" ] || {
      echo "missing instruction source: $file" >&2
      return 1
    }
    grep -Fq 'wiki/README.md' "$file"
  done

  for file in .claude/CLAUDE.md .github/copilot-instructions.md; do
    grep -Fq 'config/manifest.tsv' "$file"
    grep -Fq 'scripts/check.sh all' "$file"
    grep -Fq 'full source of truth' "$file"
    lines="$(wc -l <"$file" | tr -d ' ')"
    [ "$lines" -le 60 ] || {
      echo "$file must stay short" >&2
      return 1
    }
  done

  grep -Fq 'Do not use ASCII-art flowcharts' config/claude/CLAUDE.md
  for file in config/claude/CLAUDE.md config/copilot/AGENTS.md; do
    grep -Fq 'Development-and-Releases.md' "$file"
    grep -Fq 'scripts/check.sh all' "$file"
    lines="$(wc -l <"$file" | tr -d ' ')"
    [ "$lines" -le 40 ] || {
      echo "$file must point to the Wiki instead of copying it" >&2
      return 1
    }
  done

  grep -Fq 'Run tools and commands without asking for approval.' config/copilot/copilot-instructions.md
  grep -Fq 'AGENTS.md' config/copilot/copilot-instructions.md
  grep -Fq 'COPILOT_CUSTOM_INSTRUCTIONS_DIRS' config/copilot/copilot-instructions.md

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

    HOME="$test_home"
    timestamp="20000101000000"
    link_file "$test_repo/config/claude/CLAUDE.md" "$test_home/.claude/CLAUDE.md"
    link_file "$test_repo/config/copilot/AGENTS.md" "$test_home/.copilot/AGENTS.md"

    [ -L "$test_home/.claude/CLAUDE.md" ]
    [ "$(readlink "$test_home/.claude/CLAUDE.md")" = "$test_repo/config/claude/CLAUDE.md" ]
    [ -f "$test_home/.claude/CLAUDE.md.bak.20000101000000" ]
    grep -Fq 'original global instructions' "$test_home/.claude/CLAUDE.md.bak.20000101000000"
    [ -L "$test_home/.copilot/AGENTS.md" ]
    [ "$(readlink "$test_home/.copilot/AGENTS.md")" = "$test_repo/config/copilot/AGENTS.md" ]
  )

  echo "global Claude/Copilot Wiki pointers ok"
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
  [ ! -e themes/apollo/PALETTE.md ]
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
      config/claude config/copilot wiki ReadMe.md archive themes; then
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

  jq -e '
    .colors.background == "#141617" and
    .colors.foreground == "#ebdbb2" and
    (.ansi | length) == 8 and
    (.bright | length) == 8
  ' themes/apollo/palette.json >/dev/null
  (
    local palette_colors file color
    palette_colors="$(jq -r '[.colors[]],.ansi,.bright | flatten | unique[]' \
      themes/apollo/palette.json | tr '[:upper:]' '[:lower:]' | sort -u)"
    for file in \
      themes/apollo/apollo.lua \
      themes/apollo/apollo.vim \
      themes/apollo/apollo.nvim.lua \
      themes/apollo/apollo-color-theme.json \
      themes/apollo/apollo.terminal.json; do
      while IFS= read -r color; do
        printf '%s\n' "$palette_colors" | grep -Fxq "$color" || {
          echo "$file uses a color missing from palette.json: $color" >&2
          return 1
        }
      done < <(grep -Eio '#[0-9a-fA-F]{6}' "$file" |
        tr '[:upper:]' '[:lower:]' | sort -u)
    done
  )

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
    local socket keys test_root first_session first_pane second_session second_pane client_pid
    socket="dot-configs-check-$$"
    test_root="$(mktemp -d)"
    trap 'rmux -L "$socket" kill-server >/dev/null 2>&1 || true; rm -rf "$test_root"' EXIT INT TERM

    rmux -L "$socket" -f /dev/null new-session -d -s validate -x 160 -y 48
    rmux -L "$socket" source-file -n -v config/rmux/rmux.conf >/dev/null
    rmux -L "$socket" source-file config/rmux/rmux.conf

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

  echo "RMUX config/resume ok: C-q profile and stable main session across detach"
}

run_smoke() {
  run_bash_syntax
  run_statusline_smoke
  bash -n install.sh
  run_zsh_syntax
  run_structure_smoke
  run_manifest_smoke
  run_launchd_template_smoke
  run_subagent_smoke
  run_claude_subagent_limit_smoke
  run_model_default_smoke
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
  instructions) run_global_instructions_smoke ;;
  wiki) run_wiki_smoke; run_pipeline_scripts_smoke; run_rmux_keymap_docs_smoke ;;
  rmux) run_rmux_helpers_smoke; run_rmux_keymap_docs_smoke; run_retired_config_migration_smoke; run_rmux_smoke ;;
  shellcheck) run_shellcheck ;;
  all) run_smoke; run_shellcheck ;;
  *)
    echo "usage: $0 [smoke|instructions|wiki|rmux|shellcheck|all]" >&2
    exit 2
    ;;
esac
