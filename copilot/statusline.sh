#!/usr/bin/env bash
# Custom status line for Copilot CLI.
#
# Renders a compact status line *below the input prompt*. Complements the
# footer (which already shows model/effort, dir, branch, context window, quota,
# agent, code-changes, username) with info the footer doesn't expose:
#   - wall-clock time
#   - working tree clean/dirty indicator (footer shows branch only)
#   - active Python venv (if any)
#
# The Copilot CLI passes the current session status as JSON on stdin. We drain
# but don't currently consume it — reserved for future use.
#
# Glyphs come from a Nerd Font (Recursive Mono Nerd Font + Symbols Only Nerd
# Font are wired up in the WezTerm config). Make sure your terminal renders
# Nerd Font glyphs or the icons will look like tofu.

set -u

# Drain stdin so the CLI's JSON payload doesn't pile up.
cat >/dev/null 2>&1 || true

time_str="$(date '+%H:%M:%S')"

git_str=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    git_str="  dirty"
  else
    git_str="  clean"
  fi
fi

venv_str=""
if [ -n "${VIRTUAL_ENV:-}" ]; then
  venv_str="  $(basename "$VIRTUAL_ENV")"
fi

printf '  %s%s%s' "$time_str" "$git_str" "$venv_str"
