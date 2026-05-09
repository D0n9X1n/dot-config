# claude/

Symlinked into `~/.claude/`. Bridges Anthropic's
[Claude Code CLI](https://github.com/anthropics/claude-code) to **GitHub
Copilot** models via a local [`copilot-api`](https://www.npmjs.com/package/copilot-api)
proxy that translates Anthropic-format requests into Copilot ones.

```
claude (Anthropic CLI) → http://localhost:4141 (copilot-api) → GitHub Copilot
```

`install.sh` only symlinks the **config files** in this folder
(`settings.json`, etc.); this `README.md` is excluded so it doesn't pollute
`~/.claude/`.

---

## One-time setup (per machine)

```bash
# 1. Install both npm packages globally.
npm install -g @anthropic-ai/claude-code copilot-api

# 2. GitHub device-code login (browser opens, paste the printed code).
copilot-api auth
```

After auth, `~/.local/share/copilot-api/github_token` is written and the
proxy can mint Copilot tokens on-demand.

> **`copilot-api start --claude-code` is broken without a TTY.** That flag
> opens an interactive model picker and crashes (`uv_tty_init returned
> EINVAL`) when launched headless / detached. Use plain `copilot-api start
> --port 4141` — the model is already pinned in `settings.json`, so the
> picker is unnecessary.

## Daily use

```bash
copilot-api start --port 4141 &     # leave running (or in a tmux pane)
claude                              # interactive REPL
claude -p "explain this repo"       # one-shot
```

Two pinned aliases live in `oh-my-zsh-custom/claude.zsh`:

```bash
claude-opus    # claude --model claude-opus-4.7-xhigh
claude-gpt     # claude --model gpt-5.5
```

---

## `settings.json` reference

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:4141",
    "ANTHROPIC_MODEL": "claude-opus-4.7-xhigh",
    "ANTHROPIC_SMALL_FAST_MODEL": "gpt-5.5",
    "ANTHROPIC_API_KEY": "dummy"
  },
  "effortLevel": "xhigh",
  "model": "claude-opus-4.7-xhigh",
  "modelOverrides": { … }
}
```

| Key | Purpose |
|---|---|
| `env.ANTHROPIC_BASE_URL` | Points Claude Code at the local proxy instead of `api.anthropic.com`. |
| `env.ANTHROPIC_MODEL` | Default Copilot model for main turns. Overridden by `model` and `--model`. |
| `env.ANTHROPIC_SMALL_FAST_MODEL` | Used for side-tasks (titles, summaries, conversation compaction, sub-agents). Defaults to `claude-haiku-4-5` which **Copilot does not expose** — pinning to a real model is required to silence `400 model_not_supported`. |
| `env.ANTHROPIC_API_KEY` | Required by Claude Code's startup check. The proxy ignores its value — `dummy` is fine. **First launch will prompt** "Use this custom API key? (y/N)" — pick **Yes**, otherwise it lands in `~/.claude.json#customApiKeyResponses.rejected` and Claude refuses to use it. |
| `effortLevel` | Claude Code's client-side reasoning budget. `low / medium / high / xhigh`. |
| `model` | Top-level default; takes precedence over `env.ANTHROPIC_MODEL`. |
| `modelOverrides` | Maps Anthropic-side model IDs → Copilot model IDs. Lets you redirect every entry in the built-in `/model` picker (Sonnet, Sonnet-1M, Haiku, Opus, custom rows) to whatever Copilot model you actually want. Originally designed for Bedrock ARN remapping but works with any string. |

### Built-in `/model` menu

Claude Code's `/model` picker is **hard-coded** to its own lineup
(Default / Sonnet / Sonnet-1M / Haiku / Custom). There is no setting to
hide entries or substitute a custom list. The pragmatic workaround is
`modelOverrides`: every menu pick still appears, but each one routes to a
Copilot model you choose. The current config redirects every Anthropic
entry to `claude-opus-4.7-xhigh` and the custom `gpt-5-mini` row to
`gpt-5.5`, giving you exactly two effective models.

### Available Copilot models

Run `copilot-api start --port 4141` once and check the startup log — it
prints every model your account exposes. As of this writing:

```
claude-opus-4.7, claude-opus-4.7-high, claude-opus-4.7-xhigh,
claude-opus-4.7-1m-internal, claude-opus-4.6, claude-opus-4.6-1m,
claude-sonnet-4.6, claude-sonnet-4.5, claude-haiku-4.5,
gpt-5.5, gpt-5.4, gpt-5.4-mini, gpt-5.3-codex, gpt-5.2, gpt-5.2-codex,
gpt-5-mini, gpt-4.1, gpt-4o, gemini-3.1-pro-preview, gemini-2.5-pro, …
```

> **xhigh ⊕ 1M context.** Copilot exposes either `claude-opus-4.7-xhigh`
> (default 200k context, max effort) **or** `claude-opus-4.7-1m-internal`
> (1M context, default effort). There is **no** `*-1m-xhigh` combo, so
> pick one. Current default favors xhigh.

---

## Gotchas hit while setting this up

| Symptom | Root cause | Fix |
|---|---|---|
| `claude` shows the onboarding wizard / OAuth login every launch | `hasCompletedOnboarding` missing in `~/.claude.json` | Set `"hasCompletedOnboarding": true` in `~/.claude.json` (one-time, per machine — `~/.claude.json` is **not** synced via dot-configs because it carries per-machine state like `userID` and project list). |
| Claude refuses to start ("This API key is not approved") | First-launch prompt was answered "No"; `dummy` is in `~/.claude.json#customApiKeyResponses.rejected` | Move `"dummy"` from `rejected` to `approved` in `~/.claude.json#customApiKeyResponses`. |
| `400 model_not_supported` mid-session ("do you have status line?", title generation) | Claude defaults the small-fast model to `claude-haiku-4-5`, which Copilot doesn't expose | Set `env.ANTHROPIC_SMALL_FAST_MODEL` to a Copilot model (e.g. `gpt-5.5`). |
| `copilot-api start --claude-code` crashes with `uv_tty_init returned EINVAL` | The `--claude-code` flag opens an interactive model picker; needs a TTY | Use `copilot-api start --port 4141` instead. |
| `settings.json` shows working-tree drift after running `claude` | Claude Code rewrites the file on first launch to inject `theme`, `effortLevel`, etc. | Same caveat as Copilot CLI — selectively `git checkout` runtime-injected fields you don't want to commit. The committed shape is canonical. |

---

## Maintenance

- Stop the proxy: `kill <PID>` (find it with `lsof -nP -iTCP:4141 -sTCP:LISTEN`).
- Inspect quota: `copilot-api check-usage`.
- Refresh GitHub token: `copilot-api auth` again.
- Switch default model: edit `model` + `env.ANTHROPIC_MODEL` in
  `settings.json` (this folder); takes effect on next `claude` launch
  (no `install.sh` re-run needed — it's a symlink).
- Add a new alias: append to `oh-my-zsh-custom/claude.zsh` and `source ~/.zshrc`.

## See also

- Top-level [`ReadMe.md`](../ReadMe.md) — repo-wide layout and `install.sh`
  flow.
- [`oh-my-zsh-custom/claude.zsh`](../oh-my-zsh-custom/claude.zsh) — the
  `claude-opus` / `claude-gpt` launcher aliases.
- [copilot-api on npm](https://www.npmjs.com/package/copilot-api) — proxy
  source / flag reference.
- [Claude Code docs](https://docs.claude.com/en/docs/claude-code) —
  Anthropic's CLI reference.
