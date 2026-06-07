# cc [title]
#
# Sibling of `gg` (oh-my-zsh-custom/gg.zsh) but launches Anthropic's
# Claude Code CLI instead of GitHub Copilot CLI. Sets the active terminal
# tab + window title to [title] via OSC 1/2, also tells tmux + WezTerm
# directly so the title sticks even when nested, then runs `claude` in
# the current shell. If title is omitted, use the current directory path.
#
# Model + effort are pinned globally in ~/.claude/settings.json and injected
# here because Claude Code may rewrite settings.json at runtime.
# Permission mode CANNOT be pinned via settings.json — the binary explicitly rejects
# defaultMode="bypassPermissions" with "bypassPermissions mode is
# disabled by settings". So we pass --permission-mode at the command
# line on every invocation, which the binary does honor.
#
# See gg.zsh for the rationale on each title-update path; this is the
# same recipe with a different launcher.

unalias cc 2>/dev/null
unfunction cc 2>/dev/null
function cc {
  emulate -L zsh
  # Prepend a Nerd Font glyph so the tab is visually distinct as a Claude
  # Code session. mdi-creation (U+F0674) renders as sparkles in any Nerd
  # Font — fits the "AI agent" vibe and reads cleanly even without color.
  # Wrap in $'...' (zsh ANSI-C quoting) so the literal codepoint sits in
  # the title bytes.
  local icon=$''
  local title_text="${*:-$PWD}"
  local title="$icon $title_text"
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
  command claude --permission-mode bypassPermissions --model 'claude-opus-4-8[1m]' --effort xhigh
  unset DISABLE_AUTO_TITLE
}
