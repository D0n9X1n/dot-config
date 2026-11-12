# Editors

English | [简体中文](Editors-zh-CN.md)

This repo syncs the Zed and Neovide settings. Neovim itself lives in the separate `nvim-config` repo; this repo never changes it.

## Zed

`config/zed/settings.json` links to `~/.config/zed/settings.json`. It holds the theme, icon theme, fonts, Vim mode, and agent servers. A new window opens with an empty tab. The editor toolbar is hidden: breadcrumbs, quick actions, the Selections menu, and agent review buttons are all off, and `code_actions` is already off by default. A file's name shows once, in its tab.

Tab titles are larger than the editor text. Zed has no tab font setting: tab titles use its default label size, 14/16 of `ui_font_size`. With `ui_font_size` at `15` and `buffer_font_size` at `13`, tab titles are about 13.1px. `scripts/check.sh editors` checks that tab titles stay larger than the editor text.

Zed writes setting changes through the link, so a change made in Zed shows up in this repo as a Git change. Commit it, or drop it with `git checkout`.

### Default app for text files

On macOS, `install.sh` makes Zed the default app for text and code files: plain text, Markdown, JSON, YAML, TOML, XML, property lists, and source and script files. The list is `scripts/zed-default-types.txt`, one uniform type id per line. `scripts/zed-defaults.js` (run with `osascript`, no Xcode needed) asks Launch Services only for types Zed does not handle yet. macOS then shows one "Use Zed?" dialog per type; click **Use "Zed"**. Types already set to Zed are left alone, so a later install asks nothing. Skip the step with `SKIP_ZED_DEFAULTS=1`.

Not in the list on purpose: `.ts` (macOS reads it as MPEG-2 video), web pages, CSV, and logs. To see what opens a type now:

```sh
osascript -l JavaScript scripts/zed-defaults.js dev.zed.Zed check public.yaml
```

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
