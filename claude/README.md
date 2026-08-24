# claude/

Symlinked into `~/.claude/`. Bridges Anthropic's
[Claude Code CLI](https://github.com/anthropics/claude-code) to **GitHub
Copilot** models via a local [`copilot-relay`](https://www.npmjs.com/package/copilot-relay)
proxy that translates Anthropic-format requests into Copilot ones.

```
claude (Anthropic CLI) -> http://127.0.0.1:4142 (copilot-relay) -> GitHub Copilot
```

`install.sh` symlinks every top-level file in this folder except `README*`.
That includes `CLAUDE.md`, the tracked user-global instruction source installed
at `~/.claude/CLAUDE.md`; an existing regular file is timestamp-backed up before
the symlink replaces it. This `README.md` stays repository-only.

---

## One-time setup (per machine)

```bash
# 1. Install/update Claude Code (Homebrew cask), copilot-relay, and launchd.
bash ~/Public/dot-configs/install.sh

# 2. GitHub device-code login (browser opens, paste the printed code).
npx copilot-relay auth

# 3. Re-run install.sh so launchd starts the authenticated relay.
bash ~/Public/dot-configs/install.sh
```

After auth, `~/.copilot-relay/github_token` is written and the
proxy can mint Copilot tokens on-demand.

`install.sh` installs Claude Code via `brew install --cask claude-code`
(removing any old npm `@anthropic-ai/claude-code` first), installs/updates
`copilot-relay` via npm, and writes `~/.copilot-relay/config.yaml` with
`claudeSetup: false` so the relay does not rewrite this repo's symlinked
`~/.claude/settings.json`.

## Daily use

```bash
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay" | grep state
claude                                # interactive REPL
claude -p "explain this repo"         # one-shot
```

The `oh-my-zsh-custom/claude.zsh` wrapper launches `claude` with
`--permission-mode bypassPermissions`; model and effort defaults live in
`settings.json`. For agent-team panes, run `rmux claude` explicitly. RMUX adds
Claude's tmux teammate mode and a private process-scoped shim; ordinary
`claude`/`cc` sessions and the system `tmux` command are unchanged.

---

## `settings.json` reference

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:4142",
    "ANTHROPIC_AUTH_TOKEN": "dummy",
    "ANTHROPIC_MODEL": "claude-sonnet-5[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-5[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "Sonnet 5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION": "Sonnet 5 (1M context), routed by copilot-relay to gpt-5.6-sol",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "gpt-5.6-sol[1m]",
    "ANTHROPIC_SMALL_FAST_MODEL": "gpt-5.6-sol[1m]",
    "MODEL_REASONING_EFFORT": "max",
    "CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS": "16"
  },
  "permissions": { "allow": ["*"], "defaultMode": "auto" },
  "model": "claude-sonnet-5[1m]",
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0,
    "refreshInterval": 100
  },
  "effortLevel": "max",
  "theme": "dark-ansi",
  "skipAutoPermissionPrompt": true,
  "skipDangerousModePermissionPrompt": true
}
```

| Key | Purpose |
|---|---|
| `env.ANTHROPIC_BASE_URL` | Points Claude Code at the local proxy instead of `api.anthropic.com`. |
| `env.ANTHROPIC_AUTH_TOKEN` | Required by Claude Code's startup check. `dummy` is fine; real auth happens via `npx copilot-relay auth`. **First launch will prompt** "Use this custom API key? (y/N)" — pick **Yes**, otherwise it lands in `~/.claude.json#customApiKeyResponses.rejected` and Claude refuses to use it. |
| `env.ANTHROPIC_MODEL` | Claude Code-facing default, `claude-sonnet-5[1m]`. The `[1m]` suffix keeps Claude Code's 1M-context accounting; relay maps this non-`opus` request to upstream `gptModel` (`gpt-5.6-sol`). |
| `env.ANTHROPIC_DEFAULT_SONNET_MODEL` | Binds Claude Code's built-in `sonnet` alias and picker row to `claude-sonnet-5[1m]`; relay still sends it through `gptModel`. |
| `env.ANTHROPIC_DEFAULT_SONNET_MODEL_NAME` / `_DESCRIPTION` | Shows the pinned row as **Sonnet 5** in `/model` and discloses its relay destination (`gpt-5.6-sol`). |
| `env.ANTHROPIC_DEFAULT_HAIKU_MODEL` | Routes current Claude Code's Haiku tier, including sub-agents and small-fast side tasks, through `gpt-5.6-sol[1m]`. |
| `env.ANTHROPIC_SMALL_FAST_MODEL` | Legacy small-fast alias for older Claude Code versions; pinned to `gpt-5.6-sol[1m]`. |
| `env.MODEL_REASONING_EFFORT` | Kept for the custom statusline; upstream thinking is controlled by `thinkEffort` in `~/.copilot-relay/config.yaml`. |
| `env.CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | Claude Code's native concurrent-subagent limit, explicitly set to `16` (requires Claude Code v2.1.217+). |
| `effortLevel` | Claude Code's client-side reasoning budget. `low / medium / high / xhigh / max`. |
| `model` | Top-level default; set to `claude-sonnet-5[1m]` so startup and `/model` use the Sonnet 5 picker identity while relay routes it to `gptModel`. |

### Native concurrent-subagent limit

`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=16` uses Claude Code's built-in
per-session admission limit. When 16 subagents are running, another Claude-
spawned `Agent` call fails with `Concurrent subagent limit reached`; launches
work again after the running count drops below 16. `install.sh` requires Claude
Code v2.1.217 or later so this setting cannot be silently ignored.

The native limit is intentionally not described as an absolute ceiling. A
user-started `/subtask` occupies a slot but is not blocked, resuming a finished
subagent can exceed the limit, and ultracode sessions are exempt. Workflow
agents and agent-team teammates use separate limits. The former lifecycle hook,
`jq`-parsed state, and lock files are no longer needed.

### Built-in `/model` menu

Claude Code's `/model` picker owns the available rows, but pinned-model
companion variables can customize a row's display. The default and built-in
`sonnet` alias use `claude-sonnet-5[1m]`; `_NAME="Sonnet 5"` provides the
friendly label and `_DESCRIPTION` states that copilot-relay serves
`gpt-5.6-sol` upstream. Haiku and small-fast also use the GPT relay lane. Real
Opus 5 remains selectable with `/model claude-opus-5[1m]`.

### Relay config

`install.sh` creates or updates `~/.copilot-relay/config.yaml`:

```yaml
host: 127.0.0.1
port: 4142
copilotBaseUrl: https://api.githubcopilot.com
claudeSetup: false
logLevel: info
logRetentionDays: 3
thinkEffort: max
gptModel: gpt-5.6-sol
opusModel: claude-opus-5
```

> **max + 1M context.** The default identity is Claude-facing
> `claude-sonnet-5[1m]`. Because it does not contain `opus`, relay sends it to
> `gptModel: gpt-5.6-sol`; `thinkEffort: max` asks the relay to forward max
> reasoning. The bracketed suffix engages Claude Code's 1M accounting and is
> ignored relay-side. Selecting `claude-opus-5[1m]` instead matches the Opus
> lane and runs upstream `opusModel: claude-opus-5`.

---

## Gotchas hit while setting this up

| Symptom | Root cause | Fix |
|---|---|---|
| `claude` shows the onboarding wizard / OAuth login every launch | `hasCompletedOnboarding` missing in `~/.claude.json` | Set `"hasCompletedOnboarding": true` in `~/.claude.json` (one-time, per machine — `~/.claude.json` is **not** synced via dot-configs because it carries per-machine state like `userID` and project list). |
| Claude refuses to start ("This API key is not approved") | First-launch prompt was answered "No"; `dummy` is in `~/.claude.json#customApiKeyResponses.rejected` | Move `"dummy"` from `rejected` to `approved` in `~/.claude.json#customApiKeyResponses`. |
| `400 model_not_supported` mid-session ("do you have status line?", title generation) | Claude defaults the small-fast model to a model Copilot doesn't expose, or relay routing is bypassed | Keep `ANTHROPIC_DEFAULT_HAIKU_MODEL` and `ANTHROPIC_SMALL_FAST_MODEL` pinned to `gpt-5.6-sol[1m]`, and confirm `ANTHROPIC_BASE_URL` points to `http://127.0.0.1:4142`. |
| `copilot-relay` rewrites `~/.claude/settings.json` | `claudeSetup` is true in `~/.copilot-relay/config.yaml` | Re-run `install.sh`; it sets `claudeSetup: false` and restarts the launchd agent. |
| `settings.json` shows working-tree drift after running `claude` | Claude Code rewrites the file on first launch to inject `theme`, `effortLevel`, etc. | Same caveat as Copilot CLI — selectively `git checkout` runtime-injected fields you don't want to commit. The committed shape is canonical. |

---

## Maintenance

- Stop/restart the proxy: `launchctl kickstart -k "gui/$(id -u)/com.d0n9x1n.copilot-relay"`.
- Inspect listener: `curl -sS -o /dev/null --connect-timeout 1 http://127.0.0.1:4142/healthz && echo "healthy"`.
- Refresh GitHub token: `npx copilot-relay auth` again, then re-run `install.sh`.
- Switch default model: edit top-level `model` in `settings.json`, plus
  `env.ANTHROPIC_MODEL` and `opusModel` / `gptModel` in
  `~/.copilot-relay/config.yaml`.
- Add a new launcher/helper: append to `oh-my-zsh-custom/claude.zsh` and
  `source ~/.zshrc`.

## See also

- Top-level [`ReadMe.md`](../ReadMe.md) — repo-wide layout and `install.sh`
  flow.
- [`oh-my-zsh-custom/claude.zsh`](../oh-my-zsh-custom/claude.zsh) — the
  bypass-permission launcher wrapper.
- [copilot-relay on npm](https://www.npmjs.com/package/copilot-relay) — proxy
  source / flag reference.
- [Claude Code docs](https://docs.claude.com/en/docs/claude-code) —
  Anthropic's CLI reference.
