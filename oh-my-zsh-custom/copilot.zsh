# Run Copilot with the WezTerm-compatible true-color capability path, then
# clean up stale payloads after successful self-updates.
copilot() {
  TERM_PROGRAM=WezTerm COLORTERM=truecolor FORCE_COLOR=3 command copilot "$@"
  local copilot_status=$?

  if [ "$copilot_status" -eq 0 ] && [ "${1:-}" = "update" ] && [ -x "$HOME/.copilot/cleanup-legacy.sh" ]; then
    "$HOME/.copilot/cleanup-legacy.sh" || true
  fi

  return "$copilot_status"
}
