#!/usr/bin/env bash
# Custom status line for Copilot CLI (~/.copilot/statusline.sh).
#
# Sibling of ~/.claude/statusline.sh — same vibe (one Nerd-Font-iconed
# segment per data point, separated by Unicode bars), each segment gets
# its own Gruvbox accent color so the value pops out from the colored
# icon + label pair to its left. This is a "full mirror" of the Claude
# version: every segment Claude shows is reproduced here when the data
# is exposed by Copilot's statusLine JSON, plus a few Copilot-only
# extras (Cache hit %, Last-call tokens, Premium-request count).
#
# Copilot CLI feeds this script a JSON payload on stdin. Verified
# against `copilot` v1.0.44 by capturing real input — the schema is
# similar to Claude's but missing fields are silently skipped (the
# guarded `seg_*` functions return early on empty values, so adding
# data later just makes more segments appear).
# Available top-level keys (v1.0.44):
#   .session_id, .session_name, .cwd, .transcript_path, .username,
#   .version,
#   .model.{id, display_name},
#   .workspace.current_dir,
#   .remote.connected,
#   .cost.{total_premium_requests, total_api_duration_ms,
#          total_duration_ms, total_lines_added, total_lines_removed},
#   .context_window.{used_percentage, context_window_size,
#          total_input_tokens, total_cache_read_tokens,
#          last_call_input_tokens, last_call_output_tokens, ...}
# NOT exposed by Copilot (so the matching segment silently no-ops):
#   .effort.level (we instead parse the trailing "(xhigh)" / "(high)"
#                  tag baked into .model.display_name)
#   .vim.mode, .agent.name, .workspace.git_worktree, .output_style.name,
#   .cost.total_cost_usd
#
# Default layout matches ~/.claude/statusline.sh:
#   L1: status       — time, run timer, premium requests, waka today
#   L2: model        — model, effort, context
#   L3: integrations — mcp, skills, agents, style
#   L4: cwd path     — full directory path
#   L5: repo + git   — repo, branch, diff, stash, worktree
#   Bottom: separator + active subagents — root + one line per live task subagent
#           each row shows: agent name, purpose, and running time
#
# Additional Copilot-only segments remain available via
# COPILOT_STATUSLINE_SEGMENTS: wall, api, cache_pct, last_call,
# gh_account, ext_count, venv.
#
# Env overrides (mirror the Claude one for muscle memory):
#   COPILOT_STATUSLINE_NO_ICONS=1   drop icons, keep text labels
#   COPILOT_STATUSLINE_NO_COLOR=1   drop color (still pads + separators);
#                                   legacy COPILOT_STATUSLINE_NO_DIM=1
#                                   is honored as an alias.
#   COPILOT_STATUSLINE_PAD_TOP=N    blank lines before the line (default 0)
#   COPILOT_STATUSLINE_PAD_LEFT=N   spaces before the line     (default 0)
#   COPILOT_STATUSLINE_PAD_RIGHT=N  spaces after the line      (default 0)
#   COPILOT_STATUSLINE_SEGMENTS="…" override the segment list (and order)
#   COPILOT_STATUSLINE_MAX_SUBAGENTS=N max active subagent rows (default 8)
#   COPILOT_STATUSLINE_SUBAGENT_ROOT=0 hide the "main" root row
#   COPILOT_STATUSLINE_SUBAGENT_STATE_DIR=dir override hook state dir
#
# Quick check that all icons render in your terminal:
#     ~/.copilot/statusline.sh --test
#
# Bash 3.2-compatible (macOS default). Avoid `set -e` so one bad segment
# can never blank the whole line.

set -u

# --- Configuration ---------------------------------------------------------
# Five-line layout. A literal `\n` token in SEGMENTS introduces a line
# break in the render loop. Empty/no-op segments collapse cleanly so
# auto-hiding ones (worktree, stash, diff, skills, agents) take no space
# when off.
SEGMENTS="${COPILOT_STATUSLINE_SEGMENTS:-time timer premium waka \n model effort ctx \n mcp skills agent subagents style \n path \n git branch diff stash worktree}"
SEP=' │ '
SUBAGENT_SEPARATOR='----------------------------------------'

ICONS_ON=1
[ -n "${COPILOT_STATUSLINE_NO_ICONS:-}" ] && ICONS_ON=0

# Nerd Font icons. Bash 3.2 (macOS default) does not support `\uXXXX` in
# $'...' quoting — only `\xHH` — so each codepoint is spelled as raw
# UTF-8 bytes. All glyphs are FontAwesome (U+F0xx-F2xx range), the same
# subset Claude's statusline uses, so they render in any Nerd Font
# variant including `Symbols Nerd Font Mono`. Verify with --test.
#
#   U+F017 clock           = EF 80 97   Time
#   U+F2DB microchip        = EF 8B 9B   Model
#   U+F0E4 dashboard        = EF 83 A4   Effort
#   U+F254 hourglass        = EF 89 94   Wall
#   U+F233 server           = EF 88 B3   API
#   U+F155 dollar           = EF 85 95   Req (premium request count)
#   U+F021 refresh          = EF 80 A1   Cache
#   U+F1D8 paper-plane      = EF 87 98   Last
#   U+F121 code            = EF 84 A1   Diff
#   U+F07C folder-open     = EF 81 BC   Path
#   U+F1C0 database         = EF 87 80   Context
#   U+F121 code             = EF 84 A1   Vim
#   U+F135 rocket           = EF 84 B5   Agent / Run
#   U+F1BB tree             = EF 86 BB   Worktree
#   U+F0AD wrench           = EF 82 AD   Style
#   U+F0E8 sitemap          = EF 83 A8   Repo
#   U+F126 code-fork        = EF 84 A6   Branch
#   U+F187 archive          = EF 86 87   Stash
#   U+F1AE flask            = EF 86 AE   Venv
#   U+F09B github           = EF 82 9B   GH
#   U+F11C keyboard         = EF 84 9C   WakaTime
#   U+F0AE list-task        = EF 82 AE   Skills / Ext
#   U+F1E6 plug             = EF 87 A6   MCP
ICON_TIME=$'\xef\x80\x97'
ICON_MODEL=$'\xef\x8b\x9b'
ICON_EFFORT=$'\xef\x83\xa4'
ICON_RUN=$'\xef\x84\xb5'
ICON_WALL=$'\xef\x89\x94'
ICON_API=$'\xef\x88\xb3'
ICON_REQ=$'\xef\x85\x95'
ICON_CACHE=$'\xef\x80\xa1'
ICON_LAST=$'\xef\x87\x98'
ICON_DIFF=$'\xef\x84\xa1'
ICON_CTX=$'\xef\x87\x80'
ICON_VIM=$'\xef\x84\xa1'
ICON_AGENT=$'\xef\x84\xb5'
ICON_WORKTREE=$'\xef\x86\xbb'
ICON_STYLE=$'\xef\x82\xad'
ICON_REPO=$'\xef\x83\xa8'
ICON_BRANCH=$'\xef\x84\xa6'
ICON_STASH=$'\xef\x86\x87'
ICON_VENV=$'\xef\x86\xae'
ICON_PATH=$'\xef\x81\xbc'
ICON_GH=$'\xef\x82\x9b'
ICON_WAKA=$'\xef\x84\x9c'
ICON_SKILLS=$'\xef\x82\xae'
ICON_EXT=$'\xef\x82\xae'
ICON_MCP=$'\xef\x87\xa6'
# U+F085 cogs             = EF 82 85   Mode
# U+F015 home             = EF 80 95   Main (root) row
# U+F135 rocket           = EF 84 B5   Active subagent row
ICON_SUBAGENT_ROOT=$'\xef\x80\x95'
ICON_SUBAGENT=$'\xef\x84\xb5'
ICON_MODE=$'\xef\x82\x85'

# Gruvbox Dark Hard accents — match alacritty/wezterm/.tmux.conf palette.
# Use 24-bit ANSI so we don't depend on the terminal's 256-color cube.
# Honor both COPILOT_STATUSLINE_NO_COLOR (preferred) and the legacy
# COPILOT_STATUSLINE_NO_DIM as an alias for backwards-compat.
if [ -z "${COPILOT_STATUSLINE_NO_COLOR:-}" ] && [ -z "${COPILOT_STATUSLINE_NO_DIM:-}" ]; then
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'                                # dim for separator + labels
  C_RED=$'\033[38;2;251;73;52m'                   # #fb4934
  C_GREEN=$'\033[38;2;184;187;38m'                # #b8bb26
  C_YELLOW=$'\033[38;2;250;189;47m'               # #fabd2f
  C_BLUE=$'\033[38;2;131;165;152m'                # #83a598
  C_PURPLE=$'\033[38;2;211;134;155m'              # #d3869b
  C_AQUA=$'\033[38;2;142;192;124m'                # #8ec07c
  C_ORANGE=$'\033[38;2;254;128;25m'               # #fe8019
  C_FG=$'\033[38;2;235;219;178m'                  # #ebdbb2
  C_FG_DIM=$'\033[38;2;168;153;132m'              # #a89984 — gruvbox fg3
else
  C_RESET=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
  C_PURPLE=""; C_AQUA=""; C_ORANGE=""; C_FG=""
  C_FG_DIM=""
fi

# Per-side padding emitted from inside the script. Copilot CLI's
# statusLine.padding* fields are silently ignored — only the single
# `padding` key is honored — so we apply our own spacing here for
# finer control.
PAD_TOP="${COPILOT_STATUSLINE_PAD_TOP:-0}"
PAD_LEFT="${COPILOT_STATUSLINE_PAD_LEFT:-0}"
PAD_RIGHT="${COPILOT_STATUSLINE_PAD_RIGHT:-0}"

repeat() {
  local ch=$1 n=$2 out=""
  while [ "$n" -gt 0 ]; do out="${out}${ch}"; n=$((n - 1)); done
  printf '%s' "$out"
}

CACHE_DIR="${TMPDIR:-/tmp}/copilot-statusline-cache-$USER"
mkdir -p "$CACHE_DIR" 2>/dev/null || true

# --- --test flag: visually verify which icons render -----------------------
if [ "${1:-}" = "--test" ]; then
  has_fc=0
  command -v fc-list >/dev/null 2>&1 && has_fc=1
  printf 'Codepoint  Glyph  Label    Font check\n'
  printf -- '---------- ------ -------- ----------------------------------------\n'
  while IFS='|' read -r cp_hex glyph lbl; do
    [ -z "$cp_hex" ] && continue
    fc_status='(fc-list not installed)'
    if [ "$has_fc" = "1" ]; then
      fonts="$(fc-list ":charset=$cp_hex" 2>/dev/null \
                | grep -v '^/.*\.LastResort' | wc -l | tr -d ' ')"
      if [ "$fonts" -gt 0 ]; then
        fc_status="✓ in $fonts font(s)"
      else
        fc_status="✗ MISSING from real fonts"
      fi
    fi
    printf 'U+%-7s  %s     %-7s  %s\n' "$cp_hex" "$glyph" "$lbl" "$fc_status"
  done <<TEST_ICONS_EOF
f017|${ICON_TIME}|Time
f2db|${ICON_MODEL}|Model
f0e4|${ICON_EFFORT}|Effort
f135|${ICON_RUN}|Run
f254|${ICON_WALL}|Wall
f233|${ICON_API}|API
f155|${ICON_REQ}|Req
f021|${ICON_CACHE}|Cache
f1d8|${ICON_LAST}|Last
f121|${ICON_DIFF}|Diff
f1c0|${ICON_CTX}|Context
f121|${ICON_VIM}|Vim
f135|${ICON_AGENT}|Agent
f1bb|${ICON_WORKTREE}|Worktree
f0ad|${ICON_STYLE}|Style
f0e8|${ICON_REPO}|Repo
f126|${ICON_BRANCH}|Branch
f187|${ICON_STASH}|Stash
f1ae|${ICON_VENV}|Venv
f07c|${ICON_PATH}|Path
f09b|${ICON_GH}|GH
f11c|${ICON_WAKA}|WakaTime
f0ae|${ICON_SKILLS}|Skills
f0ae|${ICON_EXT}|Ext
f1e6|${ICON_MCP}|MCP
f015|${ICON_SUBAGENT_ROOT}|Main
f135|${ICON_SUBAGENT}|SubAgent
TEST_ICONS_EOF
  exit 0
fi

# --- 1. Read JSON payload from stdin ---------------------------------------
session_json=""
if [ ! -t 0 ]; then
  session_json="$(cat 2>/dev/null || true)"
fi

# --- 2. Parse all fields with one jq call (one field per line) -------------
session_id=""
session_name=""
transcript_path=""
model_name=""
cwd=""
premium="0"
api_ms="0"
total_ms="0"
lines_added="0"
lines_removed="0"
total_input="0"
cache_read="0"
last_in="0"
last_out="0"
ctx_pct=""
ctx_size=""
json_mode=""
if [ -n "$session_json" ] && command -v jq >/dev/null 2>&1; then
  {
    IFS= read -r session_id    || session_id=""
    IFS= read -r session_name  || session_name=""
    IFS= read -r transcript_path || transcript_path=""
    IFS= read -r model_name    || model_name=""
    IFS= read -r cwd           || cwd=""
    IFS= read -r premium       || premium="0"
    IFS= read -r api_ms        || api_ms="0"
    IFS= read -r total_ms      || total_ms="0"
    IFS= read -r lines_added   || lines_added="0"
    IFS= read -r lines_removed || lines_removed="0"
    IFS= read -r total_input   || total_input="0"
    IFS= read -r cache_read    || cache_read="0"
    IFS= read -r last_in       || last_in="0"
    IFS= read -r last_out      || last_out="0"
    IFS= read -r ctx_pct       || ctx_pct=""
    IFS= read -r ctx_size      || ctx_size=""
    IFS= read -r json_mode     || json_mode=""
  } < <(printf '%s' "$session_json" | jq -r '
        (.session_id // ""),
        (.session_name // ""),
        (.transcript_path // ""),
        ((.model.display_name // .model.id) // ""),
        ((.workspace.current_dir // .cwd) // ""),
        (.cost.total_premium_requests // 0),
        (.cost.total_api_duration_ms // 0),
        (.cost.total_duration_ms // 0),
        (.cost.total_lines_added // 0),
        (.cost.total_lines_removed // 0),
        (.context_window.total_input_tokens // 0),
        (.context_window.total_cache_read_tokens // 0),
        (.context_window.last_call_input_tokens // 0),
        (.context_window.last_call_output_tokens // 0),
        (.context_window.used_percentage // ""),
        (.context_window.context_window_size // .context_window.size // ""),
        (.mode // .session.mode // .config.mode // "")
      ' 2>/dev/null)
fi

# Copilot sends transcript_path as a directory; append events.jsonl if needed.
if [ -n "$transcript_path" ] && [ -d "$transcript_path" ]; then
  transcript_path="${transcript_path}/events.jsonl"
fi

if [ -z "$transcript_path" ] && [ -n "$session_id" ]; then
  candidate="$HOME/.copilot/session-state/$session_id/events.jsonl"
  [ -f "$candidate" ] && transcript_path="$candidate"
  unset candidate
fi

# Make $cwd's git state available to seg_repo / seg_branch / seg_stash so
# we report the workspace's repo, not the (likely irrelevant) repo of
# wherever Copilot CLI was launched from.
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  cd "$cwd" 2>/dev/null || true
fi

# Effort is not a top-level JSON field in Copilot — it's appended to
# .model.display_name as " (low)" / " (medium)" / " (high)" / " (xhigh)".
# Extract the *last* parenthesized token whose contents matches a known
# effort word so we don't accidentally pick up "(1M context)" etc.
effort_level=""
if [ -n "$model_name" ]; then
  case "$model_name" in
    *'(xhigh)'*)  effort_level="xhigh" ;;
    *'(high)'*)   effort_level="high" ;;
    *'(medium)'*) effort_level="medium" ;;
    *'(low)'*)    effort_level="low" ;;
  esac
fi

# --- 3. Helpers ------------------------------------------------------------
label() {
  # "<color><icon> <Label> <reset>" — icon + label share the segment's
  # accent color; the value (printed by the segment after this returns)
  # uses C_FG so it reads as the bright eye-catcher.
  local color="$1" icon="$2" text="$3"
  if [ "$ICONS_ON" = "1" ]; then
    printf '%s%s %s%s ' "$color" "$icon" "$text" "$C_RESET"
  else
    printf '%s%s%s ' "$color" "$text" "$C_RESET"
  fi
}

is_pos_int() {
  case "${1:-}" in
    '' | *[!0-9]*) return 1 ;;
    0) return 1 ;;
    *) return 0 ;;
  esac
}

fmt_ms() {
  local ms=${1:-0}
  local s=$((ms / 1000))
  if [ "$s" -ge 3600 ]; then
    printf '%dh%dm' $((s / 3600)) $(((s % 3600) / 60))
  elif [ "$s" -ge 60 ]; then
    printf '%dm' $((s / 60))
  else
    printf '%ds' "$s"
  fi
}

fmt_dhm() {
  local s=${1:-0}
  local days rem hours mins
  is_pos_int "$s" || { printf ''; return; }
  days=$((s / 86400))
  rem=$((s % 86400))
  hours=$((rem / 3600))
  mins=$(((rem % 3600) / 60))

  if [ "$days" -gt 0 ]; then
    if [ "$hours" -gt 0 ]; then printf '%sd %sh' "$days" "$hours"; else printf '%sd' "$days"; fi
  elif [ "$hours" -gt 0 ]; then
    if [ "$mins" -gt 0 ]; then printf '%sh %sm' "$hours" "$mins"; else printf '%sh' "$hours"; fi
  elif [ "$mins" -gt 0 ]; then
    printf '%sm' "$mins"
  else
    printf '%ss' "$s"
  fi
}

# Format a token count: 200000 -> 200k, 1000000 -> 1M.
fmt_tokens() {
  local n=${1:-0}
  if [ "$n" -ge 1000000 ]; then
    awk -v n="$n" 'BEGIN{ printf("%.1fM", n/1000000) }'
  elif [ "$n" -ge 1000 ]; then
    awk -v n="$n" 'BEGIN{ printf("%dk", int(n/1000)) }'
  else
    printf '%d' "$n"
  fi
}

# --- 4. Segment functions --------------------------------------------------
seg_time() {
  printf '%s%s%s%s' "$(label "$C_YELLOW" "$ICON_TIME" 'Time')" "$C_FG" "$(date '+%H:%M:%S')" "$C_RESET"
}

seg_model() {
  [ -n "$model_name" ] || return 0
  # Trim Copilot's verbose names, e.g.
  #   "Claude Opus 4.7 (1M context)(Internal only) (10x) (xhigh)"
  #   -> "Opus 4.7 (1M)"
  # Drop the leading vendor word ("Claude "), strip "(Internal only)" /
  # "(10x)" / "(low|medium|high|xhigh)" no matter how they're spaced, and
  # squash "(1M context)" -> "(1M)". Single sed pipe for portability —
  # bash 3.2's parameter expansion can't match optional leading spaces.
  local short="$model_name"
  short="${short#Claude }"
  short="$(printf '%s' "$short" | sed -E '
        s/ ?\(Internal only\)//g
        s/ ?\([0-9]+x\)//g
        s/ ?\((xhigh|high|medium|low)\)//g
        s/\(([0-9.]+[KMG]?) context\)/(\1)/g
        s/  +/ /g
        s/ +$//
      ')"
  printf '%s%s%s%s' "$(label "$C_AQUA" "$ICON_MODEL" 'Model')" "$C_FG" "$short" "$C_RESET"
}

seg_effort() {
  [ -n "$effort_level" ] || return 0
  printf '%s%s%s%s' "$(label "$C_PURPLE" "$ICON_EFFORT" 'Effort')" "$C_FG" "$effort_level" "$C_RESET"
}

seg_timer() {
  [ -n "$session_id" ] || return 0
  local f="${TMPDIR:-/tmp}/copilot-statusline-${USER}-${session_id}.start"
  if [ ! -f "$f" ]; then
    date +%s >"$f" 2>/dev/null || true
  fi
  [ -f "$f" ] || return 0
  local started now elapsed
  read -r started <"$f" 2>/dev/null || started=0
  now="$(date +%s)"
  is_pos_int "$started" || started="$now"
  elapsed=$((now - started))
  [ "$elapsed" -ge 60 ] || return 0
  printf '%s%s%s%s' "$(label "$C_ORANGE" "$ICON_RUN" 'Run')" "$C_FG" "$(fmt_dhm "$elapsed")" "$C_RESET"
}

seg_wall() {
  is_pos_int "$total_ms" || return 0
  printf '%s%s%s%s' "$(label "$C_PURPLE" "$ICON_WALL" 'Wall')" "$C_FG" "$(fmt_ms "$total_ms")" "$C_RESET"
}

seg_api() {
  is_pos_int "$api_ms" || return 0
  printf '%s%s%s%s' "$(label "$C_BLUE" "$ICON_API" 'API')" "$C_FG" "$(fmt_ms "$api_ms")" "$C_RESET"
}

seg_premium() {
  is_pos_int "$premium" || return 0
  printf '%s%s%d%s' "$(label "$C_GREEN" "$ICON_REQ" 'Req')" "$C_FG" "$premium" "$C_RESET"
}

seg_cache_pct() {
  is_pos_int "$total_input" || return 0
  local pct=$(((cache_read * 100) / total_input))
  # higher is better for cache hit; color-grade green→yellow→red as it
  # drops, so a glance tells you how cache-friendly the session is.
  local color="$C_GREEN"
  if [ "$pct" -lt 30 ]; then
    color="$C_RED"
  elif [ "$pct" -lt 60 ]; then
    color="$C_YELLOW"
  fi
  printf '%s%s%d%%%s' "$(label "$C_AQUA" "$ICON_CACHE" 'Cache')" "$color" "$pct" "$C_RESET"
}

seg_last_call() {
  is_pos_int "$last_in" || return 0
  printf '%s%s%s→%s%s' "$(label "$C_PURPLE" "$ICON_LAST" 'Last')" \
    "$C_FG" "$(fmt_tokens "$last_in")" "$(fmt_tokens "$last_out")" "$C_RESET"
}

# Diff is in SEGMENTS only when the user opts in — Copilot's footer can
# show this via showCodeChanges, and most of the time the noise/value
# tradeoff isn't worth it. Kept here so re-enabling is just a matter of
# adding `diff` to SEGMENTS.
seg_diff() {
  local a="${lines_added:-0}" r="${lines_removed:-0}"
  is_pos_int "$a" || is_pos_int "$r" || return 0
  printf '%s%s+%d%s%s/-%d%s' \
    "$(label "$C_GREEN" "$ICON_DIFF" 'Diff')" \
    "$C_GREEN" "$a" "$C_RESET" \
    "$C_RED" "$r" "$C_RESET"
}

# Ctx — context window usage. Copilot's `.context_window.used_percentage`
# is integer %. Show absolute size parenthetically when known. Color-grade
# green→yellow→red so a glance tells you how much room is left.
seg_ctx() {
  [ -n "$ctx_pct" ] || return 0
  local pct_int
  pct_int="$(awk -v p="$ctx_pct" 'BEGIN{ printf("%d", p+0) }')"
  local color="$C_GREEN"
  if [ "$pct_int" -ge 80 ]; then
    color="$C_RED"
  elif [ "$pct_int" -ge 50 ]; then
    color="$C_YELLOW"
  fi
  local body
  if [ -n "$ctx_size" ] && [ "$ctx_size" != "null" ]; then
    body="${color}${pct_int}%${C_RESET}${C_DIM}/$(fmt_tokens "$ctx_size")${C_RESET}"
  else
    body="${color}${pct_int}%${C_RESET}"
  fi
  printf '%s%s' "$(label "$C_AQUA" "$ICON_CTX" 'Context')" "$body"
}

# Path — full cwd as its own line, matching the Claude statusline. Replace
# $HOME with ~ for brevity.
seg_path() {
  [ -n "$cwd" ] || return 0
  local p="$cwd"
  case "$p" in
    "$HOME") p="~" ;;
    "$HOME"/*) p="~${p#$HOME}" ;;
  esac
  printf '%s%s%s%s' "$(label "$C_BLUE" "$ICON_PATH" 'Path')" "$C_FG" "$p" "$C_RESET"
}

# Vim / Style — Copilot CLI doesn't currently surface equivalent runtime
# JSON fields, so these no-op for visual/layout parity with Claude.
seg_vim()    { return 0; }
seg_style()  { return 0; }

# Subagents — inline count of currently running subagents. Shows "0" when
# idle, colored by activity: green=0, yellow=1-2, orange=3+. The detailed
# per-agent rows render at the bottom of the statusline separately.
seg_subagents() {
  local n="${__SUBAGENT_COUNT:-0}"
  local color="$C_GREEN"
  if [ "$n" -ge 3 ]; then
    color="$C_ORANGE"
  elif [ "$n" -ge 1 ]; then
    color="$C_YELLOW"
  fi
  printf '%s%s%d%s' "$(label "$C_PURPLE" "$ICON_SUBAGENT" 'Tasks')" "$color" "$n" "$C_RESET"
}

# Agent — count Copilot custom agent definitions in user + project scope.
# This counts local profile files on disk, not currently running subagents.
seg_agent() {
  local total=0 d count seen=""
  local project_root="${cwd:-$PWD}"
  for d in \
      "${HOME}/.copilot/agents" \
      "${project_root}/.github/agents"; do
    [ -d "$d" ] || continue
    case "$seen" in *":$d:"*) continue ;; esac
    seen="$seen:$d:"
    count="$(find "$d" -mindepth 1 -maxdepth 1 -type f -name '*.md' ! -name '.*' ! -iname 'README.md' 2>/dev/null | wc -l | tr -d ' ')"
    total=$((total + count))
  done
  printf '%s%s%d%s' "$(label "$C_PURPLE" "$ICON_AGENT" 'Agents')" "$C_FG" "$total" "$C_RESET"
}

# Skills — count user-scope + workspace-scope skill bundles.
seg_skills() {
  local total=0 d count seen=""
  local project_root="${cwd:-$PWD}"
  for d in \
      "${HOME}/.copilot/skills" \
      "${HOME}/.agents/skills" \
      "${project_root}/.github/skills" \
      "${project_root}/.claude/skills" \
      "${project_root}/.agents/skills"; do
    [ -d "$d" ] || continue
    case "$seen" in *":$d:"*) continue ;; esac
    seen="$seen:$d:"
    count="$(find "$d" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')"
    total=$((total + count))
  done
  printf '%s%s%d%s' "$(label "$C_AQUA" "$ICON_SKILLS" 'Skills')" "$C_FG" "$total" "$C_RESET"
}

# Worktree — Copilot doesn't expose .workspace.git_worktree, but we can
# detect a worktree by looking at the resolved git dir. In a linked
# worktree, git rev-parse --git-dir returns "<main>/.git/worktrees/<name>".
# Emit only the worktree name, and only when not in the main worktree
# (where the segment would otherwise appear on every repo).
GIT_INSIDE=0
GIT_STATE=""
GIT_SYNC=""
GIT_BRANCH=""
GIT_STASH="0"
GIT_WORKTREE=""
GIT_STATE_READY=0

load_git_state() {
  [ "$GIT_STATE_READY" = "1" ] && return 0
  GIT_STATE_READY=1

  GIT_INSIDE=0
  GIT_STATE=""
  GIT_SYNC=""
  GIT_BRANCH=""
  GIT_STASH="0"
  GIT_WORKTREE=""

  local key cf now mtime ttl cache_src
  cache_src="${cwd:-$PWD}"
  key="${cache_src//[^A-Za-z0-9_.-]/_}"
  cf="$CACHE_DIR/git-${key}"
  now="$(date +%s)"
  ttl="${COPILOT_STATUSLINE_GIT_TTL:-5}"
  case "$ttl" in '' | *[!0-9]*) ttl=5 ;; esac

  mtime=0
  [ -f "$cf" ] && mtime="$(stat -f %m "$cf" 2>/dev/null || stat -c %Y "$cf" 2>/dev/null || echo 0)"
  if [ -f "$cf" ] && [ $((now - mtime)) -lt "$ttl" ]; then
    {
      IFS= read -r GIT_INSIDE || GIT_INSIDE=0
      IFS= read -r GIT_STATE || GIT_STATE=""
      IFS= read -r GIT_SYNC || GIT_SYNC=""
      IFS= read -r GIT_BRANCH || GIT_BRANCH=""
      IFS= read -r GIT_STASH || GIT_STASH="0"
      IFS= read -r GIT_WORKTREE || GIT_WORKTREE=""
    } <"$cf" 2>/dev/null || GIT_INSIDE=0
    return 0
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    {
      printf '0\n'
      printf '\n'
      printf '\n'
      printf '\n'
      printf '0\n'
      printf '\n'
    } >"$cf" 2>/dev/null || true
    return 0
  fi

  GIT_INSIDE=1

  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    GIT_STATE="dirty"
  else
    GIT_STATE="clean"
  fi

  local counts behind ahead
  if counts="$(git rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)"; then
    behind="${counts%%	*}"
    ahead="${counts##*	}"
    if [ "${ahead:-0}" -gt 0 ] 2>/dev/null; then
      GIT_SYNC="${GIT_SYNC}↑${ahead}"
    fi
    if [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
      GIT_SYNC="${GIT_SYNC}↓${behind}"
    fi
  fi

  GIT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null \
    || git rev-parse --short HEAD 2>/dev/null \
    || true)"

  GIT_STASH="$(git stash list 2>/dev/null | wc -l | tr -d ' ')"
  is_pos_int "$GIT_STASH" || GIT_STASH="0"

  local gd name
  gd="$(git rev-parse --git-dir 2>/dev/null || true)"
  case "$gd" in
    *'/.git/worktrees/'*)
      name="${gd##*/.git/worktrees/}"
      GIT_WORKTREE="${name%%/*}"
      ;;
  esac

  {
    printf '%s\n' "$GIT_INSIDE"
    printf '%s\n' "$GIT_STATE"
    printf '%s\n' "$GIT_SYNC"
    printf '%s\n' "$GIT_BRANCH"
    printf '%s\n' "$GIT_STASH"
    printf '%s\n' "$GIT_WORKTREE"
  } >"$cf" 2>/dev/null || true
}

seg_worktree() {
  load_git_state
  [ "$GIT_INSIDE" = "1" ] || return 0
  [ -n "$GIT_WORKTREE" ] || return 0
  printf '%s%s%s%s' "$(label "$C_AQUA" "$ICON_WORKTREE" 'Worktree')" "$C_FG" "$GIT_WORKTREE" "$C_RESET"
}

seg_repo() {
  load_git_state
  [ "$GIT_INSIDE" = "1" ] || return 0
  local state_color="$C_GREEN"
  [ "$GIT_STATE" = "dirty" ] && state_color="$C_YELLOW"
  if [ -n "$GIT_SYNC" ]; then
    printf '%s%s%s%s %s(%s)%s' \
      "$(label "$C_AQUA" "$ICON_REPO" 'Repo')" \
      "$state_color" "$GIT_STATE" "$C_RESET" \
      "$C_ORANGE" "$GIT_SYNC" "$C_RESET"
  else
    printf '%s%s%s%s' \
      "$(label "$C_AQUA" "$ICON_REPO" 'Repo')" \
      "$state_color" "$GIT_STATE" "$C_RESET"
  fi
}

seg_git() { seg_repo; }

seg_branch() {
  load_git_state
  [ "$GIT_INSIDE" = "1" ] || return 0
  local br="$GIT_BRANCH"
  [ -n "$br" ] || return 0
  if [ ${#br} -gt 24 ]; then
    br="${br:0:23}…"
  fi
  printf '%s%s%s%s' "$(label "$C_YELLOW" "$ICON_BRANCH" 'Branch')" "$C_FG" "$br" "$C_RESET"
}

seg_stash() {
  load_git_state
  [ "$GIT_INSIDE" = "1" ] || return 0
  local count="$GIT_STASH"
  is_pos_int "$count" || return 0
  printf '%s%s%d%s' "$(label "$C_ORANGE" "$ICON_STASH" 'Stash')" "$C_FG" "$count" "$C_RESET"
}

seg_venv() {
  [ -n "${VIRTUAL_ENV:-}" ] || return 0
  printf '%s%s%s%s' "$(label "$C_BLUE" "$ICON_VENV" 'Venv')" "$C_FG" "$(basename "$VIRTUAL_ENV")" "$C_RESET"
}

seg_gh_account() {
  command -v gh >/dev/null 2>&1 || return 0
  local cf="$CACHE_DIR/gh_account"
  local now mtime account
  now="$(date +%s)"
  mtime=0
  if [ -f "$cf" ]; then
    mtime="$(stat -f %m "$cf" 2>/dev/null || stat -c %Y "$cf" 2>/dev/null || echo 0)"
  fi
  if [ -f "$cf" ] && [ $((now - mtime)) -lt 300 ]; then
    account="$(cat "$cf" 2>/dev/null || true)"
  else
    account="$(gh auth status 2>&1 | awk '
      /Logged in to github\.com account /{
        for (i=1; i<=NF; i++) if ($i=="account") { print $(i+1); exit }
      }' | head -1)"
    printf '%s' "$account" >"$cf" 2>/dev/null || true
  fi
  [ -n "$account" ] || return 0
  printf '%s%s%s%s' "$(label "$C_PURPLE" "$ICON_GH" 'GH')" "$C_FG" "$account" "$C_RESET"
}

# WakaTime — today's coding time as recorded by WakaTime. Cache for 5
# minutes and refresh in the background so statusline rendering stays fast.
seg_waka() {
  local wt="$HOME/.wakatime/wakatime-cli"
  [ -x "$wt" ] || return 0
  local cf="$CACHE_DIR/waka_today"
  local lock="$CACHE_DIR/waka_today.lock"
  local now mtime val=""
  now="$(date +%s)"
  mtime=0
  [ -f "$cf" ] && mtime="$(stat -f %m "$cf" 2>/dev/null || stat -c %Y "$cf" 2>/dev/null || echo 0)"
  if [ -f "$cf" ] && [ $((now - mtime)) -lt 300 ]; then
    read -r val <"$cf" 2>/dev/null || val=""
  else
    if [ -d "$lock" ]; then
      local lock_mtime
      lock_mtime="$(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || echo 0)"
      [ $((now - lock_mtime)) -gt 60 ] && rmdir "$lock" 2>/dev/null
    fi
    if mkdir "$lock" 2>/dev/null; then
      (
        trap 'rmdir "'"$lock"'" 2>/dev/null' EXIT
        "$wt" --today >"$cf.tmp" 2>/dev/null \
          && mv "$cf.tmp" "$cf" 2>/dev/null
      ) &
    fi
    [ -f "$cf" ] && read -r val <"$cf" 2>/dev/null
  fi
  [ -n "$val" ] || return 0

  local hrs=0 mins=0 secs=0 total rest
  case "$val" in *' hr'*) hrs="${val%% hr*}" ;; esac
  rest="$val"
  case "$rest" in *' hr'*) rest="${rest#*hrs }"; rest="${rest#*hr }" ;; esac
  case "$rest" in *' min'*) mins="${rest%% min*}" ;; esac
  rest="$val"
  case "$rest" in *' min'*) rest="${rest#*mins }"; rest="${rest#*min }" ;; esac
  case "$rest" in *' sec'*) secs="${rest%% sec*}" ;; esac
  case "$hrs" in '' | *[!0-9]*) hrs=0 ;; esac
  case "$mins" in '' | *[!0-9]*) mins=0 ;; esac
  case "$secs" in '' | *[!0-9]*) secs=0 ;; esac
  total=$((hrs * 3600 + mins * 60 + secs))
  [ "$total" -ge 60 ] || return 0
  printf '%s%s%s%s' "$(label "$C_AQUA" "$ICON_WAKA" 'WakaTime')" "$C_FG" "$(fmt_dhm "$total")" "$C_RESET"
}

# Ext — count Copilot CLI extensions in user-scope + project-scope dirs.
# Per the SDK docs: "the CLI scans .github/extensions/ (project) and the
# user's copilot config extensions directory for subdirectories
# containing extension.mjs". The user-scope dir isn't documented as a
# fixed path, so we check the conventional candidates and de-dupe.
seg_ext_count() {
  local total=0 d count
  local seen=""
  local user_root="${PWD}/.github/extensions"
  for d in \
      "${HOME}/.copilot/extensions" \
      "${HOME}/.config/copilot/extensions" \
      "${HOME}/.config/github-copilot/extensions" \
      "$user_root"; do
    [ -d "$d" ] || continue
    case "$seen" in *":$d:"*) continue ;; esac
    seen="$seen:$d:"
    count="$(find "$d" -mindepth 2 -maxdepth 2 -name 'extension.mjs' -type f 2>/dev/null | wc -l | tr -d ' ')"
    total=$((total + count))
  done
  is_pos_int "$total" || return 0
  printf '%s%s%d%s' "$(label "$C_AQUA" "$ICON_EXT" 'Ext')" "$C_FG" "$total" "$C_RESET"
}

seg_mcp_count() {
  local f="$HOME/.copilot/mcp-config.json"
  [ -f "$f" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local count
  count="$(jq -r '(.mcpServers // {}) | length' "$f" 2>/dev/null)"
  is_pos_int "$count" || return 0
  printf '%s%s%d%s' "$(label "$C_BLUE" "$ICON_MCP" 'MCP')" "$C_FG" "$count" "$C_RESET"
}

seg_mcp() { seg_mcp_count; }

# Mode — Copilot CLI runs in one of: interactive (default), plan, autopilot,
# or yolo (all permissions). Detection priority:
#   1. COPILOT_STATUSLINE_MODE env override (always wins)
#   2. .mode from the JSON payload (if Copilot exposes it)
#   3. Latest mode-change event in events.jsonl (catches mid-session switches)
#   4. Process-tree sniffing of launch args (fallback for initial mode)
# Manual override:
#   COPILOT_STATUSLINE_MODE=yolo|autopilot|plan|interactive
# Cached per-pid for 10s (reduced from 30s for responsiveness).

# Detect mode from events.jsonl transcript — catches mid-session switches
# (e.g. user types /plan or /autopilot) that process-tree sniffing misses.
detect_mode_from_transcript() {
  [ -n "$transcript_path" ] || return 0
  [ -f "$transcript_path" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local key cf sig cached_sig mode=""
  key="$(printf '%s' "$transcript_path" | cksum | awk '{print $1}')"
  cf="$CACHE_DIR/mode-transcript-${key}"
  sig="$(statusline_file_sig "$transcript_path")"

  if [ -f "$cf" ]; then
    IFS= read -r cached_sig <"$cf" 2>/dev/null || cached_sig=""
    if [ "$cached_sig" = "$sig" ]; then
      sed -n '2p' "$cf" 2>/dev/null || true
      return 0
    fi
  fi

  # Scan the last N lines for mode-change indicators:
  #   - Events with type containing "mode" and a .data.mode field
  #   - User messages that are mode-switch slash commands
  #   - autopilot_mode / plan_mode toggles in event data
  # Take the LAST match — that's the current mode.
  mode="$(tail -n 2000 "$transcript_path" 2>/dev/null | jq -r '
    (
      # Direct mode field in event data
      if (.data.mode // "") != "" then .data.mode
      # session.mode_changed events (Copilot CLI format)
      elif (.data.newMode // "") != "" then .data.newMode
      # autopilot_mode flag toggled
      elif .type == "config.changed" and (.data.key // "") == "autopilot_mode" then
        if .data.value == true then "autopilot" else "interactive" end
      elif .type == "config.changed" and (.data.key // "") == "plan_mode" then
        if .data.value == true then "plan" else "interactive" end
      # Mode change events (generic pattern)
      elif (.type | test("mode[._]changed"; "i")) then
        (.data.mode // .data.newMode // .data.new_mode // "")
      # User slash commands that switch modes
      elif .type == "user.message" or .type == "user.command" then
        ((.data.content // .data.message // .message.content // "") | tostring) as $txt
        | if ($txt | test("^\\s*/autopilot\\b"; "i")) then "autopilot"
          elif ($txt | test("^\\s*/plan\\b"; "i")) then "plan"
          elif ($txt | test("^\\s*/yolo\\b"; "i")) then "yolo"
          elif ($txt | test("^\\s*/interactive\\b"; "i")) then "interactive"
          else ""
          end
      else ""
      end
    ) // ""
  ' 2>/dev/null | grep -v '^$' | tail -1)"

  { printf '%s\n' "$sig"; printf '%s\n' "$mode"; } >"$cf" 2>/dev/null || true
  printf '%s' "$mode"
}

detect_copilot_mode() {
  local override="${COPILOT_STATUSLINE_MODE:-}"
  if [ -n "$override" ]; then
    printf '%s' "$override"
    return
  fi
  # Walk up the process tree from this script to find a `copilot` invocation.
  local pid=$PPID args="" ppid="" comm="" depth=0 mode=""
  while [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$pid" != "1" ] && [ "$depth" -lt 8 ]; do
    args="$(ps -o args= -p "$pid" 2>/dev/null)"
    comm="$(ps -o comm= -p "$pid" 2>/dev/null)"
    case "$args $comm" in
      *' copilot '*|*'/copilot '*|*' copilot'|*'/copilot'|*'copilot-cli'*)
        case "$args" in
          *' --yolo'*)            mode="yolo" ;;
          *' --autopilot'*)       mode="autopilot" ;;
          *' --plan'*)            mode="plan" ;;
          *' --mode yolo'*)       mode="yolo" ;;
          *' --mode autopilot'*)  mode="autopilot" ;;
          *' --mode plan'*)       mode="plan" ;;
          *' --mode interactive'*) mode="interactive" ;;
          *)                      mode="interactive" ;;
        esac
        break
        ;;
    esac
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ -n "$ppid" ] && [ "$ppid" != "$pid" ] || break
    pid="$ppid"
    depth=$((depth + 1))
  done
  printf '%s' "$mode"
}

seg_mode() {
  local mode=""

  # Priority 1: env override
  if [ -n "${COPILOT_STATUSLINE_MODE:-}" ]; then
    mode="$COPILOT_STATUSLINE_MODE"

  # Priority 2: JSON payload
  elif [ -n "$json_mode" ]; then
    mode="$json_mode"

  # Priority 3: transcript events (catches mid-session switches)
  # Priority 4: process-tree sniffing (launch-time fallback)
  else
    local cf="$CACHE_DIR/mode-$PPID" now mtime
    now="$(date +%s)"
    mtime=0
    [ -f "$cf" ] && mtime="$(stat -f %m "$cf" 2>/dev/null || stat -c %Y "$cf" 2>/dev/null || echo 0)"
    if [ -f "$cf" ] && [ $((now - mtime)) -lt 10 ]; then
      read -r mode <"$cf" 2>/dev/null || mode=""
    else
      # Try transcript first, fall back to process-tree
      mode="$(detect_mode_from_transcript)"
      [ -n "$mode" ] || mode="$(detect_copilot_mode)"
      printf '%s\n' "$mode" >"$cf" 2>/dev/null || true
    fi
  fi

  [ -n "$mode" ] || return 0
  local color="$C_BLUE"
  case "$mode" in
    yolo)        color="$C_RED" ;;
    autopilot)   color="$C_ORANGE" ;;
    plan)        color="$C_PURPLE" ;;
    interactive) color="$C_GREEN" ;;
  esac
  printf '%s%s%s%s' "$(label "$C_AQUA" "$ICON_MODE" 'Mode')" "$color" "$mode" "$C_RESET"
}

statusline_int_or_default() {
  local val="${1:-}" default="$2"
  case "$val" in
    '' | *[!0-9]*) printf '%s' "$default" ;;
    *) printf '%s' "$val" ;;
  esac
}

statusline_file_sig() {
  stat -f '%m:%z' "$1" 2>/dev/null || stat -c '%Y:%s' "$1" 2>/dev/null || echo 0
}

format_subagent_rows() {
  local rows="$1" out="" name purpose elapsed root
  [ -n "$rows" ] || return 0

  root="${STATUSLINE_SUBAGENT_ROOT:-1}"
  root="${COPILOT_STATUSLINE_SUBAGENT_ROOT:-$root}"
  case "$root" in
    0 | false | FALSE | no | NO) root=0 ;;
    *) root=1 ;;
  esac
  if [ "$root" = 1 ]; then
    out="${C_GREEN}${ICON_SUBAGENT_ROOT}${C_RESET} ${C_FG}main${C_RESET}"
  fi

  while IFS=$'\037' read -r name purpose elapsed; do
    [ -n "$name$purpose" ] || continue
    [ -n "$out" ] && out="${out}"$'\n'
    [ -n "$name" ] || name="agent"
    if [ -n "$purpose" ]; then
      out="${out}${C_YELLOW}${ICON_SUBAGENT}${C_RESET} ${C_FG}${name}${C_RESET}${C_DIM}:${C_RESET} ${C_FG_DIM}${purpose}${C_RESET}"
    else
      out="${out}${C_YELLOW}${ICON_SUBAGENT}${C_RESET} ${C_FG}${name}${C_RESET}"
    fi
    # Append running time when available (elapsed > 0)
    case "${elapsed:-}" in
      '' | *[!0-9]*) ;;
      0) ;;
      *)
        out="${out} ${C_DIM}($(fmt_dhm "$elapsed"))${C_RESET}"
        ;;
    esac
  done <<EOF
$rows
EOF
  printf '%s' "$out"
}

render_subagents() {
  [ -n "$session_id" ] || return 0

  local max state_dir key state_file now rows block name purpose started elapsed count us
  max="$(statusline_int_or_default "${COPILOT_STATUSLINE_MAX_SUBAGENTS:-${STATUSLINE_MAX_SUBAGENTS:-8}}" 8)"
  [ "$max" -gt 0 ] 2>/dev/null || return 0

  state_dir="${COPILOT_STATUSLINE_SUBAGENT_STATE_DIR:-${TMPDIR:-/tmp}/copilot-subagents-${USER:-default}}"
  key="$(printf '%s' "$session_id" | cksum)"
  key="${key%% *}"
  state_file="${state_dir}/${key}.rows"
  [ -r "$state_file" ] || return 0

  now="$(date +%s 2>/dev/null || printf '0')"
  rows=""
  count=0
  us=$'\037'
  while IFS=$'\037' read -r name purpose started; do
    [ -n "$name$purpose" ] || continue
    case "${started:-}" in
      '' | *[!0-9]*) elapsed=0 ;;
      *)
        elapsed=$((now - started))
        [ "$elapsed" -lt 0 ] && elapsed=0
        ;;
    esac
    [ -n "$rows" ] && rows="${rows}"$'\n'
    rows="${rows}${name}${us}${purpose}${us}${elapsed}"
    count=$((count + 1))
    [ "$count" -ge "$max" ] && break
  done <"$state_file"

  block="$(format_subagent_rows "$rows")"
  printf '%s' "$block"
}

# --- 5. Render -------------------------------------------------------------
# Pre-compute git once in the main shell. Segment functions run via command
# substitution, so they inherit these already-loaded values instead of each
# segment re-reading the git cache in its own subshell.
load_git_state

# Pre-compute hook-maintained subagent rows so seg_subagents (inline count)
# and the bottom rows agree without scanning the session event log.
__SUBAGENT_BLOCK="$(render_subagents 2>/dev/null || true)"
__SUBAGENT_COUNT=0
if [ -n "$__SUBAGENT_BLOCK" ]; then
  _total_lines=0
  while IFS= read -r _subagent_line; do
    _total_lines=$((_total_lines + 1))
  done <<EOF
$__SUBAGENT_BLOCK
EOF
  _root="${COPILOT_STATUSLINE_SUBAGENT_ROOT:-${STATUSLINE_SUBAGENT_ROOT:-1}}"
  case "$_root" in 0|false|FALSE|no|NO) __SUBAGENT_COUNT="$_total_lines" ;; *) __SUBAGENT_COUNT=$((_total_lines - 1)) ;; esac
  [ "$__SUBAGENT_COUNT" -ge 0 ] 2>/dev/null || __SUBAGENT_COUNT=0
fi

# A literal `\n` token in $SEGMENTS introduces a line break: segments before
# it form line 1, segments after it form line 2.
out=""
line_started=0
for s in $SEGMENTS; do
  if [ "$s" = '\n' ]; then
    out="${out}"$'\n'
    line_started=0
    continue
  fi
  part="$("seg_$s" 2>/dev/null || true)"
  [ -n "$part" ] || continue
  if [ "$line_started" = 1 ]; then
    out="${out}${C_DIM}${SEP}${C_RESET}${part}"
  else
    out="${out}${part}"
    line_started=1
  fi
done

[ -n "$__SUBAGENT_BLOCK" ] && out="${out}"$'\n'"${C_DIM}${SUBAGENT_SEPARATOR}${C_RESET}"$'\n'"${__SUBAGENT_BLOCK}"

# Emit top padding via dedicated printfs — $(...) command substitution
# strips trailing newlines, which would silently drop PAD_TOP entirely.
i=0
while [ "$i" -lt "$PAD_TOP" ]; do
  printf '\n'
  i=$((i + 1))
done

printf '%s%s%s' \
  "$(repeat ' ' "$PAD_LEFT")" \
  "$out" \
  "$(repeat ' ' "$PAD_RIGHT")"
