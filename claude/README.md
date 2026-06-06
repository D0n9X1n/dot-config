# claude/

Symlinked into `~/.claude/`. Bridges Anthropic's
[Claude Code CLI](https://github.com/anthropics/claude-code) to **GitHub
Copilot** models via a local [`copilot-relay`](https://www.npmjs.com/package/copilot-relay)
proxy that translates Anthropic-format requests into Copilot ones.

```
claude (Anthropic CLI) -> http://127.0.0.1:4142 (copilot-relay) -> GitHub Copilot
```

`install.sh` only symlinks the **config files** in this folder
(`settings.json`, etc.); this `README.md` is excluded so it doesn't pollute
`~/.claude/`.

---

## One-time setup (per machine)

```bash
# 1. Install Claude Code globally.
npm install -g @anthropic-ai/claude-code

# 2. Install/update copilot-relay and load its launchd agent.
bash ~/Public/dot-configs/install.sh

# 3. GitHub device-code login (browser opens, paste the printed code).
copilot-relay auth
```

After auth, `~/.copilot-relay/github_token` is written and the
proxy can mint Copilot tokens on-demand.

`install.sh` writes `~/.copilot-relay/config.yaml` with
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
`settings.json`.

---

## `settings.json` reference

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:4142",
    "ANTHROPIC_AUTH_TOKEN": "dummy",
    "ANTHROPIC_MODEL": "claude-opus-4-8[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "gpt-5.5[1m]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "gpt-5.5[1m]",
    "ANTHROPIC_SMALL_FAST_MODEL": "gpt-5.5[1m]",
    "MODEL_REASONING_EFFORT": "xhigh"
  },
  "permissions": { "allow": ["*"], "defaultMode": "auto" },
  "model": "claude-opus-4-8[1m]",
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0,
    "refreshInterval": 100
  },
  "effortLevel": "xhigh",
  "theme": "dark-ansi",
  "skipAutoPermissionPrompt": true,
  "skipDangerousModePermissionPrompt": true
}
```

| Key | Purpose |
|---|---|
| `env.ANTHROPIC_BASE_URL` | Points Claude Code at the local proxy instead of `api.anthropic.com`. |
| `env.ANTHROPIC_AUTH_TOKEN` | Required by Claude Code's startup check. `dummy` is fine; real auth happens via `copilot-relay auth`. **First launch will prompt** "Use this custom API key? (y/N)" — pick **Yes**, otherwise it lands in `~/.claude.json#customApiKeyResponses.rejected` and Claude refuses to use it. |
| `env.ANTHROPIC_MODEL` | Claude Code-facing Opus 4.8 default. The `[1m]` suffix is the explicit 1M opt-in (matches the in-app "Opus 1M" picker / binary `Xx3` gate, which keys on the name containing both `opus` and `[1m]`). Relay matches on the `opus` substring, so `claude-opus-4-8[1m]` still maps to upstream `opusModel: claude-opus-4.8` (the `[1m]` suffix is ignored relay-side). |
| `env.ANTHROPIC_DEFAULT_SONNET_MODEL` | Routes every Sonnet alias through Claude-facing `gpt-5.5[1m]`; relay maps it to upstream `gpt-5.5`. |
| `env.ANTHROPIC_DEFAULT_HAIKU_MODEL` | Routes current Claude Code's Haiku tier, including sub-agents and small-fast side tasks, through `gpt-5.5[1m]`. |
| `env.ANTHROPIC_SMALL_FAST_MODEL` | Legacy small-fast alias for older Claude Code versions; pinned to `gpt-5.5[1m]`. |
| `env.MODEL_REASONING_EFFORT` | Kept for the custom statusline; upstream thinking is controlled by `thinkEffort` in `~/.copilot-relay/config.yaml`. |
| `effortLevel` | Claude Code's client-side reasoning budget. `low / medium / high / xhigh`. |
| `model` | Top-level default; set to `claude-opus-4-8[1m]`. Do not use `default` with `copilot-relay`, because relay routes non-`opus` names to `gpt-5.5` (200k context). |

### Built-in `/model` menu

Claude Code's `/model` picker is **hard-coded** to its own lineup
(Default / Sonnet / Sonnet-1M / Haiku / Custom). There is no setting to
hide entries or substitute a custom list. The pragmatic workaround is the
`ANTHROPIC_*_MODEL` env vars above: Sonnet / Haiku / small-fast picks all
route to `gpt-5.5[1m]`, while Opus stays on `claude-opus-4-8[1m]`.

### Relay config

`install.sh` creates or updates `~/.copilot-relay/config.yaml`:

```yaml
host: 127.0.0.1
port: 4142
copilotBaseUrl: https://api.githubcopilot.com
claudeSetup: false
logLevel: info
logRetentionDays: 3
thinkEffort: xhigh
gptModel: gpt-5.5
opusModel: claude-opus-4.8
```

> **xhigh + 1M context.** `claude-opus-4.8` is natively 1M-context on Copilot,
> and `thinkEffort: xhigh` asks the relay to forward max reasoning per
> request. The bracketed `[1m]` suffix lives on the *Claude-facing* name
> (`claude-opus-4-8[1m]`) to engage Claude Code's 1M window; relay ignores
> the suffix and maps to this upstream model unchanged.

---

## Gotchas hit while setting this up

| Symptom | Root cause | Fix |
|---|---|---|
| `claude` shows the onboarding wizard / OAuth login every launch | `hasCompletedOnboarding` missing in `~/.claude.json` | Set `"hasCompletedOnboarding": true` in `~/.claude.json` (one-time, per machine — `~/.claude.json` is **not** synced via dot-configs because it carries per-machine state like `userID` and project list). |
| Claude refuses to start ("This API key is not approved") | First-launch prompt was answered "No"; `dummy` is in `~/.claude.json#customApiKeyResponses.rejected` | Move `"dummy"` from `rejected` to `approved` in `~/.claude.json#customApiKeyResponses`. |
| `400 model_not_supported` mid-session ("do you have status line?", title generation) | Claude defaults the small-fast model to a model Copilot doesn't expose, or relay routing is bypassed | Keep `ANTHROPIC_DEFAULT_HAIKU_MODEL` and `ANTHROPIC_SMALL_FAST_MODEL` pinned to `gpt-5.5[1m]`, and confirm `ANTHROPIC_BASE_URL` points to `http://127.0.0.1:4142`. |
| `copilot-relay` rewrites `~/.claude/settings.json` | `claudeSetup` is true in `~/.copilot-relay/config.yaml` | Re-run `install.sh`; it sets `claudeSetup: false` and restarts the launchd agent. |
| `settings.json` shows working-tree drift after running `claude` | Claude Code rewrites the file on first launch to inject `theme`, `effortLevel`, etc. | Same caveat as Copilot CLI — selectively `git checkout` runtime-injected fields you don't want to commit. The committed shape is canonical. |

---

## Maintenance

- Stop/restart the proxy: `launchctl kickstart -k "gui/$(id -u)/com.d0n9x1n.copilot-relay"`.
- Inspect health: `curl -s http://127.0.0.1:4142/healthz`.
- Refresh GitHub token: `copilot-relay auth` again.
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
