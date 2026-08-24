# dot-config Wiki

English | [简体中文](Home-zh-CN.md)

This Wiki documents the macOS dotfiles in [D0n9X1n/dot-config](https://github.com/D0n9X1n/dot-config). The repository's `wiki/` directory is the source of truth; browser edits are overwritten by the next publication from `main`.

## Start here

- [RMUX](RMUX.md) — terminal multiplexer architecture, configuration, keybindings, Claude teammate mode, security, and verification.
- [Archived tmux configuration](Archive-Tmux.md) — retired TPM-based setup and rollback notes.
- [Archived WezTerm configuration](Archive-WezTerm.md) — retired Lua profile and remaining compatibility-name rationale.

## Repository model

- `install.sh` bootstraps a macOS machine and creates symlinks into the home directory.
- `.rmux.conf` is the active multiplexer profile and lands at `~/.rmux.conf`.
- SonicTerm is the actively managed outer terminal; tmux and WezTerm are not installed by this repository.
- `archive/` contains inert historical configuration and is never linked.
- `QUICKREF.md` remains the agent-facing operational source of truth; `ReadMe.md` is the complete human-facing repository guide.

## Quick start

```sh
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
bash ~/Public/dot-configs/install.sh
rmux
```

Run `scripts/check.sh all` before shipping a change. See the repository README for authentication and application-specific setup.
