# gg [title]
#
# Set the current terminal tab + window title to [title], then launch
# `copilot` in the current shell. If title is omitted, use the current
# directory path so a bare `gg` session is still identifiable.
#
# Notes:
# - Uses OSC 1/2 escape sequences for the outer terminal title and renames the
#   RMUX window directly so the status bar stays aligned.
# - Sets DISABLE_AUTO_TITLE during the Copilot session so oh-my-zsh's
#   precmd/preexec hooks don't repeatedly overwrite the title.
# - Sends Copilot a process-scoped WezTerm/true-color identity even inside RMUX.
# - Uses `command copilot` to bypass any shell alias of the same name.

unalias gg 2>/dev/null
unfunction gg 2>/dev/null
function gg {
  emulate -L zsh
  # Prepend a Nerd Font glyph so the tab is visually distinct as a
  # Copilot CLI session. fa-github (U+F09B) is the GitHub octocat — the
  # most direct "this is GitHub Copilot" signal.
  local icon=$''
  local title_text="${*:-$PWD}"
  local title="$icon $title_text"
  DISABLE_AUTO_TITLE=true
  print -Pn "\e]2;${title}\a"
  print -Pn "\e]1;${title}\a"
  if [[ -n "$RMUX" ]] && (( $+commands[rmux] )); then
    command rmux rename-window -- "$title" 2>/dev/null
  fi
  TERM_PROGRAM=WezTerm COLORTERM=truecolor FORCE_COLOR=3 \
    command copilot --allow-all-tools --allow-all-paths --model gpt-6-astra --context long_context --effort max
  unset DISABLE_AUTO_TITLE
}
