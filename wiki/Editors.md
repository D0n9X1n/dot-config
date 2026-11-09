# Editors

English | [简体中文](Editors-zh-CN.md)

This repo syncs the Zed and Neovide settings. Neovim itself lives in the separate `nvim-config` repo; this repo never changes it.

## Zed

`config/zed/settings.json` links to `~/.config/zed/settings.json`. It holds the theme, icon theme, fonts, Vim mode, and agent servers. A new window opens with an empty tab.

Zed writes setting changes through the link, so a change made in Zed shows up in this repo as a Git change. Commit it, or drop it with `git checkout`.

Not synced: `~/.config/zed/themes/`, which is empty, and `~/.config/zed/prompts/`, which is Zed's local prompt database.

## Neovide

`config/neovide/config.toml` links to `~/.config/neovide/config.toml`. It sets only `fork = true`, so `neovide` started from a shell returns the prompt right away.

Fonts and other GUI options such as `guifont` are Neovim settings, so they stay in `nvim-config`.

## `nv`

`config/zsh/nv.zsh` adds `nv`. It opens files in one shared Neovide window:

```sh
nv main.cc            # open a file
nv main.cc:42         # open at line 42
nv main.cc:42:7       # column is ignored
nv a.cc b.cc          # open several files
nv                    # bring the window forward
```

The first call starts an empty Neovide with `open -n -a Neovide`, in the current folder, with Neovim listening on a fixed socket. It waits up to 10 seconds for that socket. Every call then sends the files to the window with `nvim --server --remote-send` and brings it forward. When the window is closed, the next call starts a new one.

Neovide starts empty because Neovim startup plugins, such as a dashboard, can replace files passed on the command line.

| Setting | Default |
|---|---|
| `NV_SOCKET` | `$TMPDIR/neovide-nv.sock` |

`nv` uses `--remote-send` because it still works while Neovim waits at a "Press ENTER" prompt; `--remote-expr` blocks there. A path that exists as written is never split, so a file named `a:1` still opens.

`nv` works only on macOS.

## Check

```sh
scripts/check.sh editors
ls -l ~/.config/zed/settings.json ~/.config/neovide/config.toml
zsh -ic 'type nv'
```
