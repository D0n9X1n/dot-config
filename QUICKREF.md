# QUICKREF

Condensed, machine-readable summary for agents and skim reading. See
`ReadMe.md` for full details.

## Purpose
Personal dotfiles repo. Single source of truth for shell, terminal, and editor
configuration; synced across machines via git + an idempotent installer that
creates symlinks into `$HOME` (and `~/.oh-my-zsh/custom/`).

## Layout
- `install.sh` — single entry point; idempotent; safe to re-run.
- `<repo>/.<name>` — root dotfiles linked to `$HOME/.<name>`. **Currently
  none** (the previous `.wezterm.lua` was archived under `wezterm/` in
  `v0.4.0`).
- `<repo>/ghostty/<file>` — files linked to `$HOME/.config/ghostty/<file>`.
  The destination directory is created by `install.sh` if missing (Ghostty
  itself only creates it on first launch). Currently:
  - `config.ghostty` — Ghostty terminal config. `theme = Gruvbox Dark Hard`
    (note the spaces; verified built-in via `ghostty +list-themes`),
    `font-family = Rec Mono St.Helens`, `font-variation = wght=500`,
    `font-size = 14`, `adjust-cell-height = 10%` (line height 1.1 equiv),
    `window-padding-x/y = 8`, `unfocused-split-opacity = 0.4`,
    `macos-titlebar-style = tabs`. Keybinds override Ghostty defaults to
    match the previous WezTerm muscle memory: `super+d=new_split:down`,
    `super+shift+d=new_split:right`, `super+left/right=previous_tab/next_tab`,
    `ctrl+shift+arrow_*=goto_split:*`,
    `super+ctrl+alt+shift+arrow_*=resize_split:*,5`,
    `super+ctrl+alt+enter=toggle_split_zoom`. Validate locally with
    `ghostty +validate-config --config-file=ghostty/config.ghostty`.
- `<repo>/wezterm/<file>` — **archived previous terminal config; NOT
  auto-linked**. Kept so users mid-migration can manually run
  `ln -s "$(pwd)/wezterm/wezterm.lua" ~/.wezterm.lua`. Slated for removal
  in `v0.5.0`.
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
  - `gg.zsh` — defines `gg <title>` which sets the terminal tab + window
    title via OSC 1/2 escapes (works in Ghostty, WezTerm, iTerm2, …) and
    runs `command copilot --allow-all-tools --allow-all-paths --effort xhigh`.
    For WezTerm, also calls `wezterm cli set-tab-title` / `set-window-title`
    (no-op outside WezTerm). Sets `DISABLE_AUTO_TITLE=true` so oh-my-zsh
    hooks don't overwrite the title during the session.

## How install.sh works
1. macOS only (auto-installs Homebrew apps and fonts; failures are warnings,
   never fatal — handles deprecated taps and conflicting casks gracefully).
   Set `SKIP_BREW=1` to skip the Homebrew step entirely (useful for CI /
   fake-`HOME` testing).
2. Symlinks every top-level `.<name>` file in the repo to `$HOME/.<name>`.
3. Symlinks every file in `oh-my-zsh-custom/` to `~/.oh-my-zsh/custom/`.
   Skipped (with a warning) if `~/.oh-my-zsh/custom/` does not exist.
4. Symlinks every file in `copilot/` to `~/.copilot/`.
   Skipped (with a warning) if `~/.copilot/` does not exist.
5. Symlinks every file in `ghostty/` to `~/.config/ghostty/`. **Creates the
   destination directory if missing** (Ghostty only creates it on first
   launch).
6. Existing destination files/links that don't match are renamed to
   `<name>.bak.YYYYMMDDHHMMSS` before linking.
7. Correct symlinks are left alone (no-op).

## Adding a new config
- New `~/.something` dotfile: drop `.something` at repo root, run `install.sh`.
- New oh-my-zsh customization: add a `*.zsh` file to `oh-my-zsh-custom/`,
  run `install.sh`. oh-my-zsh auto-loads files in alphabetical order.
- New Copilot CLI config: add a file to `copilot/`, run `install.sh`.
  Note: `mcp-config.json` is excluded (contains secrets) — manage it manually.
- New Ghostty config snippet: add a file to `ghostty/`, run `install.sh`.
  The destination directory is created automatically.
- Editing existing config: edit in this repo. Symlinks make changes live
  immediately on every machine.

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
- Apps: Ghostty (daily-driver as of `v0.4.0`); WezTerm (legacy, kept for
  users mid-migration); oh-my-zsh required only for the `oh-my-zsh-custom/`
  part.
- Fonts (auto-installed): Recursive (Rec Mono St.Helens — part of the Rec Mono
  variable family), Recursive Mono Nerd Font, LXGW WenKai (currently unused;
  cleanup slated for `v0.5.0`), Symbols Only Nerd Font, Noto Color Emoji.
- Optional brew formulae sourced if present: `autojump`,
  `zsh-fast-syntax-highlighting`, `zsh-completions`.

## Notes
- Safe to re-run `install.sh` anytime; existing correct links are skipped.
- Backups are created only when a non-matching file/link exists.
- `oh-my-zsh-custom/custom.zsh` shadows oh-my-zsh's default
  `custom/custom.zsh` (which is gitignored upstream and irrelevant here).
- Validate the Ghostty config without launching the GUI:
  `ghostty +validate-config --config-file=ghostty/config.ghostty`.
- The `copilot/settings.json` working-tree may show a tiny diff
  (`"padding": 0`) introduced by the Copilot CLI runtime — known noise; do
  not commit it as a real change.
