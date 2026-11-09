# Herdr

English | [简体中文](Herdr-zh-CN.md)

[Herdr](https://herdr.dev) is the terminal workspace this repo sets up with the Apollo layout. The layout lives in its own public repo, [herdr-config](https://github.com/D0n9X1n/herdr-config). This repo pins it as a Git submodule at `config/herdr`.

## What install does

`./install.sh` (and `uu`, which runs it) does these Herdr steps on macOS:

1. **Install Herdr when missing.** With no `Herdr.app` in `~/Applications` or `/Applications`, and no `herdr-app` on `PATH`, it runs `brew install --cask herdr-app`. An existing install is never touched. A failure prints one warning, and the rest of the install goes on. `SKIP_BREW=1` skips it.
2. **Update the submodule.** It runs `git submodule update --init config/herdr`. Offline, the Herdr rows are skipped with one `Herdr config:` line, and everything else installs.
3. **Keep your live values.** It reads the live `settings.json` and `keys.json`, and writes them into `config/herdr/user/` when they differ. If your `keys.json` is still Herdr's default, the Apollo keymap is used instead.
4. **Install the files.** Layouts, the theme, `settings.json`, `keys.json` and the agent script are links. Mods are copies; see below.
5. **Put the Dock icon back.** A Herdr update replaces the app and drops its custom icon. If `config/herdr/scripts/set-app-icon.sh --check` finds no custom icon, the installer sets the Apollo icon again. A failure prints a warning and goes on.

No backup of any kind is kept: no seed folder, no archive, no `.bak` file.

## Installed paths

| Source | Home destination | Type |
|---|---|---|
| `config/herdr/layouts/*` | `~/.config/herdr-app/layouts/*` | `link` |
| `config/herdr/themes/*` | `~/.config/herdr-app/themes/*` | `link` |
| `config/herdr/user/settings.json` | `~/.config/herdr-app/settings.json` | `link` |
| `config/herdr/user/keys.json` | `~/.config/herdr-app/keys.json` | `link` |
| `config/herdr/mods/**` | `~/.config/herdr-app/mods/**` | `copy` |
| `config/herdr/agent/herdr-context.sh` | `~/.local/bin/herdr-agent-context` | `link` |

## Why mods are copies

Herdr does not load a mod's `svg()` and `image()` files through a link, so its icons would be blank. Each mod file is a `copy` row instead. See [Repository operations](Repository-Operations.md) for how copies are kept in step and removed.

## Agent hooks

Claude Code and Copilot CLI run this at session start:

```sh
[ -x ~/.local/bin/herdr-agent-context ] && ~/.local/bin/herdr-agent-context claude || true
```

(Copilot uses `copilot` in place of `claude`.) Inside a Herdr terminal it adds a short note: this is Herdr, the terminal's address, and to run `herdr-app --skill` and `hc --skill` first. Outside Herdr, in the Claude desktop app, or with the script missing, it prints nothing.

## Settings edits

`config/herdr` has `ignore = dirty`, so Herdr's own writes to `settings.json` and `keys.json` never block `uu`. To keep an edit for every machine, commit it in herdr-config, then bump the pin here.

## Bump the pin

```sh
git -C config/herdr fetch --tags
git -C config/herdr checkout vX.Y.Z
git add config/herdr
```

Change `HERDR_PIN` in `scripts/check.sh` to match, run `scripts/check.sh all`, then commit.
