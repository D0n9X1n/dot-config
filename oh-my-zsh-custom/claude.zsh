# claude (function wrapper)
#
# Bare `claude` is overridden as a function (not an alias — aliases can't
# pass through positional args like `claude --resume`). It tacks on
# `--permission-mode bypassPermissions` so every invocation runs in
# bypass mode, matching the global behavior we'd want from settings.json
# but can't have (the binary rejects defaultMode="bypassPermissions" with
# "...is disabled by settings"). The flag is the only path the binary
# honors.
#
# Model + effort defaults live in ~/.claude/settings.json, but are also
# injected here because Claude Code may rewrite settings.json at runtime.

unalias claude 2>/dev/null
unfunction claude 2>/dev/null
function claude {
  emulate -L zsh
  local -a defaults
  local has_model=0
  local has_effort=0
  local arg

  for arg in "$@"; do
    case "$arg" in
      --model|--model=*) has_model=1 ;;
      --effort|--effort=*) has_effort=1 ;;
    esac
  done

  defaults=(--permission-mode bypassPermissions)
  (( has_model )) || defaults+=(--model 'claude-opus-4-8[1m]')
  (( has_effort )) || defaults+=(--effort xhigh)

  command claude "${defaults[@]}" "$@"
}
