# dot-configs

Personal dotfiles repository. Single source of truth for shell, terminal, and
editor configuration; synced across machines via git + an idempotent installer
that creates symlinks into the home directory.

## Repository layout

```
dot-configs/
├── install.sh                   # idempotent linker; safe to re-run
├── .wezterm.lua                 # root dotfile  -> ~/.wezterm.lua
├── oh-my-zsh-custom/            # contents -> ~/.oh-my-zsh/custom/
│   ├── custom.zsh               # aliases, proxy helpers, brew completions, env
│   └── gg.zsh                   # gg() function (WezTerm title + copilot)
├── ReadMe.md                    # this file
└── QUICKREF.md                  # condensed reference (agent-friendly)
```

`install.sh` is the only entry point. It:

1. Installs required macOS apps and fonts via Homebrew (best-effort; failures
   are logged but never abort the install).
2. Symlinks every **top-level** dotfile in this repo (files starting with `.`)
   into `$HOME`. Example: `.wezterm.lua` → `~/.wezterm.lua`.
3. Symlinks every file in `oh-my-zsh-custom/` into `~/.oh-my-zsh/custom/`.
   Skipped (with a warning) if `~/.oh-my-zsh/custom/` does not exist.
4. Backs up any existing destination file or symlink that doesn't already point
   at the repo as `<name>.bak.YYYYMMDDHHMMSS` before linking.
5. Leaves correctly-pointing symlinks alone (no-op).

Safe to re-run at any time. Pulling new commits automatically takes effect on
all machines because every config file is a symlink into this repo.

## Usage

```bash
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
bash ~/Public/dot-configs/install.sh
```

Subsequent updates on a machine:

```bash
cd ~/Public/dot-configs && git pull
# Re-run install.sh only if new files were added; existing symlinks need no action.
```

## How to add a new config

| Goal | Where to add the file |
|---|---|
| New `~/.something` dotfile | Drop it at repo root as `.something`, then re-run `install.sh`. |
| New oh-my-zsh customization (alias, function, env) | Create a new `*.zsh` file in `oh-my-zsh-custom/`, then re-run `install.sh`. Files there are auto-loaded by oh-my-zsh in alphabetical order. |
| Editing an existing config | Edit it in this repo. Changes take effect immediately on every machine where it's symlinked. |

After adding/editing, commit and push. Other machines pick up the change with
`git pull` (and `install.sh` again only if new files were introduced).

## Included configs

### Shell (`oh-my-zsh-custom/`)

#### `custom.zsh`

- Aliases: `ls=eza`, `ll=eza -l`, `c=cd ..`, `vim=nvim`, `proxy/unproxy`.
- `enable_proxy` / `disable_proxy` functions: toggle SOCKS5 proxy at
  `127.0.0.1:46971` for shell env vars, git, and npm in one call.
- Sources `zsh-fast-syntax-highlighting` and `zsh-completions` from Homebrew if
  available.
- Loads optional autojump if installed.
- Adds `.NET` and Android SDK tooling to `PATH`.

#### `gg.zsh` — `gg <title>`

Sets the current WezTerm tab and window title to `<title>`, then launches
`copilot --allow-all-tools --allow-all-paths` in the current shell. Useful for
labeling Copilot CLI sessions so they're identifiable in the tab bar.

Implementation notes:

- Sends OSC 1/2 escape sequences for the title (WezTerm's window title bar
  reflects the active pane's OSC 2 title — IPC alone is not enough).
- Also calls `wezterm cli set-tab-title` and `set-window-title` to update
  WezTerm's internal state for completeness.
- Sets `DISABLE_AUTO_TITLE=true` while Copilot is running so oh-my-zsh's
  `precmd`/`preexec` hooks don't keep overwriting the title.
- Calls `command copilot ...` to bypass any shell alias of the same name.

### WezTerm (`.wezterm.lua`)

#### Theme & appearance

| Setting | Value |
|---|---|
| Color scheme | GruvboxDarkHard |
| Background opacity | 1.0 |
| Window padding | 8px all sides |

#### Fonts

| Role | Font | Size |
|---|---|---|
| Primary (EN) | RecMonoBaker Nerd Font | 14pt |
| CJK fallback | LXGW WenKai Mono | scaled 17/14 |
| Icons/Powerline | Symbols Nerd Font Mono | — |
| Emoji | Noto Color Emoji | — |

- **Line height:** 1.2
- **Weight:** Auto-detects Retina displays — uses Regular on Retina, DemiBold on non-Retina.
- **Bold:** Native bold rendering enabled, `bold_brightens_ansi_colors` disabled.
- `custom_block_glyphs` disabled for correct Powerline/NERD glyph rendering.

#### Tab bar

- Retro style (non-fancy), positioned at bottom.
- Pill-shaped tabs with Nerd Font process icons (shell, nvim, ssh, git, node, python, go, rust, docker, kubectl, etc.).
- Folder icon shown for directory-based tab titles (`parent/leaf` format).
- Tab index number prefixed to each tab title.
- Max tab width: 40, minimum clickable width: 22.
- No new-tab button, no tab index badge.

#### Keybindings

| Action | Shortcut |
|---|---|
| Split right (horizontal) | `Cmd+Ctrl+Alt+V` |
| Split down (vertical) | `Cmd+Ctrl+Alt+H` |
| Previous tab | `Cmd+←` |
| Next tab | `Cmd+→` |
| Focus pane (direction) | `Ctrl+Shift+Arrows` |
| Resize pane (small steps) | `Cmd+Ctrl+Alt+Shift+Arrows` |
| Toggle pane zoom | `Cmd+Ctrl+Alt+Enter` |

#### Other settings

| Setting | Value |
|---|---|
| Rendering | WebGpu (Metal) — avoids deprecated OpenGL sleep/wake crashes |
| TERM | `xterm-256color` |
| Scrollback lines | 20,000 |
| Audible bell | Disabled |

## Requirements

### Apps

- [WezTerm](https://wezfurlong.org/wezterm/)
- [oh-my-zsh](https://ohmyz.sh/) (required only if you want the
  `oh-my-zsh-custom/` files linked)

### Fonts (installed automatically via Homebrew)

- Recursive (Rec Mono Baker) — `font-recursive`
- Recursive Mono Nerd Font — `font-recursive-mono-nerd-font`
- LXGW WenKai — `font-lxgw-wenkai`
- Symbols Only Nerd Font — `font-symbols-only-nerd-font`
- Noto Color Emoji — `font-noto-color-emoji`

### Optional Homebrew formulae used by `custom.zsh`

- `autojump`, `zsh-fast-syntax-highlighting`, `zsh-completions` — sourced if
  present; absence is silently ignored.

## License

See [LICENSE](LICENSE).
