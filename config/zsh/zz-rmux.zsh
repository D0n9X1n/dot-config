# RMUX session helpers.

unalias rr rd rl rs rh rmux 2>/dev/null
unfunction rr rd rl rs rh rmux 2>/dev/null

function _rmux_store {
  if [[ -x "$HOME/.local/bin/rmux-store" ]]; then
    "$HOME/.local/bin/rmux-store" "$@"
  elif (( $+commands[rmux-store] )); then
    command rmux-store "$@"
  else
    print -u2 'RMUX helpers are not installed; run ./install.sh in dot-configs.'
    return 127
  fi
}

function rmux {
  _rmux_store client "$@"
}
function rs {
  if (( $# )); then
    print -u2 'usage: rs'
    return 2
  fi
  _rmux_store restart
}
function rh {
  if (( $# )); then
    print -u2 'usage: rh'
    return 2
  fi
  _rmux_store help
}

function rr {
  emulate -L zsh
  if (( $# != 1 )); then
    print -u2 "usage: rr <session>"
    return 2
  fi
  _rmux_store rr "$1"
}

function rd {
  emulate -L zsh
  if (( $# != 1 )); then
    print -u2 "usage: rd <session>"
    return 2
  fi
  _rmux_store rd "$1"
}

function rl {
  emulate -L zsh
  if (( $# != 0 )); then
    print -u2 "usage: rl"
    return 2
  fi
  _rmux_store rl
}

unalias exit logout 2>/dev/null
unfunction exit logout 2>/dev/null

function exit {
  emulate -L zsh
  if [[ -n "${RMUX:-}" ]]; then
    _rmux_store client detach-client
    return $?
  fi
  builtin exit "$@"
}

function logout {
  emulate -L zsh
  if [[ -n "${RMUX:-}" ]]; then
    _rmux_store client detach-client
    return $?
  fi
  builtin logout "$@"
}

function _rmux_detach_or_delete_char {
  if [[ -n "${RMUX:-}" && -z "$BUFFER" ]]; then
    zle -I
    _rmux_store client detach-client
  else
    zle .delete-char-or-list
  fi
}

zle -N _rmux_detach_or_delete_char
bindkey -M emacs '^D' _rmux_detach_or_delete_char
bindkey -M viins '^D' _rmux_detach_or_delete_char
