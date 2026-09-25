# Multiplexer session helpers.
#
# Platform rule: Windows uses RMUX; macOS and Linux use native tmux.
# On macOS and Linux each rX helper runs its tX twin from zz-tmux.zsh.

unalias rr rd rl rs rh rmux 2>/dev/null
unfunction rr rd rl rs rh rmux 2>/dev/null

function _mux_uses_rmux {
  case "$OSTYPE" in
    msys*|cygwin*|win32*) return 0 ;;
  esac
  return 1
}

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

if _mux_uses_rmux; then
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
else
  # macOS and Linux: rr=tt, rl=tl, rd=td, rh=th, rs=ts. No rmux wrapper.
  function rr { tt "$@"; }
  function rl { tl "$@"; }
  function rd { td "$@"; }
  function rh { th "$@"; }
  function rs { ts "$@"; }
fi

unalias exit logout 2>/dev/null
unfunction exit logout 2>/dev/null

function exit {
  emulate -L zsh
  if [[ -n "${RMUX:-}" ]]; then
    _rmux_store client detach-client
    return $?
  elif [[ -n "${TMUX:-}" ]] && (( $+functions[_tmux_store] )); then
    _tmux_store client detach-client
    return $?
  fi
  builtin exit "$@"
}

function logout {
  emulate -L zsh
  if [[ -n "${RMUX:-}" ]]; then
    _rmux_store client detach-client
    return $?
  elif [[ -n "${TMUX:-}" ]] && (( $+functions[_tmux_store] )); then
    _tmux_store client detach-client
    return $?
  fi
  builtin logout "$@"
}

function _rmux_detach_or_delete_char {
  if [[ -n "${RMUX:-}" && -z "$BUFFER" ]]; then
    zle -I
    _rmux_store client detach-client
  elif [[ -n "${TMUX:-}" && -z "$BUFFER" ]] && (( $+functions[_tmux_store] )); then
    zle -I
    _tmux_store client detach-client
  else
    zle .delete-char-or-list
  fi
}

zle -N _rmux_detach_or_delete_char
bindkey -M emacs '^D' _rmux_detach_or_delete_char
bindkey -M viins '^D' _rmux_detach_or_delete_char
