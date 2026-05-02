# gg <title>
#
# Set the current WezTerm tab + window title to <title>, then launch
# `copilot` in the current shell. Use `gg "Tab Title"` to start a Copilot
# session with a meaningful name on the tab.
#
# Notes:
# - Uses OSC escape sequences (which WezTerm honors for the window title bar)
#   *and* the `wezterm cli` IPC for in-app state. Both are needed because
#   WezTerm's window title bar reflects the active pane title (OSC 2), while
#   `wezterm cli` updates the internal tab/window title attributes.
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
  command copilot --allow-all-tools --allow-all-paths
  unset DISABLE_AUTO_TITLE
}
