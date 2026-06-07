#!/usr/bin/env bash
# Custom status line for Claude Code (~/.claude/statusline.sh).
#
# Sibling of ~/.copilot/statusline.sh — same vibe (one Nerd-Font-iconed
# segment per data point, separated by Unicode bars), but each segment
# gets its own Gruvbox accent color instead of a flat ANSI dim wrap, so
# the line pops a little more without screaming.
#
# Claude Code feeds this script a JSON payload on stdin. Schema reference:
#   https://code.claude.com/docs/en/statusline
# Fields we read (all `// ""` / `// 0` guarded so missing field == segment
# silently skipped, never an error):
#   .session_id                              -> Run timer key
#   .transcript_path                         -> Active subagent tree source
#   .model.display_name | .model.id          -> Model
#   .workspace.current_dir                   -> cwd for git segments
#   .workspace.git_worktree                  -> Worktree (when set)
#   .effort.level                            -> Effort (when supported)
#   .vim.mode                                -> Vim (when vim mode on)
#   .agent.name                              -> Agent (when --agent set)
#   .cost.total_cost_usd                     -> Cost
#   .cost.total_duration_ms                  -> Wall (real elapsed)
#   .cost.total_api_duration_ms              -> API (model wall-time)
#   .cost.total_lines_added/removed          -> Diff (+a/-b)
#   .context_window.used_percentage          -> Ctx (color-graded)
#   .context_window.context_window_size      -> Ctx absolute total
#   .output_style.name                       -> Style (omitted if "default")
#
# Segments (in render order; each omitted when its data is unavailable):
#   Time     wall-clock HH:MM:SS                            yellow
#   Model    short model name                               aqua
#   Effort   .effort.level (low/medium/high/xhigh)          purple
#   Run      minutes since this session_id was first seen   orange
#   Wall     total_duration_ms formatted (Hh Mm / Mm / Ss)  purple
#   API      total_api_duration_ms formatted                blue
#   Cost     total_cost_usd → $1.23                         green
#   Diff     +added/-removed lines                          green/red
#   Ctx      context_window.used_percentage (color-graded)  green→yellow→red
#   Vim      .vim.mode                                      orange
#   Agent    .agent.name                                    purple
#   Worktree .workspace.git_worktree                        aqua
#   Style    output_style.name (omitted if "default")       purple
#   Repo     git clean/dirty + ↑ahead/↓behind upstream      aqua
#   Branch   git branch (truncated)                         yellow
#   Stash    git stash count (omitted when 0)               orange
#   Venv     basename of $VIRTUAL_ENV                       blue
#   GH       `gh auth status` account (cached 5 min)        purple
#
# Env overrides (mirror the copilot one for muscle memory):
#   CLAUDE_STATUSLINE_NO_ICONS=1  drop icons, keep text labels
#   CLAUDE_STATUSLINE_NO_COLOR=1  drop color (still pads + separators)
#   CLAUDE_STATUSLINE_PAD_TOP=N   blank lines before the line (default 0)
#   CLAUDE_STATUSLINE_PAD_LEFT=N  spaces before the line     (default 0)
#   CLAUDE_STATUSLINE_PAD_RIGHT=N spaces after the line      (default 0)
#   CLAUDE_STATUSLINE_MAX_SUBAGENTS=N max active subagent rows (default 8)
#   CLAUDE_STATUSLINE_SUBAGENT_ROOT=0 hide the "main" root row
#
# Quick check that all icons render in your terminal:
#     ~/.claude/statusline.sh --test
#
# Bash 3.2-compatible (macOS default). Avoid `set -e` so one bad segment
# can never blank the whole line.

set -u

# --- Configuration ---------------------------------------------------------
# Five-line layout. A literal `\n` token in SEGMENTS introduces a line
# break in the render loop. Empty/no-op segments collapse cleanly so
# auto-hiding ones (worktree, venv, stash, diff) take no space when off.
#   L1: status       — time, run timer, cost, waka today
#   L2: model        — model, effort, context
#   L3: integrations — mcp, skills, agents, style
#   L4: cwd path     — full directory path
#   L5: repo + git   — repo, diff, branch, stash, worktree
#   Bottom: separator + active subagents — root + one line per live Agent/Task
SEGMENTS="time timer cost waka \n model effort ctx \n mcp skills agent subagents style \n path \n git branch diff stash worktree"
SEP=' │ '
SUBAGENT_SEPARATOR='----------------------------------------'

ICONS_ON=1
[ -n "${CLAUDE_STATUSLINE_NO_ICONS:-}" ] && ICONS_ON=0

# Nerd Font icons. Bash 3.2 (macOS default) does not support `\uXXXX` in
# $'...' quoting — only `\xHH` — so each codepoint is spelled as raw
# UTF-8 bytes. All glyphs are FontAwesome (U+F0xx-F2xx range), the same
# subset Copilot's statusline uses, so they render in any Nerd Font
# variant including `Symbols Nerd Font Mono`. Verify with --test.
#
#   U+F252 hourglass-half  = EF 89 92   Time
#   U+F2DB microchip        = EF 8B 9B   Model
#   U+F0E4 dashboard        = EF 83 A4   Effort
#   U+F254 hourglass        = EF 89 94   Wall
#   U+F233 server           = EF 88 B3   API
#   U+F155 dollar           = EF 85 95   Cost
#   U+F12A asterisk         = EF 84 AA   Diff (stand-in for "changes")
#   U+F121 code            = EF 84 A1   Diff (angle brackets, code edits)
#   U+F07C folder-open    = EF 81 BC   Path (cwd, "currently in")
#   U+F1C0 database        = EF 87 80   Context
#   U+F121 code             = EF 84 A1   Vim
#   U+F135 rocket           = EF 84 B5   Agent / Run (also)
#   U+F1BB tree             = EF 86 BB   Worktree
#   U+F0AD wrench           = EF 82 AD   Style
#   U+F0E8 sitemap          = EF 83 A8   Repo
#   U+F126 code-fork        = EF 84 A6   Branch
#   U+F187 archive          = EF 86 87   Stash
#   U+F1AE flask            = EF 86 AE   Venv
#   U+F09B github           = EF 82 9B   GH
#   U+F0AE list-task        = EF 82 AE   Skills
#   U+F1E6 plug             = EF 87 A6   MCP
ICON_TIME=$'\xef\x80\x97'
ICON_MODEL=$'\xef\x8b\x9b'
ICON_EFFORT=$'\xef\x83\xa4'
ICON_RUN=$'\xef\x84\xb5'
ICON_WALL=$'\xef\x89\x94'
ICON_API=$'\xef\x88\xb3'
ICON_COST=$'\xef\x85\x95'
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
ICON_MCP=$'\xef\x87\xa6'
# U+F015 home            = EF 80 95   Main (root) row
ICON_SUBAGENT_ROOT=$'\xef\x80\x95'
# U+F0C0 users           = EF 83 80   Running subagents
ICON_SUBAGENT=$'\xef\x83\x80'

# Gruvbox Dark Hard accents — match alacritty/wezterm/.tmux.conf palette.
# Use 24-bit ANSI so we don't depend on the terminal's 256-color cube.
if [ -z "${CLAUDE_STATUSLINE_NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'                                # dim for separator + label
  C_RED=$'\033[38;2;251;73;52m'                   # #fb4934
  C_GREEN=$'\033[38;2;184;187;38m'                # #b8bb26
  C_YELLOW=$'\033[38;2;250;189;47m'               # #fabd2f
  C_BLUE=$'\033[38;2;131;165;152m'                # #83a598
  # Background variants for highlighted values (e.g., vim mode badge).
  # Palette + role assignment match vim-airline's gruvbox theme:
  #   NORMAL  → yellow bg
  #   INSERT  → blue bg
  #   VISUAL  → orange bg
  #   REPLACE → red bg
  # Airline pairs each with a dark foreground (#1d2021) for contrast — the
  # vim segment uses $C_BG_FG below instead of $C_FG.
  CB_RED=$'\033[48;2;204;36;29m'                   # #cc241d — gruvbox red
  CB_BLUE=$'\033[48;2;69;133;136m'                 # #458588 — gruvbox blue
  CB_YELLOW=$'\033[48;2;215;153;33m'               # #d79921 — gruvbox yellow
  CB_ORANGE=$'\033[48;2;214;93;14m'                # #d65d0e — gruvbox orange
  CB_GREEN=$'\033[48;2;152;151;26m'                # #98971a — gruvbox green (kept for back-compat)
  C_FG_DIM=$'\033[38;2;168;153;132m'               # #a89984 — gruvbox fg3
  C_BG_FG=$'\033[38;2;29;32;33m'                   # #1d2021 — gruvbox dark0_hard, for text on bright bg
  C_PURPLE=$'\033[38;2;211;134;155m'              # #d3869b
  C_AQUA=$'\033[38;2;142;192;124m'                # #8ec07c
  C_ORANGE=$'\033[38;2;254;128;25m'               # #fe8019
  C_FG=$'\033[38;2;235;219;178m'                  # #ebdbb2
else
  C_RESET=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
  C_PURPLE=""; C_AQUA=""; C_ORANGE=""; C_FG=""
  CB_RED=""; CB_BLUE=""; CB_YELLOW=""; CB_ORANGE=""; CB_GREEN=""
  C_FG_DIM=""; C_BG_FG=""
fi

PAD_TOP="${CLAUDE_STATUSLINE_PAD_TOP:-0}"
PAD_LEFT="${CLAUDE_STATUSLINE_PAD_LEFT:-0}"
PAD_RIGHT="${CLAUDE_STATUSLINE_PAD_RIGHT:-0}"

repeat() {
  local ch=$1 n=$2 out=""
  while [ "$n" -gt 0 ]; do out="${out}${ch}"; n=$((n - 1)); done
  printf '%s' "$out"
}

CACHE_DIR="${TMPDIR:-/tmp}/claude-statusline-cache-$USER"
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
f085|${ICON_MODEL}|Model
f0e7|${ICON_EFFORT}|Effort
f252|${ICON_RUN}|Run
f254|${ICON_WALL}|Wall
f233|${ICON_API}|API
f155|${ICON_COST}|Cost
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
f015|${ICON_SUBAGENT_ROOT}|Main
TEST_ICONS_EOF
  exit 0
fi

# --- 1. Read JSON payload from stdin ---------------------------------------
session_json=""
if [ ! -t 0 ]; then
  session_json="$(cat 2>/dev/null || true)"
fi

# --- 2. Parse all fields with pure-bash regex (no jq fork) -----------------
# Claude Code's payload is shallow JSON with stable keys. Pure-bash parsing
# avoids the ~22ms jq startup per render. We use targeted regex against the
# raw payload — every key we care about is unique within the payload, so we
# don't even need to descend into objects.
session_id=""
transcript_path=""
model_name=""
cwd=""
effort_level=""
vim_mode=""
agent_name=""
worktree_name=""
cost_usd="0"
total_ms="0"
api_ms="0"
lines_added="0"
lines_removed="0"
ctx_pct=""
ctx_size=""
output_style=""

# jget_str <key>  -> first matching "key": "value" string into __JV
# jget_num <key>  -> first matching "key": number/bool/null into __JV
# Both use the global $session_json haystack; both clear __JV on no-match.
__JV=""
jget_str() {
  __JV=""
  [[ "$session_json" =~ \"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && __JV="${BASH_REMATCH[1]}"
}
jget_num() {
  __JV=""
  if [[ "$session_json" =~ \"$1\"[[:space:]]*:[[:space:]]*([-0-9.]+|true|false|null) ]]; then
    [ "${BASH_REMATCH[1]}" != "null" ] && __JV="${BASH_REMATCH[1]}"
  fi
}

if [ -n "$session_json" ]; then
  jget_str "session_id";                session_id="$__JV"
  jget_str "transcript_path";           transcript_path="$__JV"
  jget_str "display_name";              model_name="$__JV"
  [ -z "$model_name" ] && { jget_str "id"; model_name="$__JV"; }
  jget_str "current_dir";               cwd="$__JV"
  [ -z "$cwd" ] && { jget_str "cwd";   cwd="$__JV"; }
  jget_str "level";                     effort_level="$__JV"
  jget_str "mode";                      vim_mode="$__JV"
  # agent.name and worktree.name share the key "name" — disambiguate by
  # presence of agent. block first.
  if [[ "$session_json" == *'"agent"'* ]]; then
    jget_str "name";                    agent_name="$__JV"
  fi
  jget_str "git_worktree";              worktree_name="$__JV"
  jget_num "total_cost_usd";            cost_usd="${__JV:-0}"
  jget_num "total_duration_ms";         total_ms="${__JV:-0}"
  jget_num "total_api_duration_ms";     api_ms="${__JV:-0}"
  jget_num "total_lines_added";         lines_added="${__JV:-0}"
  jget_num "total_lines_removed";       lines_removed="${__JV:-0}"
  jget_num "used_percentage";           ctx_pct="$__JV"
  jget_num "context_window_size";       ctx_size="$__JV"
  # output_style.name — only read if no agent (which would have stolen the
  # "name" match above). Output style is rarely set, so this is best-effort.
  if [[ "$session_json" == *'"output_style"'* ]] && [ -z "$agent_name" ]; then
    jget_str "name";                    output_style="$__JV"
  fi
fi

# Make $cwd's git state available to seg_git / seg_branch / seg_stash so
# we report the workspace's repo, not the (likely irrelevant) repo of
# wherever Claude Code was launched from.
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  cd "$cwd" 2>/dev/null || true
fi

# --- 3. Helpers ------------------------------------------------------------
label() {
  # "<color><icon> <Label> <reset>" — written into $__LBL via printf -v so
  # callers can splice it without a `$(label ...)` subshell fork.
  local color="$1" icon="$2" text="$3"
  if [ "$ICONS_ON" = "1" ]; then
    printf -v __LBL '%s%s %s%s ' "$color" "$icon" "$text" "$C_RESET"
  else
    printf -v __LBL '%s%s%s ' "$color" "$text" "$C_RESET"
  fi
}

is_pos_int() {
  case "${1:-}" in
    '' | *[!0-9]*) return 1 ;;
    0) return 1 ;;
    *) return 0 ;;
  esac
}

is_pos_num() {
  # Accepts ints AND decimals (cost_usd is a float).
  case "${1:-}" in
    '' | 0 | 0.0 | 0.00) return 1 ;;
    *[!0-9.]*) return 1 ;;
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

# Format a duration in seconds as "Nd Hh Mm" / "Nh Mm" / "Nm" — the unit
# of the largest non-zero component plus the next one down. Used by Run
# and WakaTime so the two timing segments read consistently for any
# duration (multi-day WakaTime totals included).
fmt_dhm() {
  local s=${1:-0}
  if [ "$s" -ge 86400 ]; then
    printf '%dd%dh%dm' $((s / 86400)) $(((s % 86400) / 3600)) $(((s % 3600) / 60))
  elif [ "$s" -ge 3600 ]; then
    printf '%dh%dm' $((s / 3600)) $(((s % 3600) / 60))
  elif [ "$s" -ge 60 ]; then
    printf '%dm' $((s / 60))
  else
    printf '%ds' "$s"
  fi
}

# Format a token count for the Ctx segment: 200000 -> 200k, 1000000 -> 1M.
# Pure-bash arithmetic; no awk fork.
fmt_tokens() {
  local n=${1:-0}
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    # Integer math: e.g. 1500000 -> "1.5M". Compute tenths separately.
    local whole=$(( n / 1000000 ))
    local tenths=$(( (n % 1000000) / 100000 ))
    printf '%d.%dM' "$whole" "$tenths"
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    printf '%dk' $(( n / 1000 ))
  else
    printf '%d' "$n"
  fi
}

# --- 4. Segment functions --------------------------------------------------
# Each seg_* writes its rendered text into the global $__SEG via `printf -v`.
# Returning early (no output) leaves __SEG untouched — the render loop reads
# it and skips empty values. This avoids one `$(...)` subshell fork per
# segment per render.
seg_time() {
  label "$C_YELLOW" "$ICON_TIME" 'Time'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$(date '+%H:%M:%S')" "$C_RESET"
}

seg_model() {
  [ -n "$model_name" ] || return 0
  # Trim long internal names: "claude-opus-4.7-1m-internal" -> "opus-4.7-1m"
  local short="$model_name"
  short="${short#claude-}"
  short="${short%-internal}"
  label "$C_AQUA" "$ICON_MODEL" 'Model'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$short" "$C_RESET"
}

seg_effort() {
  # Claude Code's statusline JSON doesn't expose reasoning effort (no
  # `.effort.level` in the documented schema as of v2.1.x), so $effort_level
  # parsed from the payload is virtually always empty. Fall back to the
  # MODEL_REASONING_EFFORT env var — Claude Code exports settings.json's
  # `env` block to the statusline subprocess, so a user who set
  # MODEL_REASONING_EFFORT=xhigh in settings.json gets it surfaced here.
  # Mirrors how the copilot statusline derives effort from the "(xhigh)"
  # suffix in the model name; Claude's model names don't carry one.
  local lvl="${effort_level:-${MODEL_REASONING_EFFORT:-}}"
  [ -n "$lvl" ] || return 0
  label "$C_PURPLE" "$ICON_EFFORT" 'Effort'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$lvl" "$C_RESET"
}

seg_timer() {
  [ -n "$session_id" ] || return 0
  local f="${TMPDIR:-/tmp}/claude-statusline-${USER}-${session_id}.start"
  if [ ! -f "$f" ]; then
    date +%s >"$f" 2>/dev/null || true
  fi
  [ -f "$f" ] || return 0
  local started now elapsed
  read -r started <"$f" 2>/dev/null || started=0
  now="$(date +%s)"
  elapsed=$(( now - started ))
  [ "$elapsed" -ge 60 ] || return 0
  label "$C_ORANGE" "$ICON_RUN" 'Run'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$(fmt_dhm "$elapsed")" "$C_RESET"
}

seg_wall() {
  is_pos_int "$total_ms" || return 0
  label "$C_PURPLE" "$ICON_WALL" 'Wall'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$(fmt_ms "$total_ms")" "$C_RESET"
}

seg_api_time() {
  is_pos_int "$api_ms" || return 0
  label "$C_BLUE" "$ICON_API" 'API'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$(fmt_ms "$api_ms")" "$C_RESET"
}

seg_cost() {
  is_pos_num "$cost_usd" || return 0
  local pretty
  # bash printf handles floats — saves an awk fork.
  printf -v pretty '$%.2f' "$cost_usd"
  label "$C_GREEN" "$ICON_COST" 'Cost'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$pretty" "$C_RESET"
}

seg_diff() {
  # +added/-removed line counts from the JSON payload. Auto-hides when
  # the session hasn't touched any code yet (both counts zero).
  local a="${lines_added:-0}" r="${lines_removed:-0}"
  is_pos_int "$a" || is_pos_int "$r" || return 0
  label "$C_GREEN" "$ICON_DIFF" 'Diff'
  printf -v __SEG '%s%s+%d%s%s/-%d%s' "$__LBL" "$C_GREEN" "$a" "$C_RESET" "$C_RED" "$r" "$C_RESET"
}

# Path — full cwd as its own line. Replace $HOME with ~ for brevity;
# this is exactly how Claude Code normally writes it in the welcome
# banner. Auto-hides if cwd is empty (paranoia — JSON should always
# have it).
seg_path() {
  [ -n "$cwd" ] || return 0
  local p="$cwd"
  case "$p" in
    "$HOME") p="~" ;;
    "$HOME"/*) p="~${p#$HOME}" ;;
  esac
  label "$C_BLUE" "$ICON_PATH" 'Path'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$p" "$C_RESET"
}

# Ctx — context window usage. Prefer the rich `.context_window.used_percentage`
# field (Claude Code 2.x); color-grade green→yellow→red. Show absolute size
# parenthetically when known. Falls back to the old 200k+ red badge if the
# rich field is missing.
seg_ctx() {
  [ -n "$ctx_pct" ] || return 0
  # Truncate to int by stripping the decimal portion — saves an awk fork.
  # ctx_pct comes in as a float like "8.234" or "12"; we want "8" / "12".
  local pct_int="${ctx_pct%%.*}"
  pct_int="${pct_int:-0}"
  local color="$C_GREEN"
  if [ "$pct_int" -ge 80 ] 2>/dev/null; then
    color="$C_RED"
  elif [ "$pct_int" -ge 50 ] 2>/dev/null; then
    color="$C_YELLOW"
  fi
  local body
  if [ -n "$ctx_size" ] && [ "$ctx_size" != "null" ]; then
    body="${color}${pct_int}%${C_RESET}${C_DIM}/$(fmt_tokens "$ctx_size")${C_RESET}"
  else
    body="${color}${pct_int}%${C_RESET}"
  fi
  label "$C_AQUA" "$ICON_CTX" 'Context'
  printf -v __SEG '%s%s' "$__LBL" "$body"
}

seg_vim() {
  [ -n "$vim_mode" ] || return 0
  # vim-airline gruvbox palette:
  #   NORMAL  → yellow / dark fg
  #   INSERT  → blue   / dark fg
  #   VISUAL  → orange / dark fg
  #   REPLACE → red    / dark fg
  # Dark foreground on each bright bg follows airline's high-contrast style.
  local mode_bg="$CB_YELLOW"
  case "$vim_mode" in
    [Ii][Nn][Ss][Ee][Rr][Tt]*)     mode_bg="$CB_BLUE"   ;;
    [Vv][Ii][Ss][Uu][Aa][Ll]*)     mode_bg="$CB_ORANGE" ;;
    [Nn][Oo][Rr][Mm][Aa][Ll]*)     mode_bg="$CB_YELLOW" ;;
    [Rr][Ee][Pp][Ll][Aa][Cc][Ee]*) mode_bg="$CB_RED"    ;;
  esac
  label "$C_RED" "$ICON_VIM" 'Vim'
  printf -v __SEG '%s%s%s %s %s' "$__LBL" "$mode_bg" "$C_BG_FG" "$vim_mode" "$C_RESET"
}

# Agent — count *.md agent definitions in user + project scope. Claude
# Code loads agents from ~/.claude/agents/<name>.md (user) and
# <cwd>/.claude/agents/<name>.md (project). Mirrors seg_skills' shape.
# Note: this counts AVAILABLE agents (definitions on disk), not currently
# running ones — the statusline JSON doesn't expose a runtime list.
seg_agent() {
  local total=0 d count
  for d in "${HOME}/.claude/agents" "${PWD}/.claude/agents"; do
    [ -d "$d" ] || continue
    count="$(find "$d" -mindepth 1 -maxdepth 1 -type f -name '*.md' ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')"
    total=$((total + count))
  done
  is_pos_int "$total" || return 0
  label "$C_PURPLE" "$ICON_AGENT" 'Agents'
  printf -v __SEG '%s%s%d%s' "$__LBL" "$C_FG" "$total" "$C_RESET"
}

seg_worktree() {
  [ -n "$worktree_name" ] || return 0
  label "$C_AQUA" "$ICON_WORKTREE" 'Worktree'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$worktree_name" "$C_RESET"
}

seg_style() {
  [ -n "$output_style" ] || return 0
  [ "$output_style" = "default" ] && return 0
  label "$C_PURPLE" "$ICON_STYLE" 'Style'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$output_style" "$C_RESET"
}

# --- Pre-compute shared git state ------------------------------------------
# git/branch/stash all need the same plumbing. Calling git on every render
# costs ~50ms even after consolidation — and git state almost never changes
# between keystrokes. Cache the computed values per-cwd with a 5-second TTL,
# so vim-mode-driven re-renders (which dominate after pressing Esc) skip
# git entirely on the hot path.
GIT_INSIDE=0
GIT_DIRTY=""
GIT_BRANCH=""
GIT_SYNC=""
GIT_STASH_COUNT=0

# Per-cwd cache key. Keep it short — just the cwd hash, since we don't
# invalidate across branches; that's fine because the TTL caps staleness.
__cwd_hash="$(printf '%s' "${PWD}" | cksum | awk '{print $1}')"
__git_cache="$CACHE_DIR/git-${__cwd_hash}"
__use_cache=0
if [ -f "$__git_cache" ]; then
  __mtime="$(stat -f %m "$__git_cache" 2>/dev/null || stat -c %Y "$__git_cache" 2>/dev/null || echo 0)"
  __age=$(( $(date +%s) - __mtime ))
  if [ "$__age" -lt 5 ]; then
    __use_cache=1
    # shellcheck disable=SC1090
    . "$__git_cache" 2>/dev/null || __use_cache=0
  fi
fi

if [ "$__use_cache" = 0 ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_INSIDE=1
  # status + branch + upstream sync in one shot via `git status --porcelain=v2 --branch`.
  __gs="$(git status --porcelain=v2 --branch 2>/dev/null)"
  __dirty_lines="$(printf '%s\n' "$__gs" | grep -cv '^#')"
  [ "$__dirty_lines" -gt 0 ] 2>/dev/null && GIT_DIRTY=1
  GIT_BRANCH="$(printf '%s\n' "$__gs" | awk '/^# branch.head /{print $3; exit}')"
  __ab="$(printf '%s\n' "$__gs" | awk '/^# branch.ab /{print $3" "$4; exit}')"
  if [ -n "$__ab" ]; then
    __ahead="${__ab%% *}"; __behind="${__ab##* }"
    __ahead="${__ahead#+}"; __behind="${__behind#-}"
    [ "${__ahead:-0}" -gt 0 ] 2>/dev/null && GIT_SYNC="${GIT_SYNC}↑${__ahead}"
    [ "${__behind:-0}" -gt 0 ] 2>/dev/null && GIT_SYNC="${GIT_SYNC}↓${__behind}"
  fi
  if [ "$GIT_BRANCH" = "(detached)" ] || [ -z "$GIT_BRANCH" ]; then
    GIT_BRANCH="$(git rev-parse --short HEAD 2>/dev/null)"
  fi
  GIT_STASH_COUNT="$(git stash list 2>/dev/null | wc -l | tr -d ' ')"
  # Persist for the next renders within the TTL window.
  {
    printf 'GIT_INSIDE=%s\n' "$GIT_INSIDE"
    printf 'GIT_DIRTY=%q\n' "$GIT_DIRTY"
    printf 'GIT_BRANCH=%q\n' "$GIT_BRANCH"
    printf 'GIT_SYNC=%q\n' "$GIT_SYNC"
    printf 'GIT_STASH_COUNT=%s\n' "$GIT_STASH_COUNT"
  } >"$__git_cache" 2>/dev/null || true
fi

seg_git() {
  [ "$GIT_INSIDE" = 1 ] || return 0
  local state="clean" state_color="$C_GREEN"
  if [ -n "$GIT_DIRTY" ]; then
    state="dirty"; state_color="$C_YELLOW"
  fi
  label "$C_AQUA" "$ICON_REPO" 'Repo'
  if [ -n "$GIT_SYNC" ]; then
    printf -v __SEG '%s%s%s%s %s(%s)%s' \
      "$__LBL" "$state_color" "$state" "$C_RESET" \
      "$C_ORANGE" "$GIT_SYNC" "$C_RESET"
  else
    printf -v __SEG '%s%s%s%s' "$__LBL" "$state_color" "$state" "$C_RESET"
  fi
}

seg_branch() {
  [ "$GIT_INSIDE" = 1 ] || return 0
  local br="$GIT_BRANCH"
  [ -n "$br" ] || return 0
  if [ ${#br} -gt 24 ]; then
    br="${br:0:23}…"
  fi
  label "$C_YELLOW" "$ICON_BRANCH" 'Branch'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$br" "$C_RESET"
}

seg_stash() {
  [ "$GIT_INSIDE" = 1 ] || return 0
  is_pos_int "$GIT_STASH_COUNT" || return 0
  label "$C_ORANGE" "$ICON_STASH" 'Stash'
  printf -v __SEG '%s%s%d%s' "$__LBL" "$C_FG" "$GIT_STASH_COUNT" "$C_RESET"
}

seg_venv() {
  [ -n "${VIRTUAL_ENV:-}" ] || return 0
  label "$C_BLUE" "$ICON_VENV" 'Venv'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "${VIRTUAL_ENV##*/}" "$C_RESET"
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
    read -r account <"$cf" 2>/dev/null || account=""
  else
    account="$(gh auth status 2>&1 | awk '
      /Logged in to github\.com account /{
        for (i=1; i<=NF; i++) if ($i=="account") { print $(i+1); exit }
      }' | head -1)"
    printf '%s' "$account" >"$cf" 2>/dev/null || true
  fi
  [ -n "$account" ] || return 0
  label "$C_PURPLE" "$ICON_GH" 'GH'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$account" "$C_RESET"
}

# WakaTime — today's coding time as recorded by WakaTime. The `wakatime-cli
# --today` call hits the network internally (~250ms), way too slow for
# every render. Cache for 5 minutes; on a miss, kick off a background
# refresh and serve the previous value (returns nothing the first time
# until the bg fetch lands). Skipped if wakatime-cli isn't installed.
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
    # Stale-lock recovery: if the lockdir is older than 60s the previous
    # bg fetch died (network hang, SIGKILL on logout, OOM) without
    # cleanup. Without this guard the dir persists forever, no further
    # refresh ever runs, and the segment silently freezes on the last
    # cached value — invisible failure mode. (Reviewer flagged this.)
    if [ -d "$lock" ]; then
      local lock_mtime
      lock_mtime="$(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || echo 0)"
      [ $((now - lock_mtime)) -gt 60 ] && rmdir "$lock" 2>/dev/null
    fi
    # Background refresh — don't block the render. mkdir-based lock so
    # multiple concurrent statusline runs don't all spawn fetchers. The
    # subshell's EXIT trap guarantees the lock is removed even if the
    # fetch hangs and we get killed mid-call.
    if mkdir "$lock" 2>/dev/null; then
      (
        trap 'rmdir "'"$lock"'" 2>/dev/null' EXIT
        "$wt" --today >"$cf.tmp" 2>/dev/null \
          && mv "$cf.tmp" "$cf" 2>/dev/null
      ) &
    fi
    # Serve stale value while the bg refresh runs (avoids flicker).
    [ -f "$cf" ] && read -r val <"$cf" 2>/dev/null
  fi
  [ -n "$val" ] || return 0
  # wakatime-cli prints variants: "2 hrs 9 mins" / "1 hr 5 mins" /
  # "47 mins" / "1 min" / "8 secs". Convert to total seconds, then
  # render via fmt_dhm so multi-day totals format as "Nd Hh Mm" / "Nh Mm"
  # consistently with seg_timer.
  local hrs=0 mins=0 secs=0 total
  case "$val" in *' hr'*) hrs="${val%% hr*}" ;; esac
  local rest="$val"
  case "$rest" in *' hr'*) rest="${rest#*hrs }"; rest="${rest#*hr }" ;; esac
  case "$rest" in *' min'*) mins="${rest%% min*}" ;; esac
  rest="$val"
  case "$rest" in *' min'*) rest="${rest#*mins }"; rest="${rest#*min }" ;; esac
  case "$rest" in *' sec'*) secs="${rest%% sec*}" ;; esac
  case "$hrs" in '' | *[!0-9]*) hrs=0 ;; esac
  case "$mins" in '' | *[!0-9]*) mins=0 ;; esac
  case "$secs" in '' | *[!0-9]*) secs=0 ;; esac
  total=$(( hrs * 3600 + mins * 60 + secs ))
  [ "$total" -ge 60 ] || return 0
  label "$C_AQUA" "$ICON_WAKA" 'WakaTime'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$(fmt_dhm "$total")" "$C_RESET"
}

# Skills — count user-scope + workspace-scope skill bundles. Claude Code
# loads skills from ~/.claude/skills/<name>/SKILL.md (user) and
# <cwd>/.claude/skills/<name>/SKILL.md (project). The statusline JSON
# doesn't expose a count, so we compute it ourselves. Hidden dirs (the
# .git inside .claude/skills, dotfiles) are excluded.
seg_skills() {
  local total=0 d count
  for d in "${HOME}/.claude/skills" "${PWD}/.claude/skills"; do
    [ -d "$d" ] || continue
    count="$(find "$d" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')"
    total=$((total + count))
  done
  is_pos_int "$total" || return 0
  label "$C_AQUA" "$ICON_SKILLS" 'Skills'
  printf -v __SEG '%s%s%d%s' "$__LBL" "$C_FG" "$total" "$C_RESET"
}

# MCP — number of servers in ~/.claude.json's .mcpServers map. Claude
# Code reads MCP servers from ~/.claude.json (top-level), NOT from
# settings.json. install.sh seeds this map from copilot's mcp.json so
# the count matches what `copilot` shows.
#
# Counted via grep of the mcpServers block (no jq fork). The ~/.claude.json
# format is stable JSON, one server per "name": { ... } entry inside the
# mcpServers object; we count those object-opening braces.
seg_subagents() {
  # Count currently-running subagents.
  #
  # Primary source: per-session counter file maintained by the Claude
  # Code hooks at ~/.claude/hooks/subagent-counter.sh (wired up in
  # ~/.claude/settings.json under PreToolUse/PostToolUse/SubagentStop).
  # The hook does +1 on Task start and -1 on Task stop, so reading the
  # counter is one `read` from a tiny file — no jq, no tail, no scan.
  #
  # Fallback: if the counter file doesn't exist (e.g. session started
  # before the hooks were installed, or hooks somehow disabled), scan
  # the transcript with the signature-cached approach below.
  local n=0 src="hook"
  if [ -n "${session_id:-}" ]; then
    local hf="${TMPDIR:-/tmp}/claude-subagents-${USER:-default}/${session_id}"
    if [ -f "$hf" ]; then
      read -r n <"$hf" 2>/dev/null || n=0
      case "$n" in '' | *[!0-9]*) n=0 ;; esac
    else
      src="scan"
    fi
  else
    src="scan"
  fi

  if [ "$src" = "scan" ] && [ -n "${transcript_path:-}" ] && [ -f "$transcript_path" ] \
     && command -v jq >/dev/null 2>&1; then
    # Signature-cached transcript scan (fallback only).
    local key cf sig cached_sig cached_n tail_lines
    key="$(printf '%s' "$transcript_path" | cksum | awk '{print $1}')"
    cf="$CACHE_DIR/subagents-count-${key}"
    sig="$(statusline_file_sig "$transcript_path")"
    cached_sig=""; cached_n=""
    if [ -f "$cf" ]; then
      { IFS= read -r cached_sig; IFS= read -r cached_n; } <"$cf" 2>/dev/null
    fi
    if [ -n "$cached_sig" ] && [ "$cached_sig" = "$sig" ]; then
      case "$cached_n" in
        '' | *[!0-9]*) n=0 ;;
        *) n="$cached_n" ;;
      esac
    else
      tail_lines="$(statusline_int_or_default "${CLAUDE_STATUSLINE_SUBAGENT_TAIL:-${STATUSLINE_SUBAGENT_TAIL:-4000}}" 4000)"
      n="$(tail -n "$tail_lines" "$transcript_path" 2>/dev/null | jq -n -r '
        def content_items: if (.message.content? | type) == "array" then .message.content else [] end;
        def text_content: if (.message.content? | type) == "string" then .message.content else "" end;
        def async_handle($c): ($c.content | tostring | contains("Async agent launched successfully"));
        reduce inputs as $o ({agents:{}};
          ($o | text_content) as $txt
          | (if ($txt | contains("<task-notification>") and contains("<tool-use-id>")) then
              ($txt | capture("<tool-use-id>(?<id>[^<]+)</tool-use-id>")? // {}) as $m
              | if (($m.id // "") != "" and ($txt | test("<status>(completed|failed|cancelled)</status>"))) then
                  if .agents[$m.id] then .agents[$m.id].done = true else . end
                else . end
            else . end)
          | reduce ($o | content_items[]) as $c (.;
              if ($c.type == "tool_use" and ($c.name == "Agent" or $c.name == "Task")) then
                ($c.id // "") as $id
                | if $id == "" then . else
                    .agents[$id] = {background: ($c.input.run_in_background // false), done: false}
                  end
              elif ($c.type == "tool_result") then
                ($c.tool_use_id // "") as $id
                | if ($id != "" and .agents[$id]) then
                    if (.agents[$id].background and async_handle($c)) then .
                    else .agents[$id].done = true end
                  else . end
              else . end))
        | [ .agents | to_entries[] | select(.value.done | not) ] | length
      ' 2>/dev/null)"
      case "$n" in '' | *[!0-9]*) n=0 ;; esac
      { printf '%s\n%s\n' "$sig" "$n"; } >"$cf" 2>/dev/null || true
    fi
  fi
  label "$C_PURPLE" "$ICON_SUBAGENT" 'Subagents'
  printf -v __SEG '%s%s%d%s' "$__LBL" "$C_FG" "$n" "$C_RESET"
}

seg_mcp() {
  local f="$HOME/.claude.json"
  [ -f "$f" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  # Cache by file mtime to avoid re-reading + re-parsing the (potentially
  # large) ~/.claude.json on every render. jq is required by install.sh
  # for the MCP merge anyway, so it's always available — using it here
  # too keeps claude/statusline.sh and copilot/statusline.sh aligned
  # (was awk-based brace-counting; copilot uses jq; reviewer flagged the
  # drift). jq also handles MCP server names containing `}` in string
  # values correctly, which the awk parser would miscount.
  local cf="$CACHE_DIR/mcp_count"
  local fmtime cached_mtime cached_count="" count
  fmtime="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
  if [ -f "$cf" ]; then
    IFS='|' read -r cached_mtime cached_count <"$cf" 2>/dev/null
    if [ "$cached_mtime" = "$fmtime" ]; then
      count="$cached_count"
    fi
  fi
  if [ -z "$count" ]; then
    count="$(jq -r '(.mcpServers // {}) | length' "$f" 2>/dev/null)"
    [ -z "$count" ] && count=0
    printf '%s|%s\n' "$fmtime" "$count" >"$cf" 2>/dev/null || true
  fi
  is_pos_int "$count" || return 0
  label "$C_BLUE" "$ICON_MCP" 'MCP'
  printf -v __SEG '%s%s%d%s' "$__LBL" "$C_FG" "$count" "$C_RESET"
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
  local rows="$1" out="" name purpose root
  [ -n "$rows" ] || return 0

  root="${STATUSLINE_SUBAGENT_ROOT:-1}"
  root="${CLAUDE_STATUSLINE_SUBAGENT_ROOT:-$root}"
  case "$root" in
    0 | false | FALSE | no | NO) root=0 ;;
    *) root=1 ;;
  esac
  if [ "$root" = 1 ]; then
    out="${C_GREEN}${ICON_SUBAGENT_ROOT}${C_RESET} ${C_FG}main${C_RESET}"
  fi

  while IFS=$'\t' read -r name purpose; do
    [ -n "$name$purpose" ] || continue
    [ -n "$out" ] && out="${out}"$'\n'
    [ -n "$name" ] || name="agent"
    out="${out}${C_YELLOW}○${C_RESET} ${C_FG}${name}${C_RESET}"
    [ -n "$purpose" ] && out="${out}  ${C_FG_DIM}${purpose}${C_RESET}"
  done <<EOF
$rows
EOF
  printf '%s' "$out"
}

render_subagents() {
  [ -n "$transcript_path" ] || return 0
  [ -f "$transcript_path" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local max tail_lines key cf sig cached_sig rows block
  max="$(statusline_int_or_default "${CLAUDE_STATUSLINE_MAX_SUBAGENTS:-${STATUSLINE_MAX_SUBAGENTS:-8}}" 8)"
  [ "$max" -gt 0 ] 2>/dev/null || return 0
  tail_lines="$(statusline_int_or_default "${CLAUDE_STATUSLINE_SUBAGENT_TAIL:-${STATUSLINE_SUBAGENT_TAIL:-4000}}" 4000)"
  key="$(printf '%s' "$transcript_path" | cksum | awk '{print $1}')"
  cf="$CACHE_DIR/subagents-${key}"
  sig="$(statusline_file_sig "$transcript_path")"

  if [ -f "$cf" ]; then
    IFS= read -r cached_sig <"$cf" 2>/dev/null || cached_sig=""
    if [ "$cached_sig" = "$sig" ]; then
      sed '1d' "$cf" 2>/dev/null || true
      return 0
    fi
  fi

  rows="$(tail -n "$tail_lines" "$transcript_path" 2>/dev/null | jq -r --argjson max "$max" '
    def clean:
      tostring
      | gsub("[\r\n\t]+"; " ")
      | gsub("  +"; " ")
      | sub("^ +"; "")
      | sub(" +$"; "")
      | .[0:140];
    def content_items:
      if (.message.content? | type) == "array" then .message.content else [] end;
    def text_content:
      if (.message.content? | type) == "string" then .message.content else "" end;
    def async_handle($c):
      ($c.content | tostring | contains("Async agent launched successfully"));

    reduce inputs as $o ({agents:{}, order:[]};
      ($o | text_content) as $txt
      | (if ($txt | contains("<task-notification>") and contains("<tool-use-id>")) then
          ($txt | capture("<tool-use-id>(?<id>[^<]+)</tool-use-id>")? // {}) as $m
          | if (($m.id // "") != "" and ($txt | test("<status>(completed|failed|cancelled)</status>"))) then
              if .agents[$m.id] then .agents[$m.id].done = true else . end
            else . end
        else . end)
      | reduce ($o | content_items[]) as $c (.;
          if ($c.type == "tool_use" and ($c.name == "Agent" or $c.name == "Task")) then
            ($c.id // "") as $id
            | if $id == "" then .
              else
                .agents[$id] = {
                  name: (($c.input.subagent_type // $c.input.agent_type // $c.input.name // "agent") | clean),
                  purpose: (($c.input.description // $c.input.subject // $c.input.prompt // "") | clean),
                  background: ($c.input.run_in_background // false),
                  done: false
                }
                | .order += [$id]
              end
          elif ($c.type == "tool_result") then
            ($c.tool_use_id // "") as $id
            | if ($id != "" and .agents[$id]) then
                if (.agents[$id].background and async_handle($c)) then .
                else .agents[$id].done = true end
              else . end
          else . end
        )
    )
    | [ .order[] as $id | .agents[$id] | select(. != null and (.done | not)) ]
    | .[:$max][]
    | [.name, .purpose]
    | @tsv
  ' 2>/dev/null)"
  block="$(format_subagent_rows "$rows")"
  { printf '%s\n' "$sig"; printf '%s' "$block"; } >"$cf" 2>/dev/null || true
  printf '%s' "$block"
}

# --- 5. Render -------------------------------------------------------------
# Each seg_* writes its output to the global $__SEG via `printf -v` instead
# of stdout. We can then concatenate without forking a `$(...)` subshell
# per segment — saves ~2ms × 16 segments ≈ 30ms on every render.
#
# A literal `\n` token in $SEGMENTS introduces a line break: segments
# before it form line 1, segments after it form line 2, etc. Empty
# segments don't trigger a separator, so a line break followed by all-empty
# segments collapses cleanly.
out=""
line_started=0
for s in $SEGMENTS; do
  if [ "$s" = '\n' ]; then
    out="${out}"$'\n'
    line_started=0
    continue
  fi
  __SEG=""
  "seg_$s" 2>/dev/null || true
  [ -n "$__SEG" ] || continue
  if [ "$line_started" = 1 ]; then
    out="${out}${C_DIM}${SEP}${C_RESET}${__SEG}"
  else
    out="${out}${__SEG}"
    line_started=1
  fi
done

__SUBAGENTS="$(render_subagents 2>/dev/null || true)"
[ -n "$__SUBAGENTS" ] && out="${out}"$'\n'"${C_DIM}${SUBAGENT_SEPARATOR}${C_RESET}"$'\n'"${__SUBAGENTS}"

i=0
while [ "$i" -lt "$PAD_TOP" ]; do
  printf '\n'
  i=$((i + 1))
done

# `\r` (carriage return) snaps the cursor to column 1 before painting,
# which matters because Claude Code's renderer sometimes pre-positions
# us a cell or two in. Note: Claude Code's statusline panel itself has
# a 1-cell border that no script-side ANSI can defeat — that border is
# UI chrome, not padding.
printf '\r%s%s%s' \
  "$(repeat ' ' "$PAD_LEFT")" \
  "$out" \
  "$(repeat ' ' "$PAD_RIGHT")"
