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
#
# Quick check that all icons render in your terminal:
#     ~/.claude/statusline.sh --test
#
# Bash 3.2-compatible (macOS default). Avoid `set -e` so one bad segment
# can never blank the whole line.

set -u

# --- Configuration ---------------------------------------------------------
SEGMENTS="time model effort timer cost ctx vim agent worktree style git branch stash venv gh_account skills mcp"
SEP=' │ '

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
#   U+F0C2 cloud            = EF 83 82   Context
#   U+F121 code             = EF 84 A1   Vim
#   U+F135 rocket           = EF 84 B5   Agent / Run (also)
#   U+F1BB tree             = EF 86 BB   Worktree
#   U+F0AD wrench           = EF 82 AD   Style
#   U+F1D3 git              = EF 87 93   Repo
#   U+F126 code-fork        = EF 84 A6   Branch
#   U+F187 archive          = EF 86 87   Stash
#   U+F1AE flask            = EF 86 AE   Venv
#   U+F09B github           = EF 82 9B   GH
#   U+F0AE list-task        = EF 82 AE   Skills
#   U+F1E6 plug             = EF 87 A6   MCP
ICON_TIME=$'\xef\x89\x92'
ICON_MODEL=$'\xef\x8b\x9b'
ICON_EFFORT=$'\xef\x83\xa4'
ICON_RUN=$'\xef\x84\xb5'
ICON_WALL=$'\xef\x89\x94'
ICON_API=$'\xef\x88\xb3'
ICON_COST=$'\xef\x85\x95'
ICON_DIFF=$'\xef\x84\xaa'
ICON_CTX=$'\xef\x83\x82'
ICON_VIM=$'\xef\x84\xa1'
ICON_AGENT=$'\xef\x84\xb5'
ICON_WORKTREE=$'\xef\x86\xbb'
ICON_STYLE=$'\xef\x82\xad'
ICON_REPO=$'\xef\x87\x93'
ICON_BRANCH=$'\xef\x84\xa6'
ICON_STASH=$'\xef\x86\x87'
ICON_VENV=$'\xef\x86\xae'
ICON_GH=$'\xef\x82\x9b'
ICON_SKILLS=$'\xef\x82\xae'
ICON_MCP=$'\xef\x87\xa6'

# Gruvbox Dark Hard accents — match alacritty/wezterm/.tmux.conf palette.
# Use 24-bit ANSI so we don't depend on the terminal's 256-color cube.
if [ -z "${CLAUDE_STATUSLINE_NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'                                # dim for separator + label
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
f0c2|${ICON_CTX}|Ctx
f121|${ICON_VIM}|Vim
f135|${ICON_AGENT}|Agent
f1bb|${ICON_WORKTREE}|Worktree
f0ad|${ICON_STYLE}|Style
f1d3|${ICON_REPO}|Repo
f126|${ICON_BRANCH}|Branch
f187|${ICON_STASH}|Stash
f1ae|${ICON_VENV}|Venv
f09b|${ICON_GH}|GH
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
if [ -n "$session_json" ] && command -v jq >/dev/null 2>&1; then
  {
    IFS= read -r session_id    || session_id=""
    IFS= read -r model_name    || model_name=""
    IFS= read -r cwd           || cwd=""
    IFS= read -r effort_level  || effort_level=""
    IFS= read -r vim_mode      || vim_mode=""
    IFS= read -r agent_name    || agent_name=""
    IFS= read -r worktree_name || worktree_name=""
    IFS= read -r cost_usd      || cost_usd="0"
    IFS= read -r total_ms      || total_ms="0"
    IFS= read -r api_ms        || api_ms="0"
    IFS= read -r lines_added   || lines_added="0"
    IFS= read -r lines_removed || lines_removed="0"
    IFS= read -r ctx_pct       || ctx_pct=""
    IFS= read -r ctx_size      || ctx_size=""
    IFS= read -r output_style  || output_style=""
  } < <(printf '%s' "$session_json" | jq -r '
        (.session_id // ""),
        ((.model.display_name // .model.id) // ""),
        ((.workspace.current_dir // .cwd) // ""),
        (.effort.level // ""),
        (.vim.mode // ""),
        (.agent.name // ""),
        (.workspace.git_worktree // .worktree.name // ""),
        (.cost.total_cost_usd // 0),
        (.cost.total_duration_ms // 0),
        (.cost.total_api_duration_ms // 0),
        (.cost.total_lines_added // 0),
        (.cost.total_lines_removed // 0),
        (.context_window.used_percentage // ""),
        (.context_window.context_window_size // ""),
        (.output_style.name // "")
      ' 2>/dev/null)
fi

# Make $cwd's git state available to seg_git / seg_branch / seg_stash so
# we report the workspace's repo, not the (likely irrelevant) repo of
# wherever Claude Code was launched from.
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  cd "$cwd" 2>/dev/null || true
fi

# --- 3. Helpers ------------------------------------------------------------
label() {
  # "<color><icon> <Label> <reset>" — icon + label share the dim accent so
  # the value (printed by the segment after this returns) reads as the
  # bright eye-catcher.
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

# Format a token count for the Ctx segment: 200000 -> 200k, 1000000 -> 1M.
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
  printf '%s%s%s' "$(label "$C_YELLOW" "$ICON_TIME" 'Time')" "$C_FG$(date '+%H:%M:%S')" "$C_RESET"
}

seg_model() {
  [ -n "$model_name" ] || return 0
  # Trim long internal names: "claude-opus-4.7-1m-internal" -> "opus-4.7-1m"
  local short="$model_name"
  short="${short#claude-}"
  short="${short%-internal}"
  printf '%s%s%s%s' "$(label "$C_AQUA" "$ICON_MODEL" 'Model')" "$C_FG" "$short" "$C_RESET"
}

seg_effort() {
  [ -n "$effort_level" ] || return 0
  printf '%s%s%s%s' "$(label "$C_PURPLE" "$ICON_EFFORT" 'Effort')" "$C_FG" "$effort_level" "$C_RESET"
}

seg_timer() {
  [ -n "$session_id" ] || return 0
  local f="${TMPDIR:-/tmp}/claude-statusline-${USER}-${session_id}.start"
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

seg_api_time() {
  is_pos_int "$api_ms" || return 0
  printf '%s%s%s%s' "$(label "$C_BLUE" "$ICON_API" 'API')" "$C_FG" "$(fmt_ms "$api_ms")" "$C_RESET"
}

seg_cost() {
  is_pos_num "$cost_usd" || return 0
  local pretty
  pretty="$(awk -v c="$cost_usd" 'BEGIN{ printf("$%.2f", c+0) }')"
  printf '%s%s%s%s' "$(label "$C_GREEN" "$ICON_COST" 'Cost')" "$C_FG" "$pretty" "$C_RESET"
}

seg_diff() {
  # Disabled — user removed Diff from SEGMENTS. Kept here so re-enabling
  # is just a matter of adding `diff` back to the list at the top.
  return 0
}

# Ctx — context window usage. Prefer the rich `.context_window.used_percentage`
# field (Claude Code 2.x); color-grade green→yellow→red. Show absolute size
# parenthetically when known. Falls back to the old 200k+ red badge if the
# rich field is missing.
seg_ctx() {
  if [ -n "$ctx_pct" ]; then
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
    return 0
  fi
  return 0
}

seg_vim() {
  [ -n "$vim_mode" ] || return 0
  printf '%s%s%s%s' "$(label "$C_ORANGE" "$ICON_VIM" 'Vim')" "$C_FG" "$vim_mode" "$C_RESET"
}

seg_agent() {
  [ -n "$agent_name" ] || return 0
  printf '%s%s%s%s' "$(label "$C_PURPLE" "$ICON_AGENT" 'Agent')" "$C_FG" "$agent_name" "$C_RESET"
}

seg_worktree() {
  [ -n "$worktree_name" ] || return 0
  printf '%s%s%s%s' "$(label "$C_AQUA" "$ICON_WORKTREE" 'Worktree')" "$C_FG" "$worktree_name" "$C_RESET"
}

seg_style() {
  [ -n "$output_style" ] || return 0
  [ "$output_style" = "default" ] && return 0
  printf '%s%s%s%s' "$(label "$C_PURPLE" "$ICON_STYLE" 'Style')" "$C_FG" "$output_style" "$C_RESET"
}

seg_git() {
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
  printf '%s%s%d%s' "$(label "$C_AQUA" "$ICON_SKILLS" 'Skills')" "$C_FG" "$total" "$C_RESET"
}

# MCP — number of servers in ~/.claude/settings.json's .mcpServers map.
# Mirrors the copilot statusline's MCP segment but reads Claude's own
# config (which install.sh now jq-merges from the copilot mcp.json so
# the count matches what `copilot` shows).
seg_mcp() {
  local f="$HOME/.claude/settings.json"
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
