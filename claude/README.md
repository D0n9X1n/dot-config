# claude/

Symlinked into `~/.claude/`. Bridges Anthropic's
[Claude Code CLI](https://github.com/anthropics/claude-code) to **GitHub
Copilot** models via a local [`betahi-copilot-bridge`](https://www.npmjs.com/package/betahi-copilot-bridge)
proxy that translates Anthropic-format requests into Copilot ones.

```
claude (Anthropic CLI) → http://127.0.0.1:4142 (copilot-bridge) → GitHub Copilot
```

`install.sh` only symlinks the **config files** in this folder
(`settings.json`, etc.); this `README.md` is excluded so it doesn't pollute
`~/.claude/`.

---

## One-time setup (per machine)

```bash
# 1. Install both npm packages globally.
npm install -g @anthropic-ai/claude-code betahi-copilot-bridge

# 2. GitHub device-code login (browser opens, paste the printed code).
copilot-bridge auth
```

After auth, `~/.local/share/copilot-bridge/github_token` is written and the
proxy can mint Copilot tokens on-demand.

> **`copilot-bridge start --no-claude-setup --no-codex-setup` is broken without a TTY.** That flag
> opens an interactive model picker and crashes (`uv_tty_init returned
> EINVAL`) when launched headless / detached. Use plain `copilot-bridge start
> --port 4142` — the model is already pinned in `settings.json`, so the
> picker is unnecessary.

## Daily use

```bash
copilot-bridge start --port 4142 &     # leave running (or in a tmux pane)
claude                              # interactive REPL
claude -p "explain this repo"       # one-shot
```

Two pinned aliases live in `oh-my-zsh-custom/claude.zsh`:

```bash
claude-opus    # claude --model claude-opus-4.7-[1m]
claude-gpt     # claude --model gpt-5.5
```

---

## `settings.json` reference

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:4142",
    "ANTHROPIC_AUTH_TOKEN": "dummy",
    "ANTHROPIC_MODEL": "claude-opus-4.7-[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "gpt-5.5",
    "ANTHROPIC_SMALL_FAST_MODEL": "gpt-5.5",
    "MODEL_REASONING_EFFORT": "xhigh"
  },
  "permissions": { "allow": ["*"], "defaultMode": "auto" },
  "model": "claude-opus-4.7-[1m]",
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
| `env.ANTHROPIC_AUTH_TOKEN` | Required by Claude Code's startup check. copilot-bridge expects the token form (not `ANTHROPIC_API_KEY`) and ignores its value — `dummy` is fine. **First launch will prompt** "Use this custom API key? (y/N)" — pick **Yes**, otherwise it lands in `~/.claude.json#customApiKeyResponses.rejected` and Claude refuses to use it. |
| `env.ANTHROPIC_MODEL` | Default model for main turns. The bracket form `claude-opus-4.7-[1m]` is Claude Code's UI-friendly variant; copilot-bridge maps it to `claude-opus-4.7-1m` upstream. Overridden by top-level `model` and `--model`. |
| `env.ANTHROPIC_DEFAULT_SONNET_MODEL` | Routes every Sonnet alias (Sonnet 4-5 / 4-6 / Sonnet-1M) to a Copilot model. Pinned to `gpt-5.5` so Sonnet picks land on a mid-tier model rather than full Opus. |
| `env.ANTHROPIC_DEFAULT_HAIKU_MODEL` | Routes every Haiku alias (and any sub-agent spawned with `model: "haiku"`) to a Copilot model. Pinned to `gpt-5.5`. **This is the variable current Claude Code reads** — the legacy `ANTHROPIC_SMALL_FAST_MODEL` is silently ignored by recent versions, so haiku sub-agents would otherwise leak to upstream `claude-haiku-4-5-20251001`. |
| `env.ANTHROPIC_SMALL_FAST_MODEL` | Legacy alias for the same Haiku/small-fast tier. Kept for older Claude Code versions; current versions prefer `ANTHROPIC_DEFAULT_HAIKU_MODEL`. Pinning to `gpt-5.5` silences `400 model_not_supported` either way. |
| `env.MODEL_REASONING_EFFORT` | Read by copilot-bridge per-request and forwarded to Copilot as the reasoning budget. Mirrors the client-side `effortLevel`. |
| `effortLevel` | Claude Code's client-side reasoning budget. `low / medium / high / xhigh`. |
| `model` | Top-level default; takes precedence over `env.ANTHROPIC_MODEL`. |

### Built-in `/model` menu

Claude Code's `/model` picker is **hard-coded** to its own lineup
(Default / Sonnet / Sonnet-1M / Haiku / Custom). There is no setting to
hide entries or substitute a custom list. The pragmatic workaround is
the two `ANTHROPIC_*_MODEL` env vars above: every menu pick still
appears, but each Sonnet / Haiku entry routes to `gpt-5.5` while every
Opus entry resolves to the top-level `model` (`claude-opus-4.7-[1m]`),
giving you exactly two effective models. (Older revisions of this config
used a `modelOverrides` map for the same purpose; the env-var route is
simpler and works without the proxy maintaining its own routing table.)

### Available Copilot models

Run `copilot-bridge start --port 4142` once and check the startup log — it
prints every model your account exposes. As of this writing:

```
claude-opus-4.7, claude-opus-4.7-high, claude-opus-4.7-xhigh,
claude-opus-4.7-1m, claude-opus-4.6, claude-opus-4.6-1m,
claude-sonnet-4.6, claude-sonnet-4.5, claude-haiku-4.5,
gpt-5.5, gpt-5.4, gpt-5.4-mini, gpt-5.3-codex, gpt-5.2, gpt-5.2-codex,
gpt-5-mini, gpt-4.1, gpt-4o, gemini-3.1-pro-preview, gemini-2.5-pro, …
```

> **xhigh ⊕ 1M context.** Copilot exposes either `claude-opus-4.7-xhigh`
> (default 200k context, max effort) **or** `claude-opus-4.7-1m` (1M
> context, default effort). There is **no** `*-1m-xhigh` combo, so pick
> one. Current default is the 1M variant (`claude-opus-4.7-[1m]`) plus
> `MODEL_REASONING_EFFORT=xhigh`, which the bridge forwards per-request.

---

## Gotchas hit while setting this up

| Symptom | Root cause | Fix |
|---|---|---|
| `claude` shows the onboarding wizard / OAuth login every launch | `hasCompletedOnboarding` missing in `~/.claude.json` | Set `"hasCompletedOnboarding": true` in `~/.claude.json` (one-time, per machine — `~/.claude.json` is **not** synced via dot-configs because it carries per-machine state like `userID` and project list). |
| Claude refuses to start ("This API key is not approved") | First-launch prompt was answered "No"; `dummy` is in `~/.claude.json#customApiKeyResponses.rejected` | Move `"dummy"` from `rejected` to `approved` in `~/.claude.json#customApiKeyResponses`. |
| `400 model_not_supported` mid-session ("do you have status line?", title generation) | Claude defaults the small-fast model to `claude-haiku-4-5`, which Copilot doesn't expose | Set both `env.ANTHROPIC_DEFAULT_HAIKU_MODEL` **and** `env.ANTHROPIC_SMALL_FAST_MODEL` to a Copilot model (e.g. `gpt-5.5`). Current Claude Code reads `*_DEFAULT_HAIKU_MODEL`; older versions read `*_SMALL_FAST_MODEL`. |
| `copilot-bridge start --no-claude-setup --no-codex-setup` crashes with `uv_tty_init returned EINVAL` | The `--claude-code` flag opens an interactive model picker; needs a TTY | Use `copilot-bridge start --port 4142` instead. |
| `settings.json` shows working-tree drift after running `claude` | Claude Code rewrites the file on first launch to inject `theme`, `effortLevel`, etc. | Same caveat as Copilot CLI — selectively `git checkout` runtime-injected fields you don't want to commit. The committed shape is canonical. |

---

## Maintenance

- Stop the proxy: `kill <PID>` (find it with `lsof -nP -iTCP:4141 -sTCP:LISTEN`).
- Inspect quota: `copilot-bridge check-usage`.
- Refresh GitHub token: `copilot-bridge auth` again.
- Switch default model: edit `model` + `env.ANTHROPIC_MODEL` in
  `settings.json` (this folder); takes effect on next `claude` launch
  (no `install.sh` re-run needed — it's a symlink).
- Add a new alias: append to `oh-my-zsh-custom/claude.zsh` and `source ~/.zshrc`.

## See also

- Top-level [`ReadMe.md`](../ReadMe.md) — repo-wide layout and `install.sh`
  flow.
- [`oh-my-zsh-custom/claude.zsh`](../oh-my-zsh-custom/claude.zsh) — the
  `claude-opus` / `claude-gpt` launcher aliases.
- [copilot-bridge on npm](https://www.npmjs.com/package/betahi-copilot-bridge) — proxy
  source / flag reference.
- [Claude Code docs](https://docs.claude.com/en/docs/claude-code) —
  Anthropic's CLI reference.
