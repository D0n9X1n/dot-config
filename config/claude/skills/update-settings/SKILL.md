---
name: update-settings
description: Change or apply a setting in this dot-configs repo. Use the config manifest, update the matching English and Chinese Wiki pages, run checks, then run install.sh. TRIGGER for changes to Claude Code, Copilot CLI, RMUX, SonicTerm, zsh, copilot-relay, MCP, status lines, or launchd. SKIP for read-only questions and archived tmux or WezTerm files.
---

# Update settings

The Wiki is the full source of truth. Read `wiki/README.md` and the page for the tool first.

## Edit the source

Never edit a managed file under `$HOME`.

| Tool | Source | Installed path |
|---|---|---|
| Claude settings | `config/claude/settings.json` | `~/.claude/settings.json` |
| Claude global rules | `config/claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| Claude status line | `config/claude/statusline.sh` | `~/.claude/statusline.sh` |
| Claude skills | `config/claude/skills/` | `~/.claude/skills/` |
| Copilot settings | `config/copilot/settings.json` | `~/.copilot/settings.json` |
| Copilot global rules | `config/copilot/AGENTS.md` and `copilot-instructions.md` | `~/.copilot/` |
| Copilot status line | `config/copilot/statusline.sh` | `~/.copilot/statusline.sh` |
| RMUX | `config/rmux/rmux.conf` | `~/.rmux.conf` |
| SonicTerm | `config/sonicterm/` | `~/.sonicterm/` |
| Zsh | `config/zsh/` | `~/.oh-my-zsh/custom/` |
| Relay | `config/copilot-relay/config.yaml` | `~/.copilot-relay/config.yaml` |
| Safe MCP data | `config/mcp/mcp-shared.json` | merged locally |
| launchd templates | `config/launchd/` | `~/Library/LaunchAgents/` |
| Apollo runtime | `scripts/apollo-releases.tsv` + `scripts/apollo-theme.sh` | `~/.local/share/dot-configs/apollo/` and consumer links |

`config/manifest.tsv` is the tracked-file install list. Add a row when a new managed file is added.

Never make a file under `archive/` active.

## Keep linked behavior together

### Status lines

Keep these files functionally aligned:

```text
config/claude/statusline.sh
config/copilot/statusline.sh
```

They share the same five-line shape, generated Apollo colors, and five-second per-directory Git cache.

Keep provider metrics different: Claude shows cost; Copilot shows premium requests. Copilot also shows custom live-subagent count and rows. Claude does not because Claude Code has native agent UI.

### Models

Sonnet and Opus are separate families.

- Claude Code keeps native client ids: `claude-sonnet-5[1m]` and `claude-haiku-4-5-20251001`.
- Sonnet-facing names route through `gptModel` to `gpt-6-astra`.
- Opus names route to `opusModel` and stay `claude-opus-5`.
- Keep `[1m]` on Claude-facing defaults that need one-million-token accounting. The Haiku id takes no suffix.
- Do not put a GPT id, or a `_NAME` / `_DESCRIPTION` display override, into Claude settings.

Do not change both families when the task names one.

### RMUX and terminal identity

- RMUX config uses tmux command syntax but is native RMUX config.
- Test with a unique `-L` socket.
- Do not add TPM or a global tmux shim.
- SonicTerm uses `TERM_PROGRAM=SonicTerm`.
- RMUX panes use `TERM_PROGRAM=rmux`.
- Only Copilot children get the WezTerm compatibility name.
- `rr` attaches when a session exists and creates only when absent.
- New tabs never auto-attach.
- In RMUX, `exit`, `logout`, and empty-prompt Ctrl+D detach.
- `rd` is the destructive session command.

### launchd

Plists under `config/launchd/` are templates.

`install.sh` replaces `__HOME__` and `__REPO_ROOT__`, writes the local plist, then reloads the job. Do not edit a rendered plist in `~/Library/LaunchAgents/`.

### Global instructions

Keep `config/claude/CLAUDE.md`, `config/copilot/AGENTS.md`, and `config/copilot/copilot-instructions.md` short. They hold reusable behavior plus one conditional pointer: these settings are synced from `~/Public/dot-configs`, and a change to them starts by reading that folder's own instruction file. Repo-only rules stay in this repo's `.claude/CLAUDE.md` and `.github/copilot-instructions.md`, so an unrelated project never loads them.

Copilot's native entry file is `config/copilot/copilot-instructions.md`. It names `~/.copilot/AGENTS.md` by absolute path and repeats the settings-source pointer, because Copilot does not reliably inline the global `AGENTS.md`. `config/zsh/custom.zsh` keeps `~/.copilot` in `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`; that wiring is asserted by `scripts/check.sh instructions`, not repeated in the instruction text.

## Update help

Update the matching English and `-zh-CN` Wiki pages in the same change.

Keep `wiki/` flat. Update `_Sidebar.md` for a new or renamed page. Use source links that end in `.md`. Do not use cross-page `.md#anchor` links.

Keep `ReadMe.md` short. Change it only when the quick start or top-level summary changes.

## Check

```sh
scripts/check.sh all
```

Use a focused check while editing:

```sh
scripts/check.sh apollo
scripts/check.sh instructions
scripts/check.sh wiki
scripts/check.sh rmux
```

Do not continue while checks fail.

## Apply

```sh
./install.sh
./install.sh
```

The second run checks idempotence.

Then verify the changed link or job. Useful checks:

```sh
ls -l ~/.claude/settings.json ~/.copilot/settings.json ~/.rmux.conf
zsh -ic 'type rr rd rl cc gg'
grep -Fq 'term_program = "SonicTerm"' ~/.sonicterm/sonicterm.toml
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay"
```

Claude settings need a new Claude Code session. RMUX reloads with `prefix + r`. SonicTerm and copilot-relay can reload their config.

## Never

- Never commit a token, key, auth file, log, or runtime state.
- Secret MCP data stays in `~/.config/github-copilot/mcp.json`.
- Relay auth stays under `~/.copilot-relay/`.
- Do not add SonicTerm save locks or `.claude/worktrees/`.
- Do not use `--no-verify` unless the user asks.
