# Herdr

English | [简体中文](Herdr-zh-CN.md)

This page covers the Apollo layout for the terminal workspace app. The app is **Apollo.app**, a renamed copy of [Herdr](https://herdr.dev) that replaced Herdr.app. It loads Herdr's settings home, `~/.config/herdr-app`, so everything below still installs there. The layout lives in its own public repo, [herdr-config](https://github.com/MOSconfig/herdr-config). This repo pins it as a Git submodule at `config/herdr`.

## What install does

`./install.sh` (and `uu`, which runs it) does these steps on macOS. It never installs Herdr or Apollo.app; install Apollo.app by hand.

1. **Update the submodule.** It runs `git submodule update --init config/herdr`. Offline, the Herdr rows are skipped with one `Herdr config:` line, and everything else installs.
2. **Keep your live values.** It reads the live `settings.json` and `keys.json`, and writes them into `config/herdr/user/` when they differ. If your `keys.json` is still Herdr's default, the Apollo keymap is used instead.
3. **Install the files.** Layouts, the theme, `settings.json`, `keys.json` and the agent script are links. Mods are copies; see below.
4. **Put the Dock icon back.** Re-signing or copying `Apollo.app` drops its custom icon. If `config/herdr/scripts/set-app-icon.sh --check --app <Apollo.app>` finds no custom icon, the installer sets the Apollo icon again. It looks in `~/Applications`, then `/Applications`. A failure prints a warning and goes on.

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

Change `HERDR_PIN` and `HERDR_PIN_SHA` (the tag's commit, from `git -C config/herdr rev-parse vX.Y.Z^{commit}`) in `scripts/check.sh` to match, run `scripts/check.sh all`, then commit. CI checks out the submodule without tags, so the check compares the commit.
