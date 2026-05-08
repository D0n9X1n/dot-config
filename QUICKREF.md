# QUICKREF

Condensed, machine-readable summary for agents and skim reading. See
`ReadMe.md` for full details.

## Purpose
Personal dotfiles repo. Single source of truth for shell, terminal, and editor
configuration; synced across machines via git + an idempotent installer that
creates symlinks into `$HOME` (and `~/.oh-my-zsh/custom/`).

## Layout
- `install.sh` — single entry point; idempotent; safe to re-run.
- `<repo>/.<name>` — root dotfiles linked to `$HOME/.<name>`. Currently:
  - `.tmux.conf` — primary tab/split/session manager (Gruvbox Dark Hard
    palette, prefix `C-q` (chosen over default C-b for ergonomics — far
    from C-c/d/z, doesn't clash with readline, and modern macOS disables
    the legacy C-q XON flow control), mouse on, top status bar, vim-style
    splits (`prefix + |` / `prefix + -`), 1-indexed windows, OSC 52
    clipboard, TPM + tmux-sensible/yank/resurrect/continuum). Bootstrap
    of TPM and plugins is automatic on first tmux start (cloned by the
    `if test ! -d tpm` block, then plugin install runs after the `run
    '~/.tmux/plugins/tpm/tpm'` init line because that line is what sets
    `TMUX_PLUGIN_MANAGER_PATH` in tmux's env). `install.sh` ALSO bootstraps
    TPM + plugins for the install-script path. Validate locally with
    `tmux -f .tmux.conf -L _v new-session -d -s _v ; tmux -L _v kill-server`.
- `<repo>/alacritty/<file>` — files linked to `$HOME/.config/alacritty/<file>`.
  The destination directory is created by `install.sh` if missing
  (Alacritty itself only creates it on first launch). Currently:
  - `alacritty.toml` — primary terminal (`v0.5.0`+). `colors = Gruvbox Dark
    Hard` (matches wezterm GruvboxDarkHard exactly), `font.normal.family
    = Rec Mono St.Helens` `style = Regular` (Alacritty has no variable-font
    weight axis support, so we can't replicate WezTerm's wght=500 — only
    Regular static is shipped by `font-recursive`; cosmetic difference at
    14pt is mild), `font.size = 14`, `font.offset.y = 2` (≈ WezTerm
    `line_height = 1.1`), `window.padding = {x=8,y=8}`,
    `window.option_as_alt = "OnlyLeft"` (left-Option as Alt for tmux/shell;
    right-Option preserved for typing accents), `window.decorations =
    "Full"` (Alacritty has NO native tabs by design — tmux is the tab
    manager), `[terminal.shell] program = "/bin/zsh" args = ["-l"]`,
    `[terminal] osc52 = "CopyPaste"` (cross-machine clipboard via SSH'd
    tmux/vim), `[bell] duration = 0`, `[mouse] hide_when_typing = true`,
    `[scrolling] history = 100000`, `[general] live_config_reload = true`.
    Keybinds add only `Cmd+T = CreateNewWindow` (no native tabs) and
    `Cmd+0 = ResetFontSize`; tabs/splits/pane-nav are entirely tmux's
    responsibility. Cross-platform notes in the file header explain how
    Linux/Windows users should symlink/import the file; Windows users
    edit `[terminal.shell] program` to `pwsh.exe` or use a sibling
    `local.toml` referenced via `[general] import`. Validate without
    launching the GUI with
    `alacritty migrate --dry-run --config-file alacritty/alacritty.toml`.
- `<repo>/wezterm/<file>` — **fallback terminal config; NOT auto-linked**.
  Kept as the supported alternative to Alacritty for users who want native
  tabs/splits without tmux, or who need WezTerm's variable-font weight axis
  (Alacritty has no equivalent). Manually opt in with
  `ln -sfn "$(pwd)/wezterm/wezterm.lua" ~/.wezterm.lua` (the `-fn` flags
  safely overwrite any stale symlink). The `wezterm` cask is still
  auto-installed by `install.sh` so the fallback is one symlink away.
- `<repo>/copilot/<file>` — files linked to `$HOME/.copilot/<file>`. Currently:
  - `settings.json` — Copilot CLI settings (model: `claude-opus-4.7-1m-internal`,
    theme `dark`, `keepAlive: busy`, `continueOnAutoMode: true`, custom
    footer (hides code-changes), custom status line). The `statusLine`
    block only takes a single `padding` field — per-side spacing is done
    in `statusline.sh` (newlines for top, leading spaces for left). Note:
    Copilot itself injects/strips a `"staff": true` field at runtime based
    on org membership; keep that field out of the committed file to avoid
    spurious diffs.
  - `statusline.sh` — executable script printing the custom status line.
    Renders 11 segments separated by `│` (each shown only when its data is
    available): `<icon> <Label> <value>` — Time, Req, Run, API, Cache,
    Last, Repo (clean/dirty + ↑↓), Stash, Venv, GH, MCP. The whole line is
    wrapped in ANSI dim (`\e[2m`…`\e[0m`) so it recedes from the prompt.
    Env overrides: `COPILOT_STATUSLINE_NO_ICONS=1` drops icons (keeps text
    labels); `COPILOT_STATUSLINE_NO_DIM=1` drops the dim wrap;
    `COPILOT_STATUSLINE_PAD_TOP=N` / `..._PAD_LEFT=N` / `..._PAD_RIGHT=N`
    override per-side padding (default top=8, left=0, right=0). The CLI's
    `statusLine.padding*` fields are silently ignored — only `padding`
    works there, so we emit our own spacing instead. Run
    `~/.copilot/statusline.sh --test` to verify each codepoint renders in
    your terminal (uses `fc-list` if installed). Parses Copilot's session
    JSON from stdin (single `jq` call) and caches `gh auth status` for
    5 min. Bash 3.2-compatible. `install.sh` ensures the executable bit
    is set.
  - `copilot-instructions.md` — global agent instructions (autonomous mode).
- `<repo>/oh-my-zsh-custom/<file>` — files linked to
  `$HOME/.oh-my-zsh/custom/<file>`. Currently:
  - `custom.zsh` — aliases, proxy helpers (`enable_proxy`/`disable_proxy`),
    brew completions, `PATH` extras (`.NET`, Android SDK).
  - `gg.zsh` — defines `gg <title>` which sets the active terminal's tab +
    window title via OSC 1/2 escapes (works bare in Alacritty, WezTerm,
    iTerm2, …) AND, when `$TMUX` is set, calls `tmux rename-window` so
    tmux's status-bar window name is updated (the OSC 2 escape doesn't
    propagate through tmux because `.tmux.conf` keeps `allow-rename off`
    / `automatic-rename off`; tmux's `set-titles on` then bubbles
    `#S · #W` up to the outer terminal). For WezTerm specifically, also
    calls `wezterm cli set-tab-title` / `set-window-title` (guarded by
    `$WEZTERM_PANE` so it's a no-op when wezterm is on PATH but not the
    active terminal). Sets `DISABLE_AUTO_TITLE=true` so oh-my-zsh hooks
    don't overwrite the title during the session.

## How install.sh works
1. macOS only (auto-installs Homebrew apps and fonts; failures are warnings,
   never fatal — handles deprecated taps and conflicting casks gracefully).
   Set `SKIP_BREW=1` to skip the Homebrew step entirely (useful for CI /
   fake-`HOME` testing). Apps: `alacritty`, `wezterm`. Fonts: `font-recursive`,
   `font-recursive-mono-nerd-font`, `font-symbols-only-nerd-font`,
   `font-noto-color-emoji`. Formulae: `tmux`.
2. Symlinks every top-level `.<name>` file in the repo to `$HOME/.<name>`
   (currently `.tmux.conf`; also passes through `.gitignore` and a stray
   `.DS_Store` — both pre-existing, harmless on macOS).
3. Symlinks every file in `oh-my-zsh-custom/` to `~/.oh-my-zsh/custom/`.
   Skipped (with a warning) if `~/.oh-my-zsh/custom/` does not exist.
4. Symlinks every file in `copilot/` to `~/.copilot/`.
   Skipped (with a warning) if `~/.copilot/` does not exist.
5. Symlinks every file in `alacritty/` to `~/.config/alacritty/`. **Creates
   the destination directory if missing** (Alacritty only creates it on first
   launch).
6. Bootstraps TPM (Tmux Plugin Manager) if `tmux` is on PATH and `~/.tmux.conf`
   is present: clones `~/.tmux/plugins/tpm` if missing, then runs
   `tpm/bin/install_plugins` which spins up the default tmux server, loads
   `.tmux.conf` (which exports `TMUX_PLUGIN_MANAGER_PATH` via the tpm init
   line), and clones the plugins listed in `.tmux.conf`. Idempotent.
7. Existing destination files/links that don't match are renamed to
   `<name>.bak.YYYYMMDDHHMMSS` before linking.
8. Correct symlinks are left alone (no-op).

## Adding a new config
- New `~/.something` dotfile: drop `.something` at repo root, run `install.sh`.
- New oh-my-zsh customization: add a `*.zsh` file to `oh-my-zsh-custom/`,
  run `install.sh`. oh-my-zsh auto-loads files in alphabetical order.
- New Copilot CLI config: add a file to `copilot/`, run `install.sh`.
  Note: `mcp-config.json` is excluded (contains secrets) — manage it manually.
- New Alacritty config snippet: add a file to `alacritty/`, run `install.sh`.
  The destination directory is created automatically.
- Editing existing config: edit in this repo. Symlinks make changes live
  immediately on every machine (Alacritty: `[general] live_config_reload =
  true`; tmux: `prefix + r`; wezterm: auto-reloads).

## Sync workflow
```bash
# First time on a machine:
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
bash ~/Public/dot-configs/install.sh

# Pull updates:
cd ~/Public/dot-configs && git pull
# Re-run install.sh only if new files were added.
```

## Requirements (from configs)
- Apps: Alacritty (daily-driver as of `v0.5.0`), WezTerm (fallback for
  users who want native tabs/splits without tmux). oh-my-zsh required only
  for the `oh-my-zsh-custom/` part; Copilot CLI required only for the
  `copilot/` part.
- Tools: tmux ≥ 3.3 (3.6a tested) for the `.tmux.conf` features (TPM,
  OSC-52 set-clipboard, status-format extensions). git for TPM clone.
- Fonts (auto-installed): Recursive (Rec Mono St.Helens — part of the Rec
  Mono variable family), Recursive Mono Nerd Font, Symbols Only Nerd Font,
  Noto Color Emoji.
- Optional brew formulae sourced if present: `autojump`,
  `zsh-fast-syntax-highlighting`, `zsh-completions`.

## Notes
- Safe to re-run `install.sh` anytime; existing correct links are skipped.
- Backups are created only when a non-matching file/link exists.
- `oh-my-zsh-custom/custom.zsh` shadows oh-my-zsh's default
  `custom/custom.zsh` (which is gitignored upstream and irrelevant here).
- Validate the Alacritty config without launching the GUI:
  `alacritty migrate --dry-run --config-file alacritty/alacritty.toml`.
  (`migrate` exits 0 with `Successfully migrated` when the schema is sound.)
- Validate the tmux config without polluting your live tmux state:
  `tmux -f .tmux.conf -L _v new-session -d -s _v -x 200 -y 50 ; tmux -L _v kill-server`.
- The `copilot/settings.json` working-tree may show a tiny diff
  (`"padding": 0`) introduced by the Copilot CLI runtime — known noise; do
  not commit it as a real change.
- TPM plugin install: if the auto-bootstrap fails on a fresh box, run
  `prefix + I` inside tmux to retry, or `~/.tmux/plugins/tpm/bin/install_plugins`
  from any shell where tmux can start its default server.
