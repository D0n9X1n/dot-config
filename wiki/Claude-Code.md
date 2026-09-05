# Claude Code

English | [简体中文](Claude-Code-zh-CN.md)

Claude Code uses a local copilot-relay service in this setup.

```mermaid
flowchart LR
    C[Claude Code] --> R[127.0.0.1:4142]
    R --> G[GitHub Copilot]
```

The source files are under `config/claude/`. They install under `~/.claude/`.

## One-time setup

```sh
./install.sh
npx copilot-relay auth
./install.sh
```

The first Claude Code launch asks if the custom `dummy` API key is allowed. Choose yes. The value is a placeholder required by Claude Code. copilot-relay owns the real GitHub login.

## Model routing

The tracked default is:

```text
Claude-facing name: gpt-6-astra[1m]
Picker name:        GPT-6 Astra
Client effort:      max
Relay route:        gptModel
Upstream model:     gpt-6-astra
```

The name has no `opus`, so copilot-relay sends it to `gptModel`.

Other routes:

| Claude-facing name | Relay lane | Upstream |
|---|---|---|
| `claude-opus-5[1m]` | `opusModel` | `claude-opus-5` |
| Haiku / small-fast aliases | `gptModel` | `gpt-6-astra` |

The `[1m]` suffix keeps Claude Code's one-million-token model context accounting; the relay sends canonical `gpt-6-astra` upstream. Automatic compaction deliberately starts at 75,000 tokens, well before Astra's advertised 872,000-token prompt limit within its 1M total window. This does not retain a full 1M-token conversation history. Relay-side thinking is `max` in `config/copilot-relay/config.yaml`.

Use a relay build with GPT-6 Astra support before relying on this setup (tracked in [copilot-relay issue #57](https://github.com/D0n9X1n/copilot-relay/issues/57)). Update the model in `config/claude/settings.json`, `config/zsh/claude.zsh`, and `config/zsh/cc.zsh` together; the wrappers' `--model` overrides the settings. The relay's `gptModel` stays suffix-free. Its blank `webSearchBackend` also uses Astra. Keep the Opus route separate.

Run `copilot` and enter `/model` to check account availability and effort choices before changing models. That is Copilot's picker, not Claude Code's picker or the relay's local `/v1/models`. After `scripts/check.sh all` passes, apply through `./install.sh` twice and start a new shell and Claude Code session. The installer restarts the relay and may interrupt active requests; wait for them to finish first.

The Sonnet-facing slot routes to GPT-6 Astra through `gptModel`; Opus stays on its separate `opusModel` route. Do not change both routes when a task names only one.

## Main settings

`config/claude/settings.json` sets:

| Key | Value or job |
|---|---|
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:4142` |
| `ANTHROPIC_AUTH_TOKEN` | local placeholder `dummy` |
| `ANTHROPIC_MODEL` | `gpt-6-astra[1m]` |
| `MODEL_REASONING_EFFORT` | `max`; launch wrappers also pass `--effort max` |
| `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | `16` |
| `statusLine.refreshInterval` | `100` |
| `theme` | `custom:apollo`; generated theme assets stay local |
| `autoCompactEnabled` | `true` |
| `autoCompactWindow` | `120000` before the output-token reserve |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `"75"`; triggers compaction at 75,000 tokens with the default output budget |
| `feedbackDrafts` | `off` |

`refreshInterval` belongs inside `statusLine`. Keep max effort in the environment and launcher flags: Claude Code 2.1.261 does not accept `max` in the persisted top-level `effortLevel` setting.

### 75k automatic compaction

Claude Code 2.1.261 requires `autoCompactWindow` to be at least 100,000, so setting it to `75000` is invalid. The tracked combination is a 120,000-token window and `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "75"`. With the default output budget, Claude reserves 20,000 tokens first: `(120000 - 20000) × 75% = 75000`.

An isolated run of the installed CLI, using these tracked settings and no output-budget override, reported `effective_window: 100000`, `threshold: 75000`, and `enforced: true`. No upstream request was made. This sets a trigger, not a hard transcript-size cap; a turn can cross it before compaction runs. Changing the model, output budget, or `CLAUDE_CODE_AUTO_COMPACT_WINDOW` override can change the calculation. Start a new Claude Code session after editing the source settings.

`~/.claude/settings.json` and `~/.claude.json` are different files:

- `settings.json` is linked config, including the `custom:apollo` theme preference.
- `~/.claude.json` is local state. It holds onboarding, API-key approval, the installer's matching Apollo theme selection, project data, and imported MCP servers.

`install.sh` generates `~/.claude/themes/apollo.json` from the verified canonical Apollo release and preserves every unrelated field when it selects `custom:apollo`. The generated theme is local state, not a Git source.

Do not put the local state file in Git.

## Global instructions

`config/claude/CLAUDE.md` installs as `~/.claude/CLAUDE.md` and sets user-wide response style. Conversational prose is direct and concise by default. Requests for more detail still win, and code, commands, findings, evidence, caveats, safety information, and technical precision stay complete.

## Launch wrappers

`config/zsh/claude.zsh` wraps `claude` and adds:

```text
--permission-mode bypassPermissions
--model gpt-6-astra[1m]
--effort max
```

The binary rejects `permissions.defaultMode: bypassPermissions` in settings. The command-line flag works. The wrapper also pins model and effort because Claude Code can rewrite settings at runtime.

Because `settings.json` is a symlink, CLI-persisted preferences can appear as source changes. Review `git diff -- config/claude/settings.json` before committing, reconcile only the changed keys with the supported settings above, and rerun `scripts/check.sh all`. Do not restore the whole file and lose other intentional edits.

`cc [title]` sets the SonicTerm title, renames the RMUX window when present, and starts Claude Code with the same defaults.

Use `rmux claude` only when Claude Code should create agent-team panes. RMUX gives that process a private tmux-compatible shim. No global tmux shim is installed.

## Agent limit

Claude Code v2.1.217 or later is required.

The native admission value is 16. It is not a hard global ceiling:

- a user-started `/subtask` uses a slot but is not blocked by the same boundary;
- a resumed agent can pass the configured count;
- ultracode is exempt;
- workflow agents and team workers use separate limits.

Do not restore the old lifecycle counter hook.

## Status line

Claude and Copilot status lines share the same five-line shape, locally generated Apollo colors, and five-second per-directory Git cache:

1. time, run time, cost, WakaTime
2. model, effort, context
3. MCP, skills, agents, style
4. current path
5. repo, branch, diff, stash, worktree

Both scripts source the same generated Apollo color include. If it is missing or color is disabled, they remain readable without colors. Claude's custom status line has no live-subagent count or tree because Claude Code has native subagent UI. Copilot keeps the custom rows.

## Plugins

The tracked settings enable:

- `frontend-design@claude-plugins-official`
- `rust-analyzer-lsp@claude-plugins-official`
- `clangd-lsp@claude-plugins-official`
- `claude-code-wakatime@wakatime`

The WakaTime marketplace points to the official `wakatime/claude-code-wakatime` Git repository.

## Common fixes

### Claude asks for onboarding every time

`hasCompletedOnboarding` is missing from local `~/.claude.json`. Complete onboarding once on that Mac.

### The `dummy` key is rejected

The first prompt was answered no. In local `~/.claude.json`, move `dummy` from `customApiKeyResponses.rejected` to `approved`, or complete the approval flow again.

### Small jobs get `model_not_supported`

Keep both Haiku and small-fast aliases set to `gpt-6-astra[1m]`. Also check the relay base URL.

### Relay rewrites settings

`claudeSetup` must be `false` in `config/copilot-relay/config.yaml`. Run `./install.sh` again.

### Relay token expired

```sh
npx copilot-relay auth
./install.sh
```

A deep relay check that exits with code 2 normally needs login again, not a restart.

## Check

```sh
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay" | grep state
curl -fsS http://127.0.0.1:4142/healthz
scripts/check.sh instructions
scripts/check.sh all
```

See [Services and automation](Services-and-Automation.md) for launchd and health checks.
