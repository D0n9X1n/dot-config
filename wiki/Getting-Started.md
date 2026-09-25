# Getting started

English | [简体中文](Getting-Started-zh-CN.md)

This repo is for macOS. `install.sh` can set up a new Mac. It is safe to run again.

## Install

```sh
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
cd ~/Public/dot-configs
./install.sh
```

The script can install Homebrew, native tmux, Claude Code, Copilot CLI, copilot-relay, shell tools, fonts, and oh-my-zsh. It downloads and verifies the pinned Apollo theme releases, builds local adapters, then links the files listed in `config/manifest.tsv`.

Native tmux and RMUX run side by side with the same Apollo theme and status style. They have separate sessions and state. The native profile targets tmux 3.7, already installed on this Mac.

The first Apollo install needs network access. Later runs can reuse the verified local bundle under `~/.local/share/dot-configs/apollo/`.

The full log is here:

```text
~/Library/Logs/dot-configs-install.log
```

## Connect the relay

Claude Code uses the local copilot-relay service.

Run the one-time browser login:

```sh
npx copilot-relay auth
./install.sh
```

The second install starts the authenticated launchd service.

Check it:

```sh
curl -fsS http://127.0.0.1:4142/healthz >/dev/null && echo "relay healthy"
```

On the first Claude Code launch, approve the custom `dummy` API key. The key is only a local placeholder. The real login is stored by copilot-relay.

If the key was rejected, see [Claude Code](Claude-Code.md).

## Daily commands

```sh
tt main          # exact attach or create native tmux session main
tr main          # interactive shortcut for tt main
tl               # list native tmux sessions; never start a server
td main          # delete exact native tmux session main
th               # native tmux help
rr main          # same as tt main on macOS/Linux; RMUX on Windows
rl               # same as tl on macOS/Linux
rd main          # same as td main on macOS/Linux
claude           # start Claude Code
cc my-project    # start Claude Code with a window title
copilot          # start Copilot CLI
gg my-project    # start Copilot CLI with a window title
```

A new SonicTerm tab stays a normal shell. Neither engine auto-attaches. `tt` refuses to attach inside RMUX; detach first.

`tt`/`tr` start a new tmux server detached and verify parent PID 1 before attaching. Existing servers stay untouched. Closing SonicTerm leaves the server running; no `ts` is needed.

`tr` is only a shell function in interactive zsh. One non-option argument selects a tmux session. Two-argument and option forms use the text utility; `command tr` always selects the utility.

Inside native tmux or RMUX, these actions detach and keep the session alive:

- `exit`
- `logout`
- Ctrl+D at an empty prompt
- `Ctrl+q`, then `d`
- closing the attached SonicTerm tab

Ctrl+D with text keeps normal editing behavior. Outside both engines, shell exit behavior is unchanged.

Use `td <name>` to delete a native tmux session. On macOS and Linux, `rd <name>` does the same; on Windows it deletes an RMUX session. Detach is not a backup: either engine loses its live sessions when its server stops or the Mac reboots. `ts` and `rs` are manual, confirmed all-session restarts that restore only workspace layout as fresh shells. They do not restore running programs or history. Never run them automatically.

See [Tmux](Tmux.md), the [native tmux keymap](Tmux-Keymap.md), [RMUX](RMUX.md), and the [RMUX keymap](RMUX-Keymap.md).

## Update

```sh
cd ~/Public/dot-configs
git pull
./install.sh
```

The installer is idempotent. It keeps correct links. It backs up a different file or link before replacing it. Native tmux migration preserves all earlier tmux backups.

The installer does not reload or stop live tmux or RMUX servers. New servers use the installed config. Reload an existing server only when you choose; see [Tmux](Tmux.md). After changing tracked config, run `scripts/check.sh all`, run `scripts/check.sh apollo-online` if release pins changed, then run `./install.sh` twice.

## Check the repo

```sh
scripts/check.sh all
```

Focused checks:

```sh
scripts/check.sh apollo
scripts/check.sh instructions
scripts/check.sh wiki
scripts/check.sh rmux
scripts/check.sh tmux
```

## Keep local data local

Do not put these in Git:

- API keys or tokens
- `~/.copilot-relay/github_token`
- `copilot_token.json`
- relay or SonicTerm logs
- SonicTerm save locks
- local MCP secrets
- generated Claude state
- downloaded or generated Apollo runtime files
- native tmux and RMUX workspace snapshots or runtime state

Secret MCP entries belong in `~/.config/github-copilot/mcp.json` on each Mac.

Next: [Repository operations](Repository-Operations.md).
