# RMUX session helpers.

unalias rr rd rl 2>/dev/null
unfunction rr rd rl 2>/dev/null

function rr {
  emulate -L zsh
  if (( $# != 1 )); then
    print -u2 "usage: rr <session>"
    return 2
  fi
  if (( ! $+commands[rmux] )); then
    print -u2 "rr: rmux not found"
    return 127
  fi
  if command rmux has-session -t "$1" >/dev/null 2>&1; then
    print "rr: resuming session '$1'"
    command rmux attach-session -t "$1"
  else
    print "rr: session '$1' does not exist; creating it"
    command rmux new-session -s "$1"
  fi
}

function rd {
  emulate -L zsh
  if (( $# != 1 )); then
    print -u2 "usage: rd <session>"
    return 2
  fi
  if (( ! $+commands[rmux] )); then
    print -u2 "rd: rmux not found"
    return 127
  fi
  command rmux kill-session -t "$1"
}

function rl {
  emulate -L zsh
  if (( $# != 0 )); then
    print -u2 "usage: rl"
    return 2
  fi
  if (( ! $+commands[rmux] )); then
    print -u2 "rl: rmux not found"
    return 127
  fi
  command rmux list-sessions
}

unalias exit logout 2>/dev/null
unfunction exit logout 2>/dev/null

function exit {
  emulate -L zsh
  if [[ -n "${RMUX:-}" ]] && (( $+commands[rmux] )); then
    command rmux detach-client
    return $?
  fi
  builtin exit "$@"
}

function logout {
  emulate -L zsh
  if [[ -n "${RMUX:-}" ]] && (( $+commands[rmux] )); then
    command rmux detach-client
    return $?
  fi
  builtin logout "$@"
}

function _rmux_detach_or_delete_char {
  if [[ -n "${RMUX:-}" && -z "$BUFFER" ]] && (( $+commands[rmux] )); then
    zle -I
    command rmux detach-client
  else
    zle .delete-char-or-list
  fi
}

zle -N _rmux_detach_or_delete_char
bindkey -M emacs '^D' _rmux_detach_or_delete_char
bindkey -M viins '^D' _rmux_detach_or_delete_char
