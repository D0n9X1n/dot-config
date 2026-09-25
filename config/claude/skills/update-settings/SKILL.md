---
name: update-settings
description: Change or apply a setting in this dot-configs repo. Use the config manifest, update the matching English and Chinese Wiki pages, run checks, then run install.sh. TRIGGER for changes to Claude Code, Copilot CLI, native tmux, RMUX, SonicTerm, zsh, copilot-relay, MCP, status lines, or launchd. SKIP for read-only questions and retired WezTerm or historical tmux settings in Git history.
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
| Copilot global rules | `config/copilot/copilot-instructions.md` | `~/.copilot/copilot-instructions.md` |
| Copilot status line | `config/copilot/statusline.sh` | `~/.copilot/statusline.sh` |
| RMUX | `config/rmux/rmux.conf` | `~/.rmux.conf` |
| Native tmux | `config/tmux/tmux.conf` | `~/.tmux.conf` |
| Native tmux helpers | `config/zsh/zz-tmux.zsh` + `scripts/tmux/` | zsh custom files, `~/.local/bin/tmux-store`, and `~/.local/lib/tmux-store/` |
| Shared workspace code | `scripts/mux/workspace.py` | `~/.local/lib/mux/workspace.py` |
| SonicTerm | `config/sonicterm/` | `~/.sonicterm/` |
| Zsh | `config/zsh/` | `~/.oh-my-zsh/custom/` |
| Relay | `config/copilot-relay/config.yaml` | `~/.copilot-relay/config.yaml` |
| Safe MCP data | `config/mcp/mcp-shared.json` | merged locally |
| launchd templates | `config/launchd/` | `~/Library/LaunchAgents/` |
| Apollo runtime | `scripts/apollo-releases.tsv` + `scripts/apollo-theme.sh` | `~/.local/share/dot-configs/apollo/` and consumer links |

`config/manifest.tsv` is the tracked-file install list. Add a row when a new managed file is added.

Retired configs stay in Git history. Managed sources must live under `config/` or `scripts/` and be listed in the manifest.

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

- Claude Code defaults to native `claude-opus-5-5[1m]` with `xhigh` effort. Keep settings, `claude`/`cc` launch flags, and the status-line effort fallback aligned.
- Preserve native `claude-sonnet-5[1m]` and `claude-haiku-4-5-20251001` identities; their non-Opus requests route through `gptModel` to `gpt-6-astra`.
- Opus names route to `opusModel`, using upstream `claude-opus-5.5` without a context suffix.
- Relay `thinkEffort` falls back to `xhigh`; explicit client effort wins. Copilot CLI and `gg` retain their separate Astra/`high` defaults.
- Keep `[1m]` on Claude-facing defaults that need one-million-token accounting. The Haiku id takes no suffix.
- Do not put a GPT id, or a `_NAME` / `_DESCRIPTION` display override, into Claude settings.

Do not change both families when the task names one.

### Multiplexers and terminal identity

- Platform rule: Windows uses RMUX; macOS and Linux use native tmux. There, `rr`/`rl`/`rd`/`rh`/`rs` run `tt`/`tl`/`td`/`th`/`ts`, and no `rmux` function exists. Do not add `rmux` back to the macOS installer.
- Read `wiki/Tmux.md` for native tmux and `wiki/RMUX.md` for RMUX. Their configs, sockets, and state stay separate; Apollo theme and status style stay aligned.
- RMUX config uses tmux command syntax but remains native RMUX config. Keep `~/.rmux.conf` separate from the active `~/.tmux.conf`.
- Test each engine with a unique `-L` socket. Never test against a live user server.
- Do not add TPM, plugin bootstrap, or a global tmux shim. Leave old plugins and resurrect data alone; preserve every tmux migration backup.
- SonicTerm uses `TERM_PROGRAM=SonicTerm`; RMUX panes use `TERM_PROGRAM=rmux`; native tmux panes keep `TERM_PROGRAM=tmux`.
- Only Copilot children get the WezTerm compatibility name.
- `cc`/`gg` check RMUX first. Native tmux renames go through `tmux-store` on the current socket, without changing `PATH`. Keep RMUX's private teammate shim unchanged.
- On Windows, `rr` attaches when a session exists and creates only when absent. Keep the Windows `rr`/`rl`/`rd`/`rh`/`rs` RMUX behavior unchanged.
- `tt` and interactive `tr NAME` attach to an exact native session or create it. `tr` sends only one non-option argument there; other forms and `command tr` use the text utility.
- `tt`/`tr` start a new server detached and verify parent PID 1 before attaching. Reuse existing servers without restart or forced reparenting.
- `tt` refuses attachment inside RMUX. Detach first. New tabs never auto-attach.
- The one `exit`/`logout`/Ctrl+D dispatcher checks RMUX first, then native tmux. Empty-prompt Ctrl+D detaches; nonempty Ctrl+D keeps normal ZLE behavior.
- `tl` lists without starting a server. `td` deletes an exact native session; `rd` does the same on macOS/Linux and is RMUX's destructive session command on Windows.
- `ts` needs a stable valid snapshot, compatible binaries, successful preflight, and interactive `yes`. It restarts all sessions on the selected native socket as fresh shells, restoring workspace layout only. No process replay, history, or autosave.
- RMUX retains its client/daemon pair. Native tmux references a compatible Homebrew executable, without binary relocation or a guarantee against arbitrary dependency cleanup.
- Never run `ts` or `rs` automatically or merely to quit SonicTerm. PID 1 does not preserve live processes through crashes or reboot.
- Native tmux 3.7 with `status-keys vi` uses Esc to change prompt mode and `C-g` to cancel. Native tmux does not fix RMUX issue #60.

### launchd

Plists under `config/launchd/` are templates.

`install.sh` replaces `__HOME__` and `__REPO_ROOT__`, writes the local plist, then reloads the job. Do not edit a rendered plist in `~/Library/LaunchAgents/`.

### Global instructions

Keep `config/claude/CLAUDE.md` and `config/copilot/copilot-instructions.md` short. They hold reusable behavior and a conditional pointer to `~/Public/dot-configs`. Changes to managed settings start by reading that folder's own instruction file. Repo-only rules stay in `.claude/CLAUDE.md` and `.github/copilot-instructions.md`.

Copilot automatically loads `~/.copilot/copilot-instructions.md`. Do not add a duplicate global `AGENTS.md` or inject its directory through the shell. Preserve any user-supplied `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` value.

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
scripts/check.sh tmux
```

Run `scripts/check.sh apollo-online` whenever release pins change. Native tmux and RMUX must both pass on macOS CI. Do not continue while checks fail.

## Apply

```sh
./install.sh
./install.sh
```

The second run checks idempotence.

Then verify the changed link or job. Useful checks:

```sh
ls -l ~/.claude/settings.json ~/.copilot/settings.json ~/.rmux.conf ~/.tmux.conf
ls -l ~/.local/bin/tmux-store ~/.local/lib/tmux-store/store.py \
  ~/.local/lib/mux/workspace.py ~/.config/tmux-apollo-theme/apollo.tmux
zsh -ic 'type tt tr tl td th ts rr rd rl rh rs cc gg'
grep -Fq 'term_program = "SonicTerm"' ~/.sonicterm/sonicterm.toml
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay"
```

Claude settings need a new Claude Code session. Installation never reloads or stops live tmux or RMUX servers. New servers read the installed config. Reload an existing server only when explicitly requested; see the engine's Wiki page. Do not use `ts` or `rs` to apply config. SonicTerm and copilot-relay can reload their config.

## Never

- Never commit a token, key, auth file, log, or runtime state.
- Secret MCP data stays in `~/.config/github-copilot/mcp.json`.
- Relay auth stays under `~/.copilot-relay/`.
- Do not add SonicTerm save locks or `.claude/worktrees/`.
- Do not use `--no-verify` unless the user asks.
