# Getting started

English | [简体中文](Getting-Started-zh-CN.md)

This repo is for macOS. `install.sh` can set up a new Mac. It is safe to run again.

## Install

```sh
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
cd ~/Public/dot-configs
./install.sh
```

The script can install Homebrew, RMUX, Claude Code, Copilot CLI, copilot-relay, shell tools, fonts, and oh-my-zsh. It downloads and verifies the pinned Apollo theme releases, builds local adapters, then links the files listed in `config/manifest.tsv`.

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
rr main          # create or resume RMUX session main
rl               # list RMUX sessions
rd main          # delete RMUX session main
claude           # start Claude Code
cc my-project    # start Claude Code with a window title
copilot          # start Copilot CLI
gg my-project    # start Copilot CLI with a window title
```

A new SonicTerm tab stays a normal shell. It does not join RMUX by itself.

Inside RMUX, these actions detach and keep the session alive:

- `exit`
- `logout`
- Ctrl+D at an empty prompt
- `Ctrl+q`, then `d`
- closing the attached SonicTerm tab

Use `rd <name>` only when you want to delete a session. RMUX stores sessions in memory. A reboot or dead RMUX daemon removes them.

See [RMUX](RMUX.md) and the [full keymap](RMUX-Keymap.md).

## Update

```sh
cd ~/Public/dot-configs
git pull
./install.sh
```

The installer is idempotent. It keeps correct links. It backs up a different file or link before replacing it.

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

Secret MCP entries belong in `~/.config/github-copilot/mcp.json` on each Mac.

Next: [Repository operations](Repository-Operations.md).
