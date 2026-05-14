# gg <title>
#
# Set the current terminal tab + window title to <title>, then launch
# `copilot` in the current shell. Use `gg "Tab Title"` to start a Copilot
# session with a meaningful name on the tab.
#
# Notes:
# - Uses OSC 1/2 escape sequences for the title (works in WezTerm,
#   iTerm2, and anything OSC-compliant). Inside tmux the escape
#   doesn't reach the outer terminal because we set `allow-rename off` /
#   `automatic-rename off` in .tmux.conf, so we also call `tmux rename-window`
#   directly — that updates tmux's status-bar window name, and tmux's
#   `set-titles on` then propagates "#S · #W" up to the outer terminal.
# - For WezTerm specifically, also calls `wezterm cli set-tab-title` /
#   `set-window-title` to keep WezTerm's internal state in sync. Guarded by
#   `(( $+commands[wezterm] ))` and `$WEZTERM_PANE`, so it's a no-op when
#   wezterm is just on PATH but not the active terminal.
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
  # Prepend a Nerd Font glyph so the tab is visually distinct as a
  # Copilot CLI session. fa-github (U+F09B) is the GitHub octocat — the
  # most direct "this is GitHub Copilot" signal.
  local icon=$''
  local title="$icon $1"
  DISABLE_AUTO_TITLE=true
  print -Pn "\e]2;${title}\a"
  print -Pn "\e]1;${title}\a"
  if [[ -n "$TMUX" ]]; then
    command tmux rename-window -- "$title" 2>/dev/null
  fi
  if [[ -n "$WEZTERM_PANE" ]] && (( $+commands[wezterm] )); then
    wezterm cli set-tab-title -- "$title" 2>/dev/null
    wezterm cli set-window-title -- "$title" 2>/dev/null
  fi
  command copilot --allow-all-tools --allow-all-paths --effort xhigh
  unset DISABLE_AUTO_TITLE
}
