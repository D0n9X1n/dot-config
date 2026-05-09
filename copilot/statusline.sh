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
# Segments (in render order; each omitted when its data is unavailable):
#   Time      wall-clock HH:MM:SS                          yellow
#   Model     short model name                             aqua
#   Effort    parsed from model.display_name "(xhigh)"     purple
#   Run       minutes since this session_id was first seen orange
#   Wall      total_duration_ms formatted (Hh Mm / Mm / Ss) purple
#   API       total_api_duration_ms formatted              blue
#   Req       total_premium_requests count                 green
#   Cache     cache_read / total_input_tokens, %           aqua, color-graded
#   Last      last-turn input→output tokens, k/M-formatted purple
#   Diff      +added / -removed lines (off by default)     green/red
#   Ctx       context_window.used_percentage               green→yellow→red
#   Vim       .vim.mode (no-op — Copilot doesn't expose)   orange
#   Agent     .agent.name (no-op — Copilot doesn't expose) purple
#   Worktree  detected via git rev-parse --git-dir         aqua
#   Style     .output_style.name (no-op)                   purple
#   Repo      git clean/dirty + ↑ahead/↓behind upstream    aqua
#   Branch    git branch (truncated)                       yellow
#   Stash     git stash count (omitted when 0)             orange
#   Venv      basename of $VIRTUAL_ENV                     blue
#   GH        `gh auth status` account (cached 5 min)      purple
#   Ext       Copilot extensions count                     aqua
#   MCP       servers in ~/.copilot/mcp-config.json        blue
#
# Env overrides (mirror the Claude one for muscle memory):
#   COPILOT_STATUSLINE_NO_ICONS=1   drop icons, keep text labels
#   COPILOT_STATUSLINE_NO_COLOR=1   drop color (still pads + separators);
#                                   legacy COPILOT_STATUSLINE_NO_DIM=1
#                                   is honored as an alias.
#   COPILOT_STATUSLINE_PAD_TOP=N    blank lines before the line (default 8)
#   COPILOT_STATUSLINE_PAD_LEFT=N   spaces before the line     (default 1)
#   COPILOT_STATUSLINE_PAD_RIGHT=N  spaces after the line      (default 0)
#   COPILOT_STATUSLINE_SEGMENTS="…" override the segment list (and order)
#
# Quick check that all icons render in your terminal:
#     ~/.copilot/statusline.sh --test
#
# Bash 3.2-compatible (macOS default). Avoid `set -e` so one bad segment
# can never blank the whole line.

set -u

# --- Configuration ---------------------------------------------------------
# SEGMENTS controls which segments render and in what order. Override
# via `COPILOT_STATUSLINE_SEGMENTS="…"` to add/remove without editing
# the file (e.g. add `diff` for code-changes, drop `cache_pct` etc).
SEGMENTS="${COPILOT_STATUSLINE_SEGMENTS:-time model effort timer wall api premium cache_pct last_call ctx vim agent worktree style repo branch stash venv gh_account ext_count mcp_count}"
SEP=' │ '

ICONS_ON=1
[ -n "${COPILOT_STATUSLINE_NO_ICONS:-}" ] && ICONS_ON=0

# Nerd Font icons. Bash 3.2 (macOS default) does not support `\uXXXX` in
# $'...' quoting — only `\xHH` — so each codepoint is spelled as raw
# UTF-8 bytes. All glyphs are FontAwesome (U+F0xx-F2xx range), the same
# subset Claude's statusline uses, so they render in any Nerd Font
# variant including `Symbols Nerd Font Mono`. Verify with --test.
#
#   U+F252 hourglass-half  = EF 89 92   Time
#   U+F2DB microchip        = EF 8B 9B   Model
#   U+F0E4 dashboard        = EF 83 A4   Effort
#   U+F254 hourglass        = EF 89 94   Wall
#   U+F233 server           = EF 88 B3   API
#   U+F155 dollar           = EF 85 95   Req (premium request count)
#   U+F021 refresh          = EF 80 A1   Cache
#   U+F1D8 paper-plane      = EF 87 98   Last
#   U+F12A asterisk         = EF 84 AA   Diff
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
#   U+F1E6 plug             = EF 87 A6   MCP
#   U+F0AE list-task        = EF 82 AE   Ext
ICON_TIME=$'\xef\x89\x92'
ICON_MODEL=$'\xef\x8b\x9b'
ICON_EFFORT=$'\xef\x83\xa4'
ICON_RUN=$'\xef\x84\xb5'
ICON_WALL=$'\xef\x89\x94'
ICON_API=$'\xef\x88\xb3'
ICON_REQ=$'\xef\x85\x95'
ICON_CACHE=$'\xef\x80\xa1'
ICON_LAST=$'\xef\x87\x98'
ICON_DIFF=$'\xef\x84\xaa'
ICON_CTX=$'\xef\x87\x80'
ICON_VIM=$'\xef\x84\xa1'
ICON_AGENT=$'\xef\x84\xb5'
ICON_WORKTREE=$'\xef\x86\xbb'
ICON_STYLE=$'\xef\x82\xad'
ICON_REPO=$'\xef\x83\xa8'
ICON_BRANCH=$'\xef\x84\xa6'
ICON_STASH=$'\xef\x86\x87'
ICON_VENV=$'\xef\x86\xae'
ICON_GH=$'\xef\x82\x9b'
ICON_EXT=$'\xef\x82\xae'
ICON_MCP=$'\xef\x87\xa6'

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
else
  C_RESET=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
  C_PURPLE=""; C_AQUA=""; C_ORANGE=""; C_FG=""
fi

# Per-side padding emitted from inside the script. Copilot CLI's
# statusLine.padding* fields are silently ignored — only the single
# `padding` key is honored — so we apply our own spacing here for
# finer control.
PAD_TOP="${COPILOT_STATUSLINE_PAD_TOP:-8}"
PAD_LEFT="${COPILOT_STATUSLINE_PAD_LEFT:-1}"
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
f252|${ICON_TIME}|Time
f2db|${ICON_MODEL}|Model
f0e4|${ICON_EFFORT}|Effort
f135|${ICON_RUN}|Run
f254|${ICON_WALL}|Wall
f233|${ICON_API}|API
f155|${ICON_REQ}|Req
f021|${ICON_CACHE}|Cache
f1d8|${ICON_LAST}|Last
f12a|${ICON_DIFF}|Diff
f1c0|${ICON_CTX}|Context
f121|${ICON_VIM}|Vim
f135|${ICON_AGENT}|Agent
f1bb|${ICON_WORKTREE}|Worktree
f0ad|${ICON_STYLE}|Style
f0e8|${ICON_REPO}|Repo
f126|${ICON_BRANCH}|Branch
f187|${ICON_STASH}|Stash
f1ae|${ICON_VENV}|Venv
f09b|${ICON_GH}|GH
f0ae|${ICON_EXT}|Ext
f1e6|${ICON_MCP}|MCP
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
if [ -n "$session_json" ] && command -v jq >/dev/null 2>&1; then
  {
    IFS= read -r session_id    || session_id=""
    IFS= read -r session_name  || session_name=""
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
  } < <(printf '%s' "$session_json" | jq -r '
        (.session_id // ""),
        (.session_name // ""),
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
        (.context_window.context_window_size // "")
      ' 2>/dev/null)
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
  local started now mins
  started="$(cat "$f" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  mins=$(((now - started) / 60))
  [ "$mins" -gt 0 ] || return 0
  printf '%s%s%dm%s' "$(label "$C_ORANGE" "$ICON_RUN" 'Run')" "$C_FG" "$mins" "$C_RESET"
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

# Vim / Agent / Style — Copilot CLI doesn't surface these in statusLine
# JSON (no .vim.mode / .agent.name / .output_style.name fields in v1.0.44),
# so these silently no-op. Kept for visual parity with Claude — if the
# CLI exposes them in a future version, just teach the jq block above.
seg_vim()    { return 0; }
seg_agent()  { return 0; }
seg_style()  { return 0; }

# Worktree — Copilot doesn't expose .workspace.git_worktree, but we can
# detect a worktree by looking at the resolved git dir. In a linked
# worktree, git rev-parse --git-dir returns "<main>/.git/worktrees/<name>".
# Emit only the worktree name, and only when not in the main worktree
# (where the segment would otherwise appear on every repo).
seg_worktree() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local gd
  gd="$(git rev-parse --git-dir 2>/dev/null)" || return 0
  case "$gd" in
    *'/.git/worktrees/'*)
      local name="${gd##*/.git/worktrees/}"
      name="${name%%/*}"
      [ -n "$name" ] || return 0
      printf '%s%s%s%s' "$(label "$C_AQUA" "$ICON_WORKTREE" 'Worktree')" "$C_FG" "$name" "$C_RESET"
      ;;
    *) return 0 ;;
  esac
}

seg_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local state="clean" state_color="$C_GREEN"
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    state="dirty"; state_color="$C_YELLOW"
  fi
  local sync="" counts behind ahead
  if counts="$(git rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)"; then
    behind="${counts%%	*}"
    ahead="${counts##*	}"
    if [ "${ahead:-0}" -gt 0 ] 2>/dev/null; then
      sync="${sync}↑${ahead}"
    fi
    if [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
      sync="${sync}↓${behind}"
    fi
  fi
  if [ -n "$sync" ]; then
    printf '%s%s%s%s %s(%s)%s' \
      "$(label "$C_AQUA" "$ICON_REPO" 'Repo')" \
      "$state_color" "$state" "$C_RESET" \
      "$C_ORANGE" "$sync" "$C_RESET"
  else
    printf '%s%s%s%s' \
      "$(label "$C_AQUA" "$ICON_REPO" 'Repo')" \
      "$state_color" "$state" "$C_RESET"
  fi
}

seg_branch() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local br
  br="$(git symbolic-ref --short HEAD 2>/dev/null \
        || git rev-parse --short HEAD 2>/dev/null)"
  [ -n "$br" ] || return 0
  if [ ${#br} -gt 24 ]; then
    br="${br:0:23}…"
  fi
  printf '%s%s%s%s' "$(label "$C_YELLOW" "$ICON_BRANCH" 'Branch')" "$C_FG" "$br" "$C_RESET"
}

seg_stash() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local count
  count="$(git stash list 2>/dev/null | wc -l | tr -d ' ')"
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

# --- 5. Render -------------------------------------------------------------
out=""
for s in $SEGMENTS; do
  part="$("seg_$s" 2>/dev/null || true)"
  [ -n "$part" ] || continue
  if [ -n "$out" ]; then
    out="${out}${C_DIM}${SEP}${C_RESET}${part}"
  else
    out="${part}"
  fi
done

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
