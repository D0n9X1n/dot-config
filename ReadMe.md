# dot-configs

Personal dotfiles repository. Single source of truth for shell, terminal, and
editor configuration; synced across machines via git + an idempotent installer
that creates symlinks into the home directory.

## Repository layout

```
dot-configs/
├── install.sh                   # idempotent linker; safe to re-run
├── .tmux.conf                   # -> ~/.tmux.conf  (tab/split/session manager)
├── oh-my-zsh-custom/            # contents -> ~/.oh-my-zsh/custom/
│   ├── custom.zsh               # aliases, proxy helpers, brew completions, env
│   └── gg.zsh                   # gg() function (terminal title + copilot)
├── copilot/                     # contents -> ~/.copilot/
│   ├── settings.json            # Copilot CLI settings (model, footer, status line)
│   ├── statusline.sh            # custom multi-segment status line
│   └── copilot-instructions.md  # global agent instructions
├── claude/                      # contents -> ~/.claude/
│   └── settings.json            # Claude Code → copilot-api proxy bridge config
├── wezterm/                     # terminal config (NOT auto-linked — opt-in)
│   └── wezterm.lua              # WezTerm config — link manually if used
├── LICENSE
├── ReadMe.md                    # this file
└── QUICKREF.md                  # condensed reference (agent-friendly)
```

`install.sh` is the only entry point. It:

1. Installs required macOS apps and fonts via Homebrew (best-effort; failures
   are logged but never abort the install). Set `SKIP_BREW=1` to skip this
   step entirely (useful for CI / fake-`HOME` testing). Casks: `wezterm`,
   the Recursive font family, Symbols Only Nerd Font, Noto Color Emoji.
   Formulae: `tmux`.
2. Symlinks every **top-level** dotfile in this repo (files starting with `.`)
   into `$HOME` (currently `.tmux.conf`, plus the existing `.gitignore` /
   `.DS_Store` pass-through which has been there since v0.1).
3. Symlinks every file in `oh-my-zsh-custom/` into `~/.oh-my-zsh/custom/`.
   Skipped (with a warning) if `~/.oh-my-zsh/custom/` does not exist.
4. Symlinks every file in `copilot/` into `~/.copilot/`. Skipped (with a
   warning) if `~/.copilot/` does not exist. Preserves the executable bit on
   `*.sh` files (so `statusline.sh` runs without re-chmod).
5. Symlinks every file in `claude/` into `~/.claude/`. **Creates the
   destination directory if missing** (Claude Code only creates `~/.claude/`
   on first launch; mkdir-p so install.sh wires things up on a fresh box).
   `settings.json` is the one exception — instead of a plain symlink it is
   **generated** by jq-merging the committed `claude/settings.json` with
   the local `~/.config/github-copilot/mcp.json` so Claude Code sees the
   exact same MCP servers Copilot CLI does, without committing
   secret-bearing MCP env (e.g. `WAKATIME_API_KEY`) to this public repo.
   Falls back to a plain symlink if `jq` or `mcp.json` is missing.
6. Bootstraps **TPM** (Tmux Plugin Manager): clones it under `~/.tmux/plugins/tpm`
   if missing, then runs `tpm/bin/install_plugins` to clone every plugin
   listed in `.tmux.conf`. Skipped if `tmux` isn't on PATH.
7. Backs up any existing destination file or symlink that doesn't already point
   at the repo as `<name>.bak.YYYYMMDDHHMMSS` before linking.
8. Leaves correctly-pointing symlinks alone (no-op).

> **`wezterm/` is intentionally not auto-linked.** The `wezterm` cask is
> still auto-installed so the terminal is one symlink away. Manually opt in
> with:
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
| New Claude Code config | Drop the file under `claude/`, then re-run `install.sh`. The destination directory is created automatically. |
| Editing an existing config | Edit it in this repo. Symlinks make changes live immediately on every machine. Reload mechanisms: tmux `prefix + r`; wezterm auto-reloads. |

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
escape sequences (works in WezTerm, iTerm2, anything OSC-compliant).
**Inside tmux** the OSC escape doesn't propagate to the outer terminal because
`.tmux.conf` keeps `allow-rename off` and `automatic-rename off`, so `gg` also
calls `tmux rename-window` directly — that updates tmux's status-bar window
name, and `set-titles on` then bubbles `#S · #W` up to the outer terminal's
titlebar. After updating titles, `gg` launches
`copilot --allow-all-tools --allow-all-paths --effort xhigh` in the current
shell. Useful for labeling Copilot CLI sessions so they're identifiable in
the tab bar.

Implementation notes:

- Sends OSC 1 (icon name / tab title) and OSC 2 (window title) — terminals
  that pull the window title from the active surface's OSC 2 (WezTerm) pick
  this up automatically when not nested in tmux.
- When `$TMUX` is set, also runs `tmux rename-window -- "$title"` so tmux's
  own window-name machinery is in sync (it doesn't read OSC sequences once
  `automatic-rename` is off).
- For WezTerm specifically (gated by `$WEZTERM_PANE`), also calls
  `wezterm cli set-tab-title` and `set-window-title` to update WezTerm's
  internal state — no-op when wezterm is on PATH but not the active terminal.
- Sets `DISABLE_AUTO_TITLE=true` while Copilot is running so oh-my-zsh's
  `precmd` / `preexec` hooks don't keep overwriting the title.
- Calls `command copilot ...` to bypass any shell alias of the same name.

### Terminal — WezTerm (`wezterm/`, opt-in)

The terminal config kept in-repo. **Not auto-linked** by `install.sh`; the
`wezterm` cask is installed so the terminal is one symlink away:

```bash
ln -sfn "$(pwd)/wezterm/wezterm.lua" ~/.wezterm.lua
```

Highlights of the in-repo config: GruvboxDarkHard, Rec Mono St.Helens,
custom 5-row "floating tabs" with Nerd Font process icons and a
Knight-Rider loading bar for vibe-coding sessions, DPI-adaptive font
weight, FreeType fine-tuning, smart `Cmd+C` (copy if selection else SIGINT).

### Terminal — tmux (`.tmux.conf`)

Primary tab/split/session manager. Linked to `~/.tmux.conf` by `install.sh`.

| Setting | Value |
|---|---|
| Theme | hand-rolled Gruvbox Dark Hard palette (matches WezTerm) |
| Prefix | `C-q` (chosen over default C-b for ergonomics — far from C-c/d/z, doesn't clash with readline, modern macOS disables the legacy C-q XON flow control so nothing reclaims the keystroke; press `prefix + C-q` to send a literal `C-q` to the active pane) |
| `default-terminal` | `tmux-256color` + `RGB` overrides for `wezterm`, `xterm-256color`, `*-direct` |
| Env scrubbing | `set-environment -gu TERMINFO TERMINFO_DIRS TERMCAP TERM_PROGRAM TERM_PROGRAM_VERSION` + `set -g COLORTERM truecolor` — defends against long-lived tmux servers inheriting dead `$TERMINFO` from previously installed terminals (which otherwise silently degrades panes from `tmux-256color` to `xterm-color` and breaks Copilot CLI's truecolor input panel). **Recovery for an already-poisoned server**: save state with `prefix + Ctrl-s`, then `tmux kill-server` from a non-tmux shell. |
| Mouse | `on` (scroll, click-to-select, drag-to-resize) |
| `escape-time` | `0` (vim-friendly) |
| `history-limit` | `100000` |
| Window/pane base index | `1` (1-indexed; `renumber-windows on`) |
| Status position | top |
| Set-clipboard | `on` (OSC 52 — works through SSH because WezTerm honours OSC 52) |
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

### Copilot CLI (`copilot/`)

Files in `copilot/` are linked into `~/.copilot/`. `install.sh` skips this
step (with a warning) if `~/.copilot/` does not exist (Copilot CLI not
installed).

#### `settings.json`

Copilot CLI configuration. Pinned model `claude-opus-4.7-1m-internal`, theme
`dark`, `keepAlive: busy`, `continueOnAutoMode: true`, custom footer (hides
code-changes plus everything `statusline.sh` now renders — model/effort,
branch, context window — to avoid duplication; keeps directory + agent +
custom segment), and a custom status line provided by `statusline.sh`.

> **Caveat:** Copilot CLI rewrites `settings.json` at runtime to inject /
> strip a `staff` field and to toggle UI defaults — edit it via atomic
> read–mutate–write–commit. Inside the `statusLine` block only the single
> `padding` field is honored (`paddingTop` / `paddingLeft` / etc. are
> silently ignored); per-side spacing is emitted from inside `statusline.sh`
> instead.

#### `statusline.sh`

Executable script — a "full mirror" of `~/.claude/statusline.sh` adapted to
Copilot's `statusLine` JSON. Per-segment Gruvbox color accents, color-graded
Cache % and Context %. Renders these segments in order, `<icon> <Label>
<value>` separated by `│` (each shown only when its data is available):
**Time, Model, Effort, Run, Wall, API, Req, Cache, Last, Ctx, Worktree,
Repo (clean / dirty + ↑↓), Branch, Stash, Venv, GH, Ext, MCP**. Effort is
parsed from `model.display_name` (Copilot bakes `(xhigh)` etc into the
display name rather than exposing `.effort.level`). Worktree is detected
via `git rev-parse --git-dir` and only shown when actually inside a linked
worktree. Vim, Agent, and Style are defined but no-op until Copilot starts
exposing them in JSON; `diff` is defined but omitted from the default
segment list (opt in via `COPILOT_STATUSLINE_SEGMENTS`).

Environment overrides:

- `COPILOT_STATUSLINE_NO_ICONS=1` — drop icons, keep text labels.
- `COPILOT_STATUSLINE_NO_COLOR=1` — drop color (legacy
  `COPILOT_STATUSLINE_NO_DIM=1` is honored as an alias for backwards-compat).
- `COPILOT_STATUSLINE_PAD_TOP=N` / `..._PAD_LEFT=N` / `..._PAD_RIGHT=N` —
  override per-side padding (defaults: top = 8, left = 1, right = 0).
- `COPILOT_STATUSLINE_SEGMENTS="…"` — override the segment list and order
  (e.g. add `diff`, drop `cache_pct`, reorder freely).

Run `~/.copilot/statusline.sh --test` to verify each codepoint renders in
your terminal (uses `fc-list` if installed). Parses Copilot's session JSON
from stdin via a single `jq` call and caches `gh auth status` for 5
minutes. Bash 3.2-compatible. `install.sh` keeps the executable bit set.

#### `copilot-instructions.md`

Global agent instructions — autonomous mode (no per-action confirmation):
operate in plan / exec cycles and verify before claiming completion.

### Claude Code (`claude/`)

Files in `claude/` are linked into `~/.claude/`. Bridges Anthropic's
[Claude Code CLI](https://github.com/anthropics/claude-code) to GitHub
Copilot models via a local [`copilot-api`](https://www.npmjs.com/package/copilot-api)
proxy that translates Anthropic-format requests into Copilot ones.

#### `settings.json`

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:4141",
    "ANTHROPIC_MODEL": "claude-opus-4.7-1m-internal",
    "ANTHROPIC_SMALL_FAST_MODEL": "gpt-5.5",
    "ANTHROPIC_API_KEY": "dummy"
  },
  "model": "claude-opus-4.7-1m-internal",
  "modelOverrides": { "...": "..." },
  "effortLevel": "max",
  "theme": "dark",
  "skipAutoPermissionPrompt": true,
  "permissions": { "defaultMode": "auto" }
}
```

Defaults pinned globally (synced across machines via this repo):

- **Model: `claude-opus-4.7-1m-internal`** (Opus 4.7, 1M-context internal
  variant). Pinned in both `env.ANTHROPIC_MODEL` *and* the top-level
  `model` field so Claude Code uses it on every launch with no `/model`
  toggle needed. `modelOverrides` redirects every other Anthropic model
  alias (Opus 4.5/4.6/4.7, Sonnet 4.5/4.6, Haiku 4.5) to the same target,
  so requests for any of those resolve to Opus 4.7 1M as well.
- **Effort: `max`** (`effortLevel: "max"`) — deepest reasoning by default,
  applied to every session without needing `/effort` each time.
- **`ANTHROPIC_SMALL_FAST_MODEL: gpt-5.5`** — the cheaper model used for
  sub-tasks like git-commit message generation; pointed at a Copilot model.
- `ANTHROPIC_BASE_URL` — the local `copilot-api` proxy.
- `ANTHROPIC_API_KEY` — required by Claude Code but unused by the proxy
  (`dummy` is fine; real auth happens in `copilot-api`'s GitHub flow).
- `skipAutoPermissionPrompt: true` + `permissions.defaultMode: "auto"` —
  autonomous mode by default (no per-action confirmation).

One-time setup (after running `install.sh` on a fresh box):

```bash
npm install -g @anthropic-ai/claude-code copilot-api
copilot-api auth                  # browser device-code login (GitHub)
copilot-api start --claude-code   # leave running on port 4141
claude                            # in another shell — uses Opus 4.7 1M @ max effort
```

> **Caveat:** Claude Code rewrites `settings.json` at runtime to add fields
> like `firstStartTime`, telemetry IDs, etc. Same atomic
> read–mutate–write–commit pattern as Copilot CLI's `settings.json`. If a
> spurious diff appears in the working tree, restore the committed shape
> rather than committing the runtime addition.

## Requirements

### Apps (auto-installed via Homebrew on macOS)

- [WezTerm](https://wezfurlong.org/wezterm/) — terminal (cask installed
  automatically; config is opt-in via the symlink command above)
- [oh-my-zsh](https://ohmyz.sh/) — required only if you want the
  `oh-my-zsh-custom/` files linked
- [GitHub Copilot CLI](https://github.com/github/copilot) — required only if
  you want the `copilot/` files linked
- [Claude Code CLI](https://github.com/anthropics/claude-code) +
  [`copilot-api`](https://www.npmjs.com/package/copilot-api) — required only
  if you want the `claude/` files linked (Anthropic CLI bridged onto GitHub
  Copilot models via a local proxy on port 4141)
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
