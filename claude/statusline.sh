#!/usr/bin/env bash
# Custom status line for Claude Code (~/.claude/statusline.sh).
#
# Sibling of ~/.copilot/statusline.sh — same vibe (one Nerd-Font-iconed
# line per segment, separated by Unicode bars), but each segment gets its
# own Gruvbox accent color instead of a flat ANSI dim wrap, so the line
# pops a little more without screaming. Whole line is still bracketed in
# bg=bg0 so it sits clean on top of any terminal background.
#
# Claude Code feeds this script a JSON payload on stdin. Documented fields
# we read:
#   .session_id                        -> stable per session (Run timer key)
#   .model.display_name | .model.id    -> shown in the Model segment
#   .workspace.current_dir             -> Repo + Branch context
#   .cost.total_cost_usd               -> Cost segment
#   .cost.total_duration_ms            -> Wall (real elapsed)
#   .cost.total_api_duration_ms        -> API (model wall-time)
#   .cost.total_lines_added/removed    -> Diff segment (+a/-b)
#   .exceeds_200k_tokens               -> Ctx warning badge
#   .output_style.name                 -> Style segment (omitted if "default")
# Everything is `// ""` / `// 0` guarded — older/newer Claude Code releases
# may add/drop fields; missing field == segment skipped, never error.
#
# Segments (in render order; each omitted when its data is unavailable):
#   Time     wall-clock HH:MM:SS                            (yellow)
#   Model    short model name                               (aqua)
#   Run      minutes since this session_id was first seen   (orange)
#   Wall     total_duration_ms formatted (Hh Mm / Mm / Ss)  (purple)
#   API      total_api_duration_ms formatted                (blue)
#   Cost     total_cost_usd → $1.23                         (green)
#   Diff     +added/-removed lines                          (green/red)
#   Ctx      "200k+" badge when exceeds_200k_tokens is true (red)
#   Style    output_style.name (omitted if "default"/empty) (purple)
#   Repo     git clean/dirty + ↑ahead/↓behind upstream      (aqua)
#   Branch   git branch (truncated)                         (yellow)
#   Stash    git stash count (omitted when 0)               (orange)
#   Venv     basename of $VIRTUAL_ENV                       (blue)
#   GH       `gh auth status` account (cached 5 min)        (purple)
#
# Env overrides (mirror the copilot one for muscle memory):
#   CLAUDE_STATUSLINE_NO_ICONS=1  drop icons, keep text labels
#   CLAUDE_STATUSLINE_NO_COLOR=1  drop color (still pads + separators)
#   CLAUDE_STATUSLINE_PAD_TOP=N   blank lines before the line (default 0)
#   CLAUDE_STATUSLINE_PAD_LEFT=N  spaces before the line     (default 1)
#   CLAUDE_STATUSLINE_PAD_RIGHT=N spaces after the line      (default 0)
#
# Quick check that all icons render in your terminal:
#     ~/.claude/statusline.sh --test
#
# Bash 3.2-compatible (macOS default). Avoid `set -e` so one bad segment
# can never blank the whole line.

set -u

# --- Configuration ---------------------------------------------------------
SEGMENTS="time model timer wall api_time cost diff ctx style git branch stash venv gh_account"
SEP=' │ '

ICONS_ON=1
[ -n "${CLAUDE_STATUSLINE_NO_ICONS:-}" ] && ICONS_ON=0

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
PAD_LEFT="${CLAUDE_STATUSLINE_PAD_LEFT:-1}"
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
  done <<'TEST_ICONS_EOF'
f017||Time
f085||Model
f252||Run
f520||Wall
f233||API
f155||Cost
f440||Diff
f071||Ctx
f0ad||Style
f1d3||Repo
e725||Branch
f187||Stash
e73c||Venv
f09b||GH
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
cost_usd="0"
total_ms="0"
api_ms="0"
lines_added="0"
lines_removed="0"
exceeds_200k="false"
output_style=""
if [ -n "$session_json" ] && command -v jq >/dev/null 2>&1; then
  {
    IFS= read -r session_id    || session_id=""
    IFS= read -r model_name    || model_name=""
    IFS= read -r cwd           || cwd=""
    IFS= read -r cost_usd      || cost_usd="0"
    IFS= read -r total_ms      || total_ms="0"
    IFS= read -r api_ms        || api_ms="0"
    IFS= read -r lines_added   || lines_added="0"
    IFS= read -r lines_removed || lines_removed="0"
    IFS= read -r exceeds_200k  || exceeds_200k="false"
    IFS= read -r output_style  || output_style=""
  } < <(printf '%s' "$session_json" | jq -r '
        (.session_id // ""),
        ((.model.display_name // .model.id) // ""),
        ((.workspace.current_dir // .cwd) // ""),
        (.cost.total_cost_usd // 0),
        (.cost.total_duration_ms // 0),
        (.cost.total_api_duration_ms // 0),
        (.cost.total_lines_added // 0),
        (.cost.total_lines_removed // 0),
        (.exceeds_200k_tokens // false),
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

# --- 4. Segment functions --------------------------------------------------
seg_time() {
  printf '%s%s%s' "$(label "$C_YELLOW" '' 'Time')" "$C_FG$(date '+%H:%M:%S')" "$C_RESET"
}

seg_model() {
  [ -n "$model_name" ] || return 0
  # Trim long internal names: "claude-opus-4.7-1m-internal" -> "opus-4.7-1m"
  local short="$model_name"
  short="${short#claude-}"
  short="${short%-internal}"
  printf '%s%s%s' "$(label "$C_AQUA" '' 'Model')" "$C_FG$short" "$C_RESET"
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
  printf '%s%s%dm%s' "$(label "$C_ORANGE" '' 'Run')" "$C_FG" "$mins" "$C_RESET"
}

seg_wall() {
  is_pos_int "$total_ms" || return 0
  printf '%s%s%s%s' "$(label "$C_PURPLE" '' 'Wall')" "$C_FG" "$(fmt_ms "$total_ms")" "$C_RESET"
}

seg_api_time() {
  is_pos_int "$api_ms" || return 0
  printf '%s%s%s%s' "$(label "$C_BLUE" '' 'API')" "$C_FG" "$(fmt_ms "$api_ms")" "$C_RESET"
}

seg_cost() {
  is_pos_num "$cost_usd" || return 0
  # awk handles the float math + 2-decimal rounding.
  local pretty
  pretty="$(awk -v c="$cost_usd" 'BEGIN{ printf("$%.2f", c+0) }')"
  printf '%s%s%s%s' "$(label "$C_GREEN" '' 'Cost')" "$C_FG" "$pretty" "$C_RESET"
}

seg_diff() {
  # Skip if both zero; otherwise color +adds green / -dels red.
  local has=0
  is_pos_int "$lines_added" && has=1
  is_pos_int "$lines_removed" && has=1
  [ "$has" = "1" ] || return 0
  local body=""
  if is_pos_int "$lines_added"; then
    body="${C_GREEN}+${lines_added}${C_RESET}"
  fi
  if is_pos_int "$lines_removed"; then
    [ -n "$body" ] && body="${body}${C_FG}/"
    body="${body}${C_RED}-${lines_removed}${C_RESET}"
  fi
  printf '%s%s' "$(label "$C_GREEN" '' 'Diff')" "$body"
}

seg_ctx() {
  [ "$exceeds_200k" = "true" ] || return 0
  printf '%s%s200k+%s' "$(label "$C_RED" '' 'Ctx')" "$C_RED" "$C_RESET"
}

seg_style() {
  [ -n "$output_style" ] || return 0
  [ "$output_style" = "default" ] && return 0
  printf '%s%s%s%s' "$(label "$C_PURPLE" '' 'Style')" "$C_FG" "$output_style" "$C_RESET"
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
      "$(label "$C_AQUA" '' 'Repo')" \
      "$state_color" "$state" "$C_RESET" \
      "$C_ORANGE" "$sync" "$C_RESET"
  else
    printf '%s%s%s%s' \
      "$(label "$C_AQUA" '' 'Repo')" \
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
  printf '%s%s%s%s' "$(label "$C_YELLOW" '' 'Branch')" "$C_FG" "$br" "$C_RESET"
}

seg_stash() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local count
  count="$(git stash list 2>/dev/null | wc -l | tr -d ' ')"
  is_pos_int "$count" || return 0
  printf '%s%s%d%s' "$(label "$C_ORANGE" '' 'Stash')" "$C_FG" "$count" "$C_RESET"
}

seg_venv() {
  [ -n "${VIRTUAL_ENV:-}" ] || return 0
  printf '%s%s%s%s' "$(label "$C_BLUE" '' 'Venv')" "$C_FG" "$(basename "$VIRTUAL_ENV")" "$C_RESET"
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
  printf '%s%s%s%s' "$(label "$C_PURPLE" '' 'GH')" "$C_FG" "$account" "$C_RESET"
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

printf '%s%s%s' \
  "$(repeat ' ' "$PAD_LEFT")" \
  "$out" \
  "$(repeat ' ' "$PAD_RIGHT")"
