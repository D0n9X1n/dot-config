# dot-configs

Personal dotfiles repository. Single source of truth for shell, terminal, and
editor configuration; synced across machines via git + an idempotent installer
that creates symlinks into the home directory.

## Repository layout

```
dot-configs/
├── install.sh                   # idempotent linker; safe to re-run
├── .tmux.conf                   # -> ~/.tmux.conf  (tab/split/session manager)
├── alacritty/                   # contents -> ~/.config/alacritty/
│   └── alacritty.toml           # Alacritty terminal config (Gruvbox + Rec Mono)
├── oh-my-zsh-custom/            # contents -> ~/.oh-my-zsh/custom/
│   ├── custom.zsh               # aliases, proxy helpers, brew completions, env
│   └── gg.zsh                   # gg() function (terminal title + copilot)
├── copilot/                     # contents -> ~/.copilot/
│   ├── settings.json            # Copilot CLI settings (model, footer, status line)
│   ├── statusline.sh            # custom multi-segment status line
│   └── copilot-instructions.md  # global agent instructions
├── wezterm/                     # fallback terminal config (NOT auto-linked)
│   └── wezterm.lua              # opt-in WezTerm config — link manually if used
├── LICENSE
├── ReadMe.md                    # this file
└── QUICKREF.md                  # condensed reference (agent-friendly)
```

`install.sh` is the only entry point. It:

1. Installs required macOS apps and fonts via Homebrew (best-effort; failures
   are logged but never abort the install). Set `SKIP_BREW=1` to skip this
   step entirely (useful for CI / fake-`HOME` testing). Casks: `alacritty`,
   `wezterm`, the Recursive font family, Symbols Only Nerd Font, Noto Color
   Emoji. Formulae: `tmux`.
2. Symlinks every **top-level** dotfile in this repo (files starting with `.`)
   into `$HOME` (currently `.tmux.conf`, plus the existing `.gitignore` /
   `.DS_Store` pass-through which has been there since v0.1).
3. Symlinks every file in `oh-my-zsh-custom/` into `~/.oh-my-zsh/custom/`.
   Skipped (with a warning) if `~/.oh-my-zsh/custom/` does not exist.
4. Symlinks every file in `copilot/` into `~/.copilot/`. Skipped (with a
   warning) if `~/.copilot/` does not exist. Preserves the executable bit on
   `*.sh` files (so `statusline.sh` runs without re-chmod).
5. Symlinks every file in `alacritty/` into `~/.config/alacritty/`. **Creates
   the destination directory if missing** (Alacritty only creates it on first
   launch, but we want install.sh to wire things up on a fresh box without
   requiring an Alacritty launch first).
6. Bootstraps **TPM** (Tmux Plugin Manager): clones it under `~/.tmux/plugins/tpm`
   if missing, then runs `tpm/bin/install_plugins` to clone every plugin
   listed in `.tmux.conf`. Skipped if `tmux` isn't on PATH.
7. Backs up any existing destination file or symlink that doesn't already point
   at the repo as `<name>.bak.YYYYMMDDHHMMSS` before linking.
8. Leaves correctly-pointing symlinks alone (no-op).

> **`wezterm/` is intentionally not auto-linked.** It's the supported fallback
> terminal — kept in-repo (and the `wezterm` cask is still auto-installed) for
> users who want native tabs/splits without involving tmux, or who need
> WezTerm's variable-font weight axis (Alacritty has no equivalent). Manually
> opt in with:
>
> ```bash
> ln -sfn "$(pwd)/wezterm/wezterm.lua" ~/.wezterm.lua
> ```

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
| New Alacritty config snippet | Drop the file under `alacritty/`, then re-run `install.sh`. The destination directory is created automatically. |
| Editing an existing config | Edit it in this repo. Symlinks make changes live immediately on every machine. Reload mechanisms: Alacritty `live_config_reload = true`; tmux `prefix + r`; wezterm auto-reloads. |

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

Sets the current terminal tab and window title to `<title>` via OSC 1 / 2
escape sequences (works in Alacritty, WezTerm, iTerm2, anything OSC-compliant).
**Inside tmux** the OSC escape doesn't propagate to the outer terminal because
`.tmux.conf` keeps `allow-rename off` and `automatic-rename off`, so `gg` also
calls `tmux rename-window` directly — that updates tmux's status-bar window
name, and `set-titles on` then bubbles `#S · #W` up to Alacritty's titlebar.
After updating titles, `gg` launches
`copilot --allow-all-tools --allow-all-paths --effort xhigh` in the current
shell. Useful for labeling Copilot CLI sessions so they're identifiable in
the tab bar.

Implementation notes:

- Sends OSC 1 (icon name / tab title) and OSC 2 (window title) — terminals
  that pull the window title from the active surface's OSC 2 (Alacritty,
  WezTerm) pick this up automatically when not nested in tmux.
- When `$TMUX` is set, also runs `tmux rename-window -- "$title"` so tmux's
  own window-name machinery is in sync (it doesn't read OSC sequences once
  `automatic-rename` is off).
- For WezTerm specifically (gated by `$WEZTERM_PANE`), also calls
  `wezterm cli set-tab-title` and `set-window-title` to update WezTerm's
  internal state — no-op when wezterm is on PATH but not the active terminal.
- Sets `DISABLE_AUTO_TITLE=true` while Copilot is running so oh-my-zsh's
  `precmd` / `preexec` hooks don't keep overwriting the title.
- Calls `command copilot ...` to bypass any shell alias of the same name.

### Terminal — Alacritty (`alacritty/`)

The daily-driver terminal as of `v0.5.0`. Files in `alacritty/` are linked
into `~/.config/alacritty/`. `install.sh` creates that directory if it
doesn't already exist (Alacritty itself only creates the dir on first
launch, but we want a fresh `install.sh` run to wire things up without
requiring the user to launch Alacritty first).

Why Alacritty + tmux instead of a tabs-native terminal:

- **Cross-platform muscle memory.** Alacritty runs natively on macOS,
  Windows, and Linux/BSD with the same TOML config. Tabs/splits/sessions
  live in tmux, so the experience is identical everywhere — including
  remote SSH where local-terminal tabs would not exist.
- **Session persistence.** tmux + tmux-resurrect + tmux-continuum survive
  Alacritty crashes, OS reboots, and SSH disconnects. Native tabs cannot.
- **Speed.** Alacritty is GPU-accelerated (OpenGL) and faster to start
  than Electron-based terminals.

#### `alacritty.toml`

| Setting | Value |
|---|---|
| Theme | hand-rolled `[colors.*]` matching Gruvbox Dark Hard (mirrors `wezterm/wezterm.lua`'s `GruvboxDarkHard`) |
| Primary font | `Rec Mono St.Helens`, style `Regular` (Alacritty has no variable-font weight axis support; the static `font-recursive` cask only ships Regular/Bold/Italic/Bold-Italic, so wght=500 from WezTerm is unreachable here — visual difference at 14pt is mild) |
| Font size | 14 pt |
| Line height | `font.offset = { x=0, y=2 }` (vertical breathing room ≈ WezTerm `line_height = 1.1`) |
| Window padding | `{x=8, y=8}`, `dynamic_padding = true` |
| Window decorations | `Full` (Alacritty has no native tab strip; full chrome lets macOS render the titlebar normally) |
| `option_as_alt` | `OnlyLeft` (left-Option as Alt for tmux/shell `M-…`; right-Option preserved for typing accents) |
| `dynamic_title` | `true` (honour OSC 0/1/2 from `gg` and tmux) |
| Bell | `duration = 0` (silent) |
| Cursor | Block, no blink, hollow when unfocused |
| Selection | `save_to_clipboard = false` (explicit Cmd+C only) |
| Scrolling | `history = 100000` |
| OSC 52 | `terminal.osc52 = "CopyPaste"` (cross-machine clipboard via SSH'd tmux/vim) |
| Shell | `[terminal.shell] program = "/bin/zsh", args = ["-l"]` (login shell) |
| `live_config_reload` | `true` |

Keybindings (additive on top of Alacritty defaults — defaults like Cmd+C/V,
Cmd+=, Cmd+-, Cmd+N (new window), Cmd+W, Cmd+F (search), Cmd+H/M (hide/min)
are kept):

| Action | Shortcut |
|---|---|
| Open another window (no native tabs — use tmux) | `Cmd+T` (alias for `Cmd+N`) |
| Reset font size | `Cmd+0` |
| Word jump in shell | `Option+Left` / `Option+Right` (sends `ESC b` / `ESC f`) |

> **Tabs/splits/pane-nav are entirely tmux's responsibility.** See the tmux
> section below for the keymap.
>
> **Validate locally** with
> `alacritty migrate --dry-run --config-file alacritty/alacritty.toml` —
> exit 0 with `Successfully migrated` means the schema is sound.

##### Cross-platform notes

The header comment in `alacritty.toml` documents how to use the file from
Linux and Windows. In short:

- **macOS**: `install.sh` symlinks the file to `~/.config/alacritty/alacritty.toml`.
- **Linux**: `ln -sfn <repo>/alacritty/alacritty.toml ~/.config/alacritty/alacritty.toml`.
- **Windows**: copy or symlink to `%APPDATA%\alacritty\alacritty.toml`.
  Override the shell to `pwsh.exe` either inline or by placing a sibling
  `local.toml` referenced from `[general] import` (the file ships with the
  import line commented for that purpose). Recursive Mono St.Helens may not
  be installed on Windows by default — fall back to `RecMonoCasual Nerd
  Font` from `font-recursive-mono-nerd-font` or any monospace family.

### Terminal — tmux (`.tmux.conf`)

Primary tab/split/session manager. Linked to `~/.tmux.conf` by `install.sh`.

| Setting | Value |
|---|---|
| Theme | hand-rolled Gruvbox Dark Hard palette (matches Alacritty + WezTerm) |
| Prefix | `C-q` (chosen over default C-b for ergonomics — far from C-c/d/z, doesn't clash with readline, modern macOS disables the legacy C-q XON flow control so nothing reclaims the keystroke; press `prefix + C-q` to send a literal `C-q` to the active pane) |
| `default-terminal` | `tmux-256color` + `RGB` overrides for `alacritty`, `wezterm`, `xterm-256color`, `*-direct` |
| Mouse | `on` (scroll, click-to-select, drag-to-resize) |
| `escape-time` | `0` (vim-friendly) |
| `history-limit` | `100000` |
| Window/pane base index | `1` (1-indexed; `renumber-windows on`) |
| Status position | top |
| Set-clipboard | `on` (OSC 52 — works through SSH because Alacritty + WezTerm both honour OSC 52) |
| Mode keys | `vi` |
| Allow rename / Auto rename | `off` (so `gg` / Vim-buffer titles stick; `gg` calls `tmux rename-window` explicitly) |

Keybinds (additive — tmux defaults like `prefix + n / p / 1..9 / Tab` for
window nav, `prefix + z` for zoom, `prefix + Space` for layout cycle, `prefix
+ d` for detach, `prefix + s` for session list are all kept):

| Action | Shortcut |
|---|---|
| Reload tmux.conf | `prefix + r` |
| Split right (vertical separator) | `prefix + |` (cwd inherited) |
| Split down (horizontal separator) | `prefix + -` (cwd inherited) |
| New window (cwd inherited) | `prefix + c` (default rebound to inherit cwd) |
| Pane focus (vim-style) | `prefix + h / j / k / l` |
| Pane resize (repeatable, no re-prefix) | `prefix + H / J / K / L` |
| Copy mode (vi keys) | `prefix + v`, then `v` start-selection, `y` copy |
| Mouse drag selection | auto-copies on drag end (OSC 52) |

Status bar segments:

- **Left**: yellow pill with the current session name (`#S`).
- **Window list**: inactive in dim grey on bg0; active in dark text on a
  Gruvbox bright-blue pill, plus a magnifier when zoomed
  (`#{?window_zoomed_flag, ,}`).
- **Right**: prefix indicator (only while the prefix is held, in red),
  `HH:MM`, vertical bar, and `YYYY-MM-DD`.

Plugins (managed by **TPM** — bootstrap is automatic on first run, both via
`.tmux.conf`'s `if "test ! -d ..."` guard and via `install.sh`):

| Plugin | Why |
|---|---|
| `tmux-plugins/tpm` | Plugin manager |
| `tmux-plugins/tmux-sensible` | Opinionated defaults that don't fight ours |
| `tmux-plugins/tmux-yank` | Cross-platform clipboard helpers |
| `tmux-plugins/tmux-resurrect` | Save/restore sessions (`prefix + Ctrl-s` / `Ctrl-r`); pane contents and Vim/NeoVim sessions captured |
| `tmux-plugins/tmux-continuum` | Auto-save every 15 min, auto-restore on tmux start |

> **Validate locally** with
> `tmux -f .tmux.conf -L _v new-session -d -s _v ; tmux -L _v kill-server`
> — silent exit means the config parsed cleanly. To force re-install of
> plugins: `~/.tmux/plugins/tpm/bin/install_plugins`.

### Fallback terminal — WezTerm (`wezterm/`, opt-in)

Kept as the supported fallback for users who want native tabs/splits without
tmux, or who need WezTerm's variable-font weight axis. **Not auto-linked**
by `install.sh`; the `wezterm` cask is still installed so the fallback is
one symlink away:

```bash
ln -sfn "$(pwd)/wezterm/wezterm.lua" ~/.wezterm.lua
```

Highlights of the in-repo config: GruvboxDarkHard, Rec Mono St.Helens,
custom 5-row "floating tabs" with Nerd Font process icons and a
Knight-Rider loading bar for vibe-coding sessions, DPI-adaptive font
weight, FreeType fine-tuning, smart `Cmd+C` (copy if selection else SIGINT).

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

### Apps (auto-installed via Homebrew on macOS)

- [Alacritty](https://alacritty.org/) — daily-driver terminal as of `v0.5.0`
- [WezTerm](https://wezfurlong.org/wezterm/) — kept as the supported
  fallback for users who want native tabs/splits without tmux
- [oh-my-zsh](https://ohmyz.sh/) — required only if you want the
  `oh-my-zsh-custom/` files linked
- [GitHub Copilot CLI](https://github.com/github/copilot) — required only if
  you want the `copilot/` files linked
- [`gh`](https://cli.github.com/) — optional; `statusline.sh` calls
  `gh auth status` (cached 5 minutes) to render the GH segment

### Tools (auto-installed via Homebrew on macOS)

- [tmux](https://github.com/tmux/tmux) ≥ 3.3 (3.6a tested) — primary tab,
  split, and session manager. TPM and listed plugins bootstrap automatically
  on first launch.
- `git` — required by TPM to clone the plugin manager and plugin repos.

### Fonts (installed automatically via Homebrew)

- Recursive (Rec Mono St.Helens — part of the Rec Mono variable family) —
  `font-recursive`
- Recursive Mono Nerd Font — `font-recursive-mono-nerd-font`
- Symbols Only Nerd Font — `font-symbols-only-nerd-font`
- Noto Color Emoji — `font-noto-color-emoji`

### Optional Homebrew formulae used by `custom.zsh`

- `autojump`, `zsh-fast-syntax-highlighting`, `zsh-completions` — sourced if
  present; absence is silently ignored.

## License

See [LICENSE](LICENSE).
