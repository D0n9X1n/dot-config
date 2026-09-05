# dot-config Wiki

English | [简体中文](Home-zh-CN.md)

This Wiki is the full guide for this repository.

The source is the flat `wiki/` folder. GitHub Actions publishes it to the GitHub Wiki. A browser edit will be replaced by the next publish from `main`.

## Start

- [Getting started](Getting-Started.md) — install the files and run the main tools.
- [Repository operations](Repository-Operations.md) — learn the folders, manifest, links, and safe update flow.

## Tools

- [Claude Code](Claude-Code.md) — relay setup, models, settings, agents, and fixes.
- [Copilot CLI](Copilot-CLI.md) — model defaults, global rules, status line, and WakaTime.
- [RMUX](RMUX.md) — sessions, panes, resume, clipboard, and Claude teams.
- [RMUX keymap](RMUX-Keymap.md) — all 278 active bindings.
- [SonicTerm and shell](SonicTerm-and-Shell.md) — terminal files, zsh helpers, and launch wrappers.

## Work

- [Services and automation](Services-and-Automation.md) — installer jobs, relay health, MCP, WakaTime, and cache cleanup.
- [Development and releases](Development-and-Releases.md) — checks, Wiki publish, issues, tags, and releases.
- [Apollo theme](Apollo-Theme.md) — pinned upstream releases and local runtime adapters.

## Main folders

| Folder | Meaning |
|---|---|
| `config/` | Config used now |
| `scripts/` | Code that runs and external release pins |
| `wiki/` | Full help |

`install.sh` stays at the root. It links tracked files from `config/manifest.tsv` and installs verified Apollo runtime assets.

## Quick start

```sh
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
cd ~/Public/dot-configs
./install.sh
npx copilot-relay auth
./install.sh
```

Run `scripts/check.sh all` before a push.

This is a public repository. Never add tokens, keys, auth files, logs, or runtime state.
