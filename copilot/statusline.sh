#!/usr/bin/env bash
# Custom status line for Copilot CLI.
#
# Renders a single status line *below the input prompt*. Each segment is
# `<NerdFont icon> <Label> <value>` separated by a Unicode bar. The whole
# line is wrapped in ANSI dim (\033[2m...\033[0m) so it visually recedes
# from the prompt above it. Environment overrides:
#   COPILOT_STATUSLINE_NO_ICONS=1   drop icons, keep the text labels
#   COPILOT_STATUSLINE_NO_DIM=1     drop the ANSI dim wrap
#
# Quick check that all icons render in your terminal:
#     ~/.copilot/statusline.sh --test
# That command also runs `fc-list` to verify each codepoint exists in some
# installed font (skips the check silently if fontconfig isn't installed).
#
# Segments (in render order; each is omitted when its data is unavailable):
#   Time         wall-clock HH:MM:SS
#   Req          .cost.total_premium_requests (omitted when 0)
#   Run          minutes since this session_id was first seen
#   API          .cost.total_api_duration_ms formatted (Hh Mm / Mm / Ss)
#   Cache        cache-hit % = total_cache_read_tokens / total_input_tokens
#   Last         last-turn input→output tokens, k/M-formatted
#   Repo         git clean/dirty + ↑ahead/↓behind upstream
#   Stash        git stash count (omitted when 0)
#   Venv         basename of $VIRTUAL_ENV
#   GH           `gh auth status` account (cached 5 min)
#   MCP          number of servers in ~/.copilot/mcp-config.json
#
# Things deliberately not rendered (already in Copilot's built-in footer):
# model/effort, cwd, branch, context-window %, +/- code changes, agent.
#
# JSON fields verified against Copilot CLI v1.0.44-2 (no `.mode` field, so
# no plan-mode badge here — Copilot already shows it in the footer).
#
# We avoid `set -e` so a single failing segment never blanks the whole line.

set -u

# --- Configuration ---------------------------------------------------------
SEGMENTS="time premium timer api_time cache_pct last_call git stash venv gh_account mcp_count"
SEP=' │ '

ICONS_ON=1
[ -n "${COPILOT_STATUSLINE_NO_ICONS:-}" ] && ICONS_ON=0

# ANSI dim wrap. Set COPILOT_STATUSLINE_NO_DIM=1 to disable.
DIM=$'\033[2m'
RESET=$'\033[0m'
if [ -n "${COPILOT_STATUSLINE_NO_DIM:-}" ]; then
  DIM=""
  RESET=""
fi

# Per-side padding in the script. The Copilot CLI statusLine config only
# honors a single `padding` key (paddingTop/Bottom/Left/Right are silently
# ignored), so we emit our own spacing here for finer control.
#   PAD_TOP   blank lines printed before the status line
#   PAD_LEFT  spaces printed before the dimmed segments
#   PAD_RIGHT spaces printed after the dimmed segments (rarely useful)
PAD_TOP="${COPILOT_STATUSLINE_PAD_TOP:-8}"
PAD_LEFT="${COPILOT_STATUSLINE_PAD_LEFT:-0}"
PAD_RIGHT="${COPILOT_STATUSLINE_PAD_RIGHT:-0}"

# repeat <char> <count> -> string of that char repeated count times
repeat() {
  local ch=$1 n=$2 out=""
  while [ "$n" -gt 0 ]; do out="${out}${ch}"; n=$((n - 1)); done
  printf '%s' "$out"
}

CACHE_DIR="${TMPDIR:-/tmp}/copilot-statusline-cache-$USER"
mkdir -p "$CACHE_DIR" 2>/dev/null || true

# --- --test flag: visually verify which icons render -----------------------
# Prints each segment's codepoint, glyph, and label so you can scan for
# tofu/box characters. If `fc-list` is installed, also reports whether the
# codepoint exists in any installed font (excludes macOS's `.LastResort`
# placeholder, which "matches" every codepoint with a missing-glyph box).
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
f017||Time
f02d||Session
f155||Req
f252||Run
f233||API
f021||Cache
f1d8||Last
f1d3||Repo
f187||Stash
e73c||Venv
f09b||GH
f1e6||MCP
TEST_ICONS_EOF
  exit 0
fi

# --- 1. Read JSON payload from stdin ---------------------------------------
session_json=""
if [ ! -t 0 ]; then
  session_json="$(cat 2>/dev/null || true)"
fi

# --- 2. Parse all fields with one jq call (one field per line) -------------
# Per-line read avoids the @tsv + IFS=$'\t' read pitfall where leading empty
# fields get collapsed by `read`. Works on macOS bash 3.2 (no `mapfile`).
session_id=""
session_name=""
premium="0"
api_ms="0"
total_input="0"
cache_read="0"
last_in="0"
last_out="0"
if [ -n "$session_json" ] && command -v jq >/dev/null 2>&1; then
  {
    IFS= read -r session_id   || session_id=""
    IFS= read -r session_name || session_name=""
    IFS= read -r premium      || premium="0"
    IFS= read -r api_ms       || api_ms="0"
    IFS= read -r total_input  || total_input="0"
    IFS= read -r cache_read   || cache_read="0"
    IFS= read -r last_in      || last_in="0"
    IFS= read -r last_out     || last_out="0"
  } < <(printf '%s' "$session_json" | jq -r '
        (.session_id // ""),
        (.session_name // ""),
        (.cost.total_premium_requests // 0),
        (.cost.total_api_duration_ms // 0),
        (.context_window.total_input_tokens // 0),
        (.context_window.total_cache_read_tokens // 0),
        (.context_window.last_call_input_tokens // 0),
        (.context_window.last_call_output_tokens // 0)
      ' 2>/dev/null)
fi

# --- 3. Helpers ------------------------------------------------------------
label() {
  # Render "<icon> <text-label> " when icons are on, or just "<text-label> "
  # when COPILOT_STATUSLINE_NO_ICONS=1. The text label is always present so
  # the segment is readable even if the Nerd Font glyph fails to render.
  if [ "$ICONS_ON" = "1" ]; then
    printf '%s %s ' "$1" "$2"
  else
    printf '%s ' "$2"
  fi
}

is_pos_int() {
  case "${1:-}" in
    '' | *[!0-9]*) return 1 ;;
    0) return 1 ;;
    *) return 0 ;;
  esac
}

fmt_short() {
  # 385612 -> 385k, 4500000 -> 4.5M
  local n=${1:-0}
  if [ "$n" -ge 1000000 ]; then
    awk -v n="$n" 'BEGIN{ printf("%.1fM", n/1000000) }'
  elif [ "$n" -ge 1000 ]; then
    awk -v n="$n" 'BEGIN{ printf("%dk", int(n/1000)) }'
  else
    printf '%d' "$n"
  fi
}

fmt_ms() {
  # 6615880 -> 1h50m; 45000 -> 45s; 0 -> ""
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
# Each prints "<icon> <Label> <value>" or nothing (skip).
seg_time() {
  printf '%s%s' "$(label '' 'Time')" "$(date '+%H:%M:%S')"
}

seg_session_name() {
  [ -n "$session_name" ] || return 0
  local name="$session_name"
  if [ ${#name} -gt 28 ]; then
    name="${name:0:27}…"
  fi
  printf '%s%s' "$(label '' 'Session')" "$name"
}

seg_premium() {
  is_pos_int "$premium" || return 0
  printf '%s%s' "$(label '' 'Req')" "$premium"
}

seg_timer() {
  [ -n "$session_id" ] || return 0
  local f="${TMPDIR:-/tmp}/copilot-statusline-${USER}-${session_id}.start"
  if [ ! -f "$f" ]; then
    date +%s >"$f" 2>/dev/null || true
  fi
  [ -f "$f" ] || return 0
  local started
  started="$(cat "$f" 2>/dev/null || echo 0)"
  local now mins
  now="$(date +%s)"
  mins=$(((now - started) / 60))
  [ "$mins" -gt 0 ] || return 0
  printf '%s%dm' "$(label '' 'Run')" "$mins"
}

seg_api_time() {
  is_pos_int "$api_ms" || return 0
  printf '%s%s' "$(label '' 'API')" "$(fmt_ms "$api_ms")"
}

seg_cache_pct() {
  is_pos_int "$total_input" || return 0
  local pct=$(((cache_read * 100) / total_input))
  printf '%s%d%%' "$(label '' 'Cache')" "$pct"
}

seg_last_call() {
  is_pos_int "$last_in" || return 0
  printf '%s%s→%s' "$(label '' 'Last')" \
    "$(fmt_short "$last_in")" "$(fmt_short "$last_out")"
}

seg_git() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local state="clean"
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    state="dirty"
  fi
  local sync=""
  local counts behind ahead
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
    printf '%s%s (%s)' "$(label '' 'Repo')" "$state" "$sync"
  else
    printf '%s%s' "$(label '' 'Repo')" "$state"
  fi
}

seg_stash() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local count
  count="$(git stash list 2>/dev/null | wc -l | tr -d ' ')"
  is_pos_int "$count" || return 0
  printf '%s%d' "$(label '' 'Stash')" "$count"
}

seg_venv() {
  [ -n "${VIRTUAL_ENV:-}" ] || return 0
  printf '%s%s' "$(label '' 'Venv')" "$(basename "$VIRTUAL_ENV")"
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
  printf '%s%s' "$(label '' 'GH')" "$account"
}

seg_mcp_count() {
  local f="$HOME/.copilot/mcp-config.json"
  [ -f "$f" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local count
  count="$(jq -r '(.mcpServers // {}) | length' "$f" 2>/dev/null)"
  is_pos_int "$count" || return 0
  printf '%s%d' "$(label '' 'MCP')" "$count"
}

# --- 5. Render -------------------------------------------------------------
out=""
for s in $SEGMENTS; do
  part="$("seg_$s" 2>/dev/null || true)"
  [ -n "$part" ] || continue
  if [ -n "$out" ]; then
    out="${out}${SEP}${part}"
  else
    out="${part}"
  fi
done

# Emit top padding via a dedicated printf — $(...) command substitution
# strips trailing newlines, which would silently drop PAD_TOP entirely.
i=0
while [ "$i" -lt "$PAD_TOP" ]; do
  printf '\n'
  i=$((i + 1))
done

printf '%s%s%s%s%s' \
  "$DIM" \
  "$(repeat ' ' "$PAD_LEFT")" \
  "$out" \
  "$(repeat ' ' "$PAD_RIGHT")" \
  "$RESET"''

