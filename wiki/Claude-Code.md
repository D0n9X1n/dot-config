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
Claude-facing name: claude-sonnet-5[1m]
Picker name:        Sonnet 5
Client effort:      max
Relay route:        gptModel
Upstream model:     gpt-5.6-sol
```

The name has no `opus`, so copilot-relay sends it to `gptModel`.

Other routes:

| Claude-facing name | Relay lane | Upstream |
|---|---|---|
| `claude-opus-5[1m]` | `opusModel` | `claude-opus-5` |
| Haiku / small-fast aliases | `gptModel` | `gpt-5.6-sol` |

The `[1m]` suffix keeps Claude Code's one-million-token context accounting. Relay-side thinking is `max` in `config/copilot-relay/config.yaml`.

Sonnet and Opus are separate families. Do not change both when a task asks to update one family.

## Main settings

`config/claude/settings.json` sets:

| Key | Value or job |
|---|---|
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:4142` |
| `ANTHROPIC_AUTH_TOKEN` | local placeholder `dummy` |
| `ANTHROPIC_MODEL` | `claude-sonnet-5[1m]` |
| `effortLevel` | `max` |
| `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | `16` |
| `statusLine.refreshInterval` | `100` |
| `theme` | `dark-ansi` |
| `autoCompactWindow` | `800000` |

`refreshInterval` belongs inside `statusLine`.

`~/.claude/settings.json` and `~/.claude.json` are different files:

- `settings.json` is linked config.
- `~/.claude.json` is local state. It holds onboarding, API-key approval, project data, and imported MCP servers.

Do not put the local state file in Git.

## Launch wrappers

`config/zsh/claude.zsh` wraps `claude` and adds:

```text
--permission-mode bypassPermissions
--model claude-sonnet-5[1m]
--effort max
```

The binary rejects `permissions.defaultMode: bypassPermissions` in settings. The command-line flag works. The wrapper also pins model and effort because Claude Code can rewrite settings at runtime.

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

Claude and Copilot status lines share the same five-line shape, Gruvbox colors, and five-second per-directory Git cache:

1. time, run time, cost, WakaTime
2. model, effort, context
3. MCP, skills, agents, style
4. current path
5. repo, branch, diff, stash, worktree

Claude's custom status line has no live-subagent count or tree. Claude Code has native subagent UI. Copilot keeps the custom rows.

## Plugins

The tracked settings enable:

- `frontend-design@claude-plugins-official`
- `rust-analyzer-lsp@claude-plugins-official`
- `claude-code-wakatime@wakatime`

The WakaTime marketplace points to the official `wakatime/claude-code-wakatime` Git repository.

## Common fixes

### Claude asks for onboarding every time

`hasCompletedOnboarding` is missing from local `~/.claude.json`. Complete onboarding once on that Mac.

### The `dummy` key is rejected

The first prompt was answered no. In local `~/.claude.json`, move `dummy` from `customApiKeyResponses.rejected` to `approved`, or complete the approval flow again.

### Small jobs get `model_not_supported`

Keep both Haiku and small-fast aliases set to `gpt-5.6-sol[1m]`. Also check the relay base URL.

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
