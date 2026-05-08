# dot-configs

Personal dotfiles repository. Single source of truth for shell, terminal, and
editor configuration; synced across machines via git + an idempotent installer
that creates symlinks into the home directory.

## Repository layout

```
dot-configs/
├── install.sh                   # idempotent linker; safe to re-run
├── ghostty/                     # contents -> ~/.config/ghostty/
│   └── config.ghostty           # Ghostty terminal config (Gruvbox + Rec Mono)
├── oh-my-zsh-custom/            # contents -> ~/.oh-my-zsh/custom/
│   ├── custom.zsh               # aliases, proxy helpers, brew completions, env
│   └── gg.zsh                   # gg() function (terminal title + copilot)
├── copilot/                     # contents -> ~/.copilot/
│   ├── settings.json            # Copilot CLI settings (model, footer, status line)
│   ├── statusline.sh            # custom multi-segment status line
│   └── copilot-instructions.md  # global agent instructions
├── wezterm/                     # archived previous terminal config (NOT auto-linked)
│   └── wezterm.lua              # legacy WezTerm config — link manually if needed
├── LICENSE
├── ReadMe.md                    # this file
└── QUICKREF.md                  # condensed reference (agent-friendly)
```

`install.sh` is the only entry point. It:

1. Installs required macOS apps and fonts via Homebrew (best-effort; failures
   are logged but never abort the install). Set `SKIP_BREW=1` to skip this
   step entirely (useful for CI / fake-`HOME` testing).
2. Symlinks every **top-level** dotfile in this repo (files starting with `.`)
   into `$HOME`.
3. Symlinks every file in `oh-my-zsh-custom/` into `~/.oh-my-zsh/custom/`.
   Skipped (with a warning) if `~/.oh-my-zsh/custom/` does not exist.
4. Symlinks every file in `copilot/` into `~/.copilot/`. Skipped (with a
   warning) if `~/.copilot/` does not exist. Preserves the executable bit on
   `*.sh` files (so `statusline.sh` runs without re-chmod).
5. Symlinks every file in `ghostty/` into `~/.config/ghostty/`. **Creates the
   destination directory if missing** (Ghostty only creates it on first
   launch, but we want install.sh to wire things up on a fresh box without
   requiring a Ghostty launch first).
6. Backs up any existing destination file or symlink that doesn't already point
   at the repo as `<name>.bak.YYYYMMDDHHMMSS` before linking.
7. Leaves correctly-pointing symlinks alone (no-op).

> **`wezterm/` is intentionally not auto-linked.** It holds the previous
> terminal config so users mid-migration can keep using WezTerm by manually
> running `ln -sfn "$(pwd)/wezterm/wezterm.lua" ~/.wezterm.lua` (the `-fn`
> flags safely overwrite the stale `~/.wezterm.lua` symlink left over from
> `v0.3.0`, which now points at a deleted file). Slated for
> removal in `v0.5.0`.

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
| New Ghostty config snippet | Drop the file under `ghostty/`, then re-run `install.sh`. The destination directory is created automatically. |
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

Sets the current terminal tab and window title to `<title>` via OSC 1 / 2
escape sequences (works in Ghostty, WezTerm, iTerm2, anything OSC-compliant)
and then launches `copilot --allow-all-tools --allow-all-paths` in the
current shell. Useful for labeling Copilot CLI sessions so they're
identifiable in the tab bar.

Implementation notes:

- Sends OSC 1 (icon name / tab title) and OSC 2 (window title) — terminals
  that pull the window title from the active pane's OSC 2 (Ghostty, WezTerm)
  pick this up automatically.
- For WezTerm specifically, also calls `wezterm cli set-tab-title` and
  `set-window-title` to update WezTerm's internal state for completeness;
  these commands are no-ops outside WezTerm.
- Sets `DISABLE_AUTO_TITLE=true` while Copilot is running so oh-my-zsh's
  `precmd` / `preexec` hooks don't keep overwriting the title.
- Calls `command copilot ...` to bypass any shell alias of the same name.

### Terminal — Ghostty (`ghostty/`)

The daily-driver terminal as of `v0.4.0`. Files in `ghostty/` are linked into
`~/.config/ghostty/`. `install.sh` creates that directory if it doesn't
already exist (Ghostty itself only creates the dir on first launch, but we
want a fresh `install.sh` run to wire things up without requiring the user
to launch Ghostty first).

#### `config.ghostty`

| Setting | Value |
|---|---|
| Theme | `Gruvbox Dark Hard` (built-in, verified via `ghostty +list-themes`) |
| Primary font | `Rec Mono St.Helens` (Recursive Mono variable family) |
| Font weight | 500 (Medium) via `font-variation = wght=500`, single weight always |
| Font size | 14 pt |
| Line height | `adjust-cell-height = 10%` (matches the WezTerm `line_height = 1.1`) |
| Bold style | `font-style-bold = default` — no native bold variant; falls back to regular |
| Window padding | 8 px on both axes |
| Inactive split dim | `unfocused-split-opacity = 0.4` |
| macOS title bar | `macos-titlebar-style = tabs` (native, tabs at top) |
| Bell | Audio off (Ghostty default `bell-features` excludes audio) |
| Scrollback | Default 10,000,000 lines |
| Renderer | Metal (Ghostty native on macOS) |
| `term` | `xterm-ghostty` (Ghostty default; ships its own terminfo) |

Keybindings (overrides on top of Ghostty defaults; later definitions win):

| Action | Shortcut |
|---|---|
| Split right (horizontal) | `Cmd+Shift+D` (Ghostty's `super+shift+d`) |
| Split down (vertical) | `Cmd+D` (Ghostty's `super+d`) |
| Previous tab | `Cmd+←` |
| Next tab | `Cmd+→` |
| Focus pane (direction) | `Ctrl+Shift+Arrows` |
| Resize pane (small steps) | `Cmd+Ctrl+Alt+Shift+Arrows` (step 5) |
| Toggle pane zoom | `Cmd+Ctrl+Alt+Enter` |
| Close pane (or tab if last pane) | `Cmd+W` (Ghostty default) |
| Copy selection to clipboard | `Cmd+C` (Ghostty default `copy_to_clipboard:mixed`) |
| Send `Ctrl+C` (SIGINT) | Plain `Ctrl+C` — Ghostty has no callback API, so the WezTerm "smart `Cmd+C`" (copy if selection, else SIGINT) is **not** portable |

> **Validate locally** with `ghostty +validate-config --config-file=ghostty/config.ghostty` — exit 0 means clean; warnings or errors print otherwise. Use `ghostty +list-themes` to confirm the theme name and `ghostty +list-actions` for the full action vocabulary.

### Legacy terminal — WezTerm (`wezterm/`, archived)

The previous daily-driver terminal. **Not auto-linked** by `install.sh`
(the linker only walks top-level `.<name>` files plus the `oh-my-zsh-custom/`,
`copilot/`, and `ghostty/` mappings). Kept in-repo through `v0.4.x` so
users mid-migration can manually opt in:

```bash
ln -sfn "$(pwd)/wezterm/wezterm.lua" ~/.wezterm.lua
```

Slated for removal in `v0.5.0`. The previous WezTerm setup highlights
(GruvboxDarkHard, Rec Mono St.Helens, custom pill tabs with Nerd Font
process icons, DPI-adaptive font weight, FreeType fine-tuning, smart
`Cmd+C`) are documented in the file header.

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

- [Ghostty](https://ghostty.org/) — daily-driver terminal as of `v0.4.0`
- [WezTerm](https://wezfurlong.org/wezterm/) — kept for users mid-migration
  who still link `wezterm/wezterm.lua` manually (cask removal slated for
  `v0.5.0`)
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
- LXGW WenKai — `font-lxgw-wenkai` (currently installed but not in any
  active config's font-fallback list — slated for cleanup in `v0.5.0`)
- Symbols Only Nerd Font — `font-symbols-only-nerd-font`
- Noto Color Emoji — `font-noto-color-emoji`

### Optional Homebrew formulae used by `custom.zsh`

- `autojump`, `zsh-fast-syntax-highlighting`, `zsh-completions` — sourced if
  present; absence is silently ignored.

## License

See [LICENSE](LICENSE).
