# gg <title>
#
# Set the current terminal tab + window title to <title>, then launch
# `copilot` in the current shell. Use `gg "Tab Title"` to start a Copilot
# session with a meaningful name on the tab.
#
# Notes:
# - Uses OSC 1/2 escape sequences for the title (works in Ghostty, WezTerm,
#   iTerm2, and anything OSC-compliant — Ghostty and WezTerm both reflect
#   the active pane's OSC 2 in the window title bar).
# - For WezTerm specifically, also calls `wezterm cli set-tab-title` /
#   `set-window-title` to keep WezTerm's internal state in sync. Guarded by
#   `(( $+commands[wezterm] ))`, so it's a no-op outside WezTerm.
# - Sets DISABLE_AUTO_TITLE during the Copilot session so oh-my-zsh's
#   precmd/preexec hooks don't repeatedly overwrite the title.
# - Uses `command copilot` to bypass any shell alias of the same name.

unalias gg 2>/dev/null
unfunction gg 2>/dev/null
function gg {
  emulate -L zsh
  if [[ -z "$1" ]]; then
    print -u2 "Usage: gg <tab title>"
    return 1
  fi
  local title="$1"
  DISABLE_AUTO_TITLE=true
  print -Pn "\e]2;${title}\a"
  print -Pn "\e]1;${title}\a"
  if (( $+commands[wezterm] )); then
    wezterm cli set-tab-title -- "$title" 2>/dev/null
    wezterm cli set-window-title -- "$title" 2>/dev/null
  fi
  command copilot --allow-all-tools --allow-all-paths --effort xhigh
  unset DISABLE_AUTO_TITLE
}
