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
├── copilot/                     # contents -> ~/.copilot/
│   ├── settings.json            # Copilot CLI settings (model, footer, status line)
│   ├── statusline.sh            # custom multi-segment status line
│   └── copilot-instructions.md  # global agent instructions
├── LICENSE
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
4. Symlinks every file in `copilot/` into `~/.copilot/`. Skipped (with a
   warning) if `~/.copilot/` does not exist. Preserves the executable bit on
   `*.sh` files (so `statusline.sh` runs without re-chmod).
5. Backs up any existing destination file or symlink that doesn't already point
   at the repo as `<name>.bak.YYYYMMDDHHMMSS` before linking.
6. Leaves correctly-pointing symlinks alone (no-op).

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
| New Copilot CLI config | Drop the file under `copilot/`, then re-run `install.sh`. (`mcp-config.json` is gitignored because it contains secrets — manage that file manually.) |
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
| Primary (EN) | Rec Mono St.Helens (Recursive Mono variable) | 14pt |
| Icons / Powerline | Symbols Nerd Font Mono | — |
| Emoji | Noto Color Emoji | — |

- **Line height:** 1.1
- **Weight:** Auto-detects display DPI — uses **Medium on Retina, Regular on non-Retina**. `apply_display_overrides()` swaps the weight and the FreeType flags on `window-config-reloaded` and `window-resized` events, so moving a window between displays re-tunes rendering live.
- **Bold:** Bold mapped to the same weight as Regular — the font has no dedicated bold variant, so `font_rules` collapses Bold to the regular weight; `bold_brightens_ansi_colors` disabled.
- **FreeType:** `freetype_render_target = "Normal"` (grayscale) on both displays. `freetype_load_target = "Normal"` at runtime — the static `"Light"` declared at the top of `.wezterm.lua` is overridden by `apply_display_overrides()` on every `window-config-reloaded` / `window-resized` event. The only DPI-conditional setting is `freetype_load_flags`: `"NO_HINTING"` on Retina (thinnest, smoothest strokes) and `"FORCE_AUTOHINT"` on non-Retina (crisper at 1×).
- `custom_block_glyphs` enabled (true) — WezTerm draws block / box-drawing glyphs itself for pixel-perfect alignment.

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
| Split right (horizontal) | `Cmd+Shift+D` |
| Split down (vertical) | `Cmd+D` |
| Previous tab | `Cmd+←` |
| Next tab | `Cmd+→` |
| Focus pane (direction) | `Ctrl+Shift+Arrows` |
| Resize pane (small steps) | `Cmd+Ctrl+Alt+Shift+Arrows` |
| Toggle pane zoom | `Cmd+Ctrl+Alt+Enter` |
| Smart copy / SIGINT | `Cmd+C` — copies if there is a selection, otherwise sends Ctrl+C |
| Close pane (or tab if last pane) | `Cmd+W` |

#### Other settings

| Setting | Value |
|---|---|
| Rendering | WebGpu (Metal) — avoids deprecated OpenGL sleep/wake crashes |
| TERM | `xterm-256color` |
| Scrollback lines | 20,000 |
| Audible bell | Disabled |
| Inactive pane dim | `inactive_pane_hsb`: saturation 0.7, brightness 0.4 |
| Window padding | 8 px on all sides |

### Copilot CLI (`copilot/`)

Files in `copilot/` are linked into `~/.copilot/`. `install.sh` skips this
step (with a warning) if `~/.copilot/` does not exist (Copilot CLI not
installed).

#### `settings.json`

Copilot CLI configuration. Pinned model `claude-opus-4.7-1m-internal`, theme
`dark`, `keepAlive: busy`, `continueOnAutoMode: true`, custom footer (hides
code-changes; shows agent + branch + context window + custom segment), and a
custom status line provided by `statusline.sh`.

> **Caveat:** Copilot CLI rewrites `settings.json` at runtime to inject /
> strip a `staff` field and to toggle UI defaults — edit it via atomic
> read–mutate–write–commit. Inside the `statusLine` block only the single
> `padding` field is honored (`paddingTop` / `paddingLeft` / etc. are
> silently ignored); per-side spacing is emitted from inside `statusline.sh`
> instead.

#### `statusline.sh`

Executable script that renders 11 segments separated by `│` (each shown only
when its data is available): `<icon> <Label> <value>` for **Time, Req, Run,
API, Cache, Last, Repo (clean / dirty + ↑↓), Stash, Venv, GH, MCP**. The
whole line is wrapped in ANSI dim (`\e[2m` … `\e[0m`) so it recedes from the
prompt.

Environment overrides:

- `COPILOT_STATUSLINE_NO_ICONS=1` — drop icons, keep text labels.
- `COPILOT_STATUSLINE_NO_DIM=1` — drop the dim wrap.
- `COPILOT_STATUSLINE_PAD_TOP=N` / `..._PAD_LEFT=N` / `..._PAD_RIGHT=N` —
  override per-side padding (defaults: top = 8, left = 0, right = 0).

Run `~/.copilot/statusline.sh --test` to verify each codepoint renders in
your terminal (uses `fc-list` if installed). Parses Copilot's session JSON
from stdin via a single `jq` call and caches `gh auth status` for 5
minutes. Bash 3.2-compatible. `install.sh` keeps the executable bit set.

#### `copilot-instructions.md`

Global agent instructions — autonomous mode (no per-action confirmation):
operate in plan / exec cycles and verify before claiming completion.

## Requirements

### Apps

- [WezTerm](https://wezfurlong.org/wezterm/)
- [oh-my-zsh](https://ohmyz.sh/) — required only if you want the
  `oh-my-zsh-custom/` files linked
- [GitHub Copilot CLI](https://github.com/github/copilot) — required only if
  you want the `copilot/` files linked
- [`gh`](https://cli.github.com/) — optional; `statusline.sh` calls
  `gh auth status` (cached 5 minutes) to render the GH segment

### Fonts (installed automatically via Homebrew)

- Recursive (Rec Mono St.Helens — part of the Rec Mono variable family) —
  `font-recursive`
- Recursive Mono Nerd Font — `font-recursive-mono-nerd-font`
- LXGW WenKai — `font-lxgw-wenkai` (currently installed but not in
  `.wezterm.lua`'s active fallback list — slated for re-evaluation in the
  Ghostty migration)
- Symbols Only Nerd Font — `font-symbols-only-nerd-font`
- Noto Color Emoji — `font-noto-color-emoji`

### Optional Homebrew formulae used by `custom.zsh`

- `autojump`, `zsh-fast-syntax-highlighting`, `zsh-completions` — sourced if
  present; absence is silently ignored.

## License

See [LICENSE](LICENSE).
