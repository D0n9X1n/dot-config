# cc <title>
#
# Sibling of `gg` (oh-my-zsh-custom/gg.zsh) but launches Anthropic's
# Claude Code CLI instead of GitHub Copilot CLI. Sets the active terminal
# tab + window title to <title> via OSC 1/2, also tells tmux + WezTerm
# directly so the title sticks even when nested, then runs `claude` in
# the current shell.
#
# `claude` is invoked bare — model and effort are pinned globally in
# ~/.claude/settings.json (model = claude-opus-4.7-1m-internal,
# effortLevel = "xhigh", permissions.defaultMode = "bypassPermissions"),
# so no per-session flags are needed.
#
# See gg.zsh for the rationale on each title-update path; this is the
# same recipe with a different launcher.

unalias cc 2>/dev/null
unfunction cc 2>/dev/null
function cc {
  emulate -L zsh
  if [[ -z "$1" ]]; then
    print -u2 "Usage: cc <tab title>"
    return 1
  fi
  local title="$1"
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
  command claude
  unset DISABLE_AUTO_TITLE
}
