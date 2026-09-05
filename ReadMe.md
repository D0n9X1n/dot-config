# dot-configs

[![CI](https://github.com/D0n9X1n/dot-config/actions/workflows/ci.yml/badge.svg)](https://github.com/D0n9X1n/dot-config/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/D0n9X1n/dot-config?sort=semver&color=fe8019)](https://github.com/D0n9X1n/dot-config/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS-1d2021?logo=apple&logoColor=ebdbb2)](#)
[![License](https://img.shields.io/github/license/D0n9X1n/dot-config?color=b8bb26)](./LICENSE)

My macOS config for RMUX, SonicTerm, zsh, Claude Code, and GitHub Copilot CLI.

## Folders

```text
config/   config used now
scripts/  code and release pins
wiki/     full help
```

`install.sh` links tracked files from `config/manifest.tsv` and installs verified Apollo runtime assets.

## Install

```sh
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
cd ~/Public/dot-configs
./install.sh
npx copilot-relay auth
./install.sh
```

The installer is for macOS. It is safe to run again.

## Daily use

```sh
rr main          # create or resume RMUX session main
rl               # list RMUX sessions
rd main          # delete RMUX session main
claude           # start Claude Code
cc my-project    # Claude Code with a title
copilot          # start Copilot CLI
gg my-project    # Copilot with a title and full tool/path access
```

New SonicTerm tabs stay as normal shells.

Inside RMUX, `exit`, `logout`, empty-prompt Ctrl+D, `Ctrl+q` then `d`, and closing the tab all detach. They keep the session alive while the RMUX daemon runs.

## Check

```sh
scripts/check.sh all
```

## Full help

Read the [GitHub Wiki](https://github.com/D0n9X1n/dot-config/wiki).

The reviewable source is in `wiki/`. It has English and Simplified Chinese pages.

A new `vX.Y.Z` tag makes a GitHub Release. The Wiki has the full release steps.

Start with:

- [Getting started](wiki/Getting-Started.md)
- [Repository operations](wiki/Repository-Operations.md)
- [RMUX](wiki/RMUX.md)
- [Claude Code](wiki/Claude-Code.md)
- [Copilot CLI](wiki/Copilot-CLI.md)

## Safety

This repo is public. Do not add tokens, keys, auth files, logs, or runtime state.

Local MCP secrets stay in `~/.config/github-copilot/mcp.json`.

## License

See [LICENSE](LICENSE).
