# --yolo is --allow-all: tools, paths, and URLs. Keep the original arguments
# available for successful-update cleanup behind the public alias.
unalias copilot 2>/dev/null || true
unfunction copilot 2>/dev/null || true

function _dot_configs_copilot {
  emulate -L zsh
  TERM_PROGRAM=WezTerm COLORTERM=truecolor FORCE_COLOR=3 command copilot --yolo "$@"
  local copilot_status=$?

  if [ "$copilot_status" -eq 0 ] && [ "${1:-}" = "update" ] && [ -x "$HOME/.copilot/cleanup-legacy.sh" ]; then
    "$HOME/.copilot/cleanup-legacy.sh" || true
  fi

  return "$copilot_status"
}

alias copilot='_dot_configs_copilot'
