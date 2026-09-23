unalias tt tl td th ts 2>/dev/null
unfunction tt tl td th ts 2>/dev/null

function _tmux_store {
  if [[ -x "$HOME/.local/bin/tmux-store" ]]; then
    "$HOME/.local/bin/tmux-store" "$@"
  elif (( $+commands[tmux-store] )); then
    command tmux-store "$@"
  else
    print -u2 'Tmux helpers are not installed; run ./install.sh in dot-configs.'
    return 127
  fi
}

function tt {
  emulate -L zsh
  if (( $# != 1 )); then
    print -u2 'usage: tt <session>'
    return 2
  fi
  _tmux_store attach "$1"
}

function tl {
  emulate -L zsh
  if (( $# )); then
    print -u2 'usage: tl'
    return 2
  fi
  _tmux_store list
}

function td {
  emulate -L zsh
  if (( $# != 1 )); then
    print -u2 'usage: td <session>'
    return 2
  fi
  _tmux_store delete "$1"
}

function th {
  emulate -L zsh
  if (( $# )); then
    print -u2 'usage: th'
    return 2
  fi
  _tmux_store help
}

function ts {
  emulate -L zsh
  if (( $# )); then
    print -u2 'usage: ts'
    return 2
  fi
  _tmux_store restart
}

if [[ -o interactive ]]; then
  unalias tr 2>/dev/null
  unfunction tr 2>/dev/null
  function tr {
    emulate -L zsh
    if (( $# == 1 )) && [[ "$1" != -* ]]; then
      tt "$1"
    else
      command tr "$@"
    fi
  }
fi
