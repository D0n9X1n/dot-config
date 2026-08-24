---
name: update-settings
description: Change any setting in the dot-configs repo correctly — edit the right file, mirror it to whatever it is coupled to, update QUICKREF.md + ReadMe.md, run scripts/check.sh, then apply it to this Mac via install.sh and reload the affected launchd agents. TRIGGER when the user asks to change, set, enable, disable, or tune configuration for any app this repo manages (Claude Code, Copilot CLI, RMUX, SonicTerm, copilot-relay, launchd agents, zsh), or asks to re-apply/sync settings to the machine. SKIP for questions about what a setting currently is (just read the file), archived tmux/WezTerm reference files, and code changes that are not configuration.
---

# update-settings

Settings in this repo are **coupled**. A one-file edit is usually wrong: the
statusline has a sibling that must match, a model alias has a family rule, a
launchd plist is a template that must be re-rendered, and every behavior change
owes an update to QUICKREF.md. This skill makes the whole change.

Two phases. Run **EDIT** then **APPLY** by default. Run APPLY alone when the
user just wants the repo's current state pushed onto the machine ("re-sync",
"re-run the installer", "my symlinks are stale").

---

## Phase 1 — EDIT

### 1. Route to the right file

Never edit `~/.claude/*`, `~/.rmux.conf`, or another repo-managed path in
`$HOME` directly. Edit the repository source. `~/.wezterm.lua` and
`~/.tmux.conf` are no longer managed; their old sources under `archive/` are
reference-only and must not be treated as active settings.

| Setting | Edit here | Lands at | Coupled to |
| --- | --- | --- | --- |
| Claude Code behavior, env, model | `claude/settings.json` | `~/.claude/settings.json` | model family rule (below) |
| Claude global instructions | `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | `copilot/AGENTS.md` shared workflow guidance |
| Claude statusline | `claude/statusline.sh` | `~/.claude/statusline.sh` | **`copilot/statusline.sh`** |
| Copilot CLI behavior | `copilot/settings.json` | `~/.config/github-copilot/` | — |
| Copilot native global instructions | `copilot/copilot-instructions.md` | `~/.copilot/copilot-instructions.md` | `AGENTS.md` discovery pointer |
| Copilot global workflow guidance | `copilot/AGENTS.md` | `~/.copilot/AGENTS.md` | `custom.zsh` discovery env + `claude/CLAUDE.md` |
| Copilot statusline | `copilot/statusline.sh` | — | **`claude/statusline.sh`** |
| MCP server (no secret) | `mcp-shared.json` | merged into Copilot + `~/.claude.json` | — |
| MCP server (needs token) | `~/.config/github-copilot/mcp.json` | per-device, gitignored | never commit |
| Relay routing / effort | `.copilot-relay/config.yaml` | `~/.copilot-relay/config.yaml` | `claude/settings.json` model names |
| RMUX | `.rmux.conf` | `~/.rmux.conf` | outer-terminal truecolor + shell title wrappers |
| SonicTerm | `.sonicterm/**.toml` | `~/.sonicterm/` | — |
| Shell aliases / wrappers | `oh-my-zsh-custom/*.zsh` | `~/.oh-my-zsh/custom/` | permission-mode flags + RMUX title routing |
| Wiki | flat `wiki/*.md` English/`-zh-CN` pairs | GitHub Wiki via Actions | `_Sidebar.md` + publish workflow |
| launchd agent | `launchd/*.plist` (**template**) | rendered to `~/Library/LaunchAgents/` | must re-render + reload |

### 2. Apply the coupling rule that fits

**Statusline parity.** `claude/statusline.sh` and `copilot/statusline.sh` must
stay functionally aligned: same segments, same output shape, same Gruvbox
palette, same per-cwd 5s git cache. Change one, port it to the other.

One intentional divergence — **do not "re-align" it away**: Claude's statusline
has no live-subagent rendering at all (no inline `subagents`/`Tasks` count, no
bottom live-agent tree, no subagent glyph), because Claude Code ships native
subagent UI and admission. Copilot keeps both, with the magic-wand glyph
(U+F0D0).

**Model routing.** Opus and Sonnet are separate families. Applying "the same
model for the family" means within Opus **or** within Sonnet, never across.
Current startup/default identity: `claude-sonnet-5[1m]`, shown as **Sonnet 5**
in `/model`; because it does not contain `opus`, relay serves upstream
`gptModel: gpt-5.6-sol`. Haiku/small-fast use `gpt-5.6-sol[1m]`. Real Opus 5
remains reachable as `claude-opus-5[1m]`, which relay maps to
`opusModel: claude-opus-5`. Keep `[1m]` on Claude-facing defaults for 1M
context accounting.

**RMUX.** `.rmux.conf` is native RMUX config even though it uses tmux command
syntax. Preserve `TERM_PROGRAM=rmux`, validate on a unique named socket, and do
not add TPM/plugin bootstrap or a global tmux shim. `rmux claude` uses a private,
process-scoped shim for teammate mode.

**Global publishing instructions.** Keep reusable Wiki and commit-derived
release guidance aligned between `claude/CLAUDE.md` and `copilot/AGENTS.md`,
while preserving tool-specific framing. Copilot's documented global entry point
is still `copilot-instructions.md`; `custom.zsh` must append `~/.copilot` to
`COPILOT_CUSTOM_INSTRUCTIONS_DIRS` without dropping or duplicating other paths.
Run `scripts/check.sh instructions`.

**Wiki.** Keep `wiki/` flat. Update English and Simplified Chinese pairs in the
same change, maintain reciprocal links and `_Sidebar.md`, then run
`scripts/check.sh wiki`. `README.md` publishes as `Home.md`; browser edits are
overwritten.

**launchd.** Plists are templates, not symlinks. install.sh substitutes
`__HOME__` → `$HOME` (launchd does not expand `$HOME` at runtime) and
`__SRC_DIR__` → repo path, then `bootout`+`bootstrap` into `gui/<uid>`. Editing
the rendered file in `~/Library/LaunchAgents/` is always wrong — it is
overwritten on next install.

**Statusline layout.** Five lines, `\n` tokens in `SEGMENTS` break lines:
L1 time/run/api/cost · L2 model/effort/context · L3 mcp/skills/agents/style ·
L4 cwd · L5 repo/branch/diff/stash/worktree. Icons are FontAwesome raw UTF-8
bytes (bash 3.2 has no `\u`). Avoid repeating an accent color between adjacent
segments or within a visual column.

### 3. Known traps

- `~/.claude/settings.json` and `~/.claude.json` are **different files**.
  Settings = behavior. `.claude.json` top level = MCP servers + state.
- `refreshInterval` nests **inside** `statusLine`, not at top level.
- `permissions.defaultMode: "bypassPermissions"` is silently rejected by the
  binary. The `--permission-mode bypassPermissions` CLI flag *is* honored —
  that is why `oh-my-zsh-custom/claude.zsh` and `cc.zsh` wrap the launcher.
- `skipDangerousModePermissionPrompt` is dead config; Claude Code re-adds it on
  its own writes. Treat as noise, do not build on it.
- Shell scripts: `set -euo pipefail`, **bash 3.2 compatible** (macOS default) —
  no associative arrays, no `printf '%(...)T'`, no `\u`. Use
  `stat -f %m || stat -c %Y` for mtime.

### 4. Docs, then checks

Behavior changed → **QUICKREF.md** (agent-facing, must stay accurate).
User-visible → **ReadMe.md**. Both if both.

```bash
scripts/check.sh all
```

CI runs the same script. Do not proceed while it is red.

---

## Phase 2 — APPLY

```bash
./install.sh
```

Idempotent: relinks symlinks, re-renders every launchd template, and
`bootout`+`bootstrap`s the agents. Correct links are left alone; mismatched
destinations are backed up as `<name>.bak.YYYYMMDDHHMMSS` first.

Reload a single agent without a full install:

```bash
launchctl kickstart -k "gui/$(id -u)/com.d0n9x1n.copilot-relay"
```

### Verify what you changed

```bash
# active symlinks landed; user-owned legacy paths are allowed
ls -l ~/.claude/settings.json ~/.claude/CLAUDE.md ~/.copilot/AGENTS.md \
  ~/.copilot/copilot-instructions.md ~/.rmux.conf
zsh -lic 'case ",${COPILOT_CUSTOM_INSTRUCTIONS_DIRS:-}," in *,"$HOME/.copilot",*) exit 0 ;; *) exit 1 ;; esac'
repo_root="$(git rev-parse --show-toplevel)"
[ ! -L ~/.tmux.conf ] || [ "$(readlink ~/.tmux.conf)" != "$repo_root/.tmux.conf" ]
[ ! -L ~/.wezterm.lua ] || [ "$(readlink ~/.wezterm.lua)" != "$repo_root/wezterm/wezterm.lua" ]

# agents loaded
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay" | grep state
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay-healthcheck" | grep state

# relay reachable end to end (spends a few tokens)
copilot-relay status --deep; echo "exit=$?"
```

Claude Code settings need a **session restart** to take effect. RMUX reloads
with `prefix + r`; SonicTerm and the relay hot-reload. WezTerm's config is no
longer managed by this repository.

---

## Ship

Semver-ish tags: patch = bugfix, minor = new feature, major = breaking.
Pushing `v*.*.*` triggers `.github/workflows/release.yml`, whose release body
is the commit subjects since the previous reachable tag.

```bash
git tag -a vX.Y.Z -m "..." && git push origin vX.Y.Z
```

If the change closes an issue, attach issue and PR to a milestone named for the
tag. Never `--no-verify` a commit unless the user explicitly asks.

## Never

- Commit a token, key, or `github_token` — the repo is **public**.
- Add an active config path outside the existing linker conventions without an
  install.sh update. `archive/` is inert; `wiki/` is publication-only.
- Commit SonicTerm `logs/`, relay logs, or `copilot_token.json`.
- Add a non-macOS branch. This repo is macOS-only and untested elsewhere.
