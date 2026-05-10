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
# Model + effort defaults live in ~/.claude/settings.json (model =
# claude-opus-4.7-1m-internal, effortLevel = "xhigh"); to switch models
# mid-session use Claude Code's `/model <name>` — the proxy passes
# free-form model names through.

unalias claude 2>/dev/null
unfunction claude 2>/dev/null
function claude {
  emulate -L zsh
  command claude --permission-mode bypassPermissions "$@"
}
