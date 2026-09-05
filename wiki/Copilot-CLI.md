# Copilot CLI

English | [简体中文](Copilot-CLI-zh-CN.md)

Copilot CLI files live under `config/copilot/`. They install under `~/.copilot/`.

## Defaults

`config/copilot/settings.json` uses:

```text
model:       gpt-6-astra
context:     long_context
effort:      max
theme:       default (terminal Base-16)
keep alive:  busy
streaming:   on
```

Run `copilot`, then enter `/model` inside its interactive session to see your account's available models and their effort choices. Astra advertises `low`, `medium`, `high`, `xhigh`, and `max`; availability depends on the account and organization policy. The CLI uses canonical `gpt-6-astra`, without Claude Code's `[1m]` suffix.

To change the managed default, edit `config/copilot/settings.json` and the `--model` in `config/zsh/gg.zsh` together, then run `scripts/check.sh all`. For an unmanaged installation, `/config model` changes the Copilot user default; here, edit the tracked sources so the next install does not undo your choice.

The custom footer hides built-in fields and runs `~/.copilot/statusline.sh`.

Copilot can add or remove a `staff` field at runtime. Keep that field out of the tracked file. In `statusLine`, only the simple `padding` field is supported. Per-side spacing belongs in the shell script.

## Global instructions

Copilot has two installed instruction files:

- `config/copilot/copilot-instructions.md` → `~/.copilot/copilot-instructions.md`
- `config/copilot/AGENTS.md` → `~/.copilot/AGENTS.md`

The native file keeps Copilot's user-wide behavior. It makes conversational prose direct and concise by default. Requests for more detail still win, and code, commands, findings, evidence, caveats, safety information, and technical precision stay complete.

`AGENTS.md` stays focused on the Wiki pointer for reusable GitHub Wiki and release work.

`config/zsh/custom.zsh` adds `~/.copilot` to `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`. It keeps any paths that already exist and does not add a duplicate.

## Terminal identity

SonicTerm and RMUX use their real terminal names. Copilot does not know every RMUX or SonicTerm capability path.

The `copilot` wrapper and `gg` start only the Copilot child with:

```text
TERM_PROGRAM=WezTerm
COLORTERM=truecolor
FORCE_COLOR=3
```

This turns on Copilot's supported terminal path. The managed `default` theme uses the terminal's Base-16 colors, so it inherits SonicTerm's Apollo ANSI palette. It does not install or run WezTerm. Other programs still see `SonicTerm` or `rmux`.

## Launch commands

```sh
copilot          # normal Copilot wrapper
gg my-project    # titled, unrestricted Copilot session
```

`gg` uses GPT-6 Astra, long context, and max effort. It also passes `--allow-all-tools --allow-all-paths`, so tools and paths do not ask for approval. Use plain `copilot` when you do not want that access mode.

`gg` sends OSC title codes to SonicTerm. Inside RMUX, it also runs `rmux rename-window`. It does not call tmux or the WezTerm CLI.

## Status line

The Copilot status line shares the five-line layout and locally generated Apollo colors with Claude:

1. time, run time, requests, WakaTime
2. model, effort, context
3. MCP, skills, agents, tasks, style
4. current path
5. repo, branch, diff, stash, worktree

It reads session JSON with one `jq` call. Both provider status scripts source the same generated Apollo color include and fall back to readable uncolored output when it is absent. Git data is cached for five seconds per working directory. GitHub auth data is cached for five minutes.

Useful environment switches:

| Variable | Work |
|---|---|
| `COPILOT_STATUSLINE_NO_ICONS=1` | Hide icons |
| `COPILOT_STATUSLINE_NO_COLOR=1` | Hide colors |
| `COPILOT_STATUSLINE_PAD_TOP=N` | Add top space |
| `COPILOT_STATUSLINE_PAD_LEFT=N` | Add left space |
| `COPILOT_STATUSLINE_PAD_RIGHT=N` | Add right space |
| `COPILOT_STATUSLINE_SEGMENTS="..."` | Set segment order |
| `COPILOT_STATUSLINE_GIT_TTL=N` | Set Git cache seconds |
| `COPILOT_STATUSLINE_MAX_SUBAGENTS=N` | Limit live rows |

Run the glyph test:

```sh
~/.copilot/statusline.sh --test
```

## Live subagents

Copilot keeps custom live-subagent UI. Hooks call `~/.copilot/subagent-state.sh`:

- session start/end resets rows;
- subagent start adds a row;
- subagent stop removes the matching row.

The status line reads hook rows first. It can use the session event log when rows are missing.

Claude's sibling status line does not copy this part because Claude Code has native agent UI.

## Cleanup

`scripts/copilot/cleanup-legacy.sh` installs as `~/.copilot/cleanup-legacy.sh`.

It keeps the current Copilot package payload, removes old payloads, removes old backup files, and keeps only the newest process log. `install.sh` runs it after linking. A successful `copilot update` runs it too.

## WakaTime

`install.sh` installs or updates the official plugin:

```text
wakatime/copilot-cli-wakatime
```

It uses the API key from `~/.wakatime.cfg`. The plugin manages its own WakaTime CLI.

The installer removes the old WakaTime MCP, old Homebrew `wakatime-cli`, and old third-party npm plugin when found.

## Session sync

The tracked settings sync user sessions for selected repositories and keep all other sessions local. Review `sessionSync` before changing this list.

## Check

```sh
copilot --version
copilot plugin list
~/.copilot/statusline.sh --test
scripts/check.sh instructions
scripts/check.sh all
```

See [SonicTerm and shell](SonicTerm-and-Shell.md) for wrapper and title details.
