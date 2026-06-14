# Copilot Instructions

Read `QUICKREF.md` at the repo root first — it is the single source of truth
for how this repository works. Keep it up to date when making changes.

`ReadMe.md` is the human-facing README; update it separately when user-visible
details change.

## Architecture

This is a dotfiles repository using a symlink-based linker pattern. `install.sh`
symlinks every **top-level non-ignored dotfile** (files starting with `.`) into
`$HOME`. Directories, nested files, and gitignored generated files are never
linked, with one explicit exception: `.sonicterm/` is tracked as an app config
directory, and `install.sh` links only its TOML config/keymap/theme files into
`~/.sonicterm/` so logs and runtime backups stay machine-local.
`.copilot-relay/config.yaml` is another explicit app-config file; only that
secret-free file is linked into `~/.copilot-relay/`, while relay tokens and logs
remain local and must not be committed.

Adding a new config means dropping a dotfile at the repo root — `install.sh`
picks it up automatically with no manifest to update. For SonicTerm, add TOML
under `.sonicterm/`, `.sonicterm/keymaps/`, or `.sonicterm/themes/`.

The install script also handles brand-new macOS bootstrap: installs Homebrew if
missing, installs Homebrew formulae/casks (including Claude Code via
`claude-code`), installs npm globals for Copilot CLI + `copilot-relay`, installs
oh-my-zsh, downloads custom RecMono fonts from `MOSconfig/recursive-code-config`,
and then links configs. On non-macOS systems it skips installation and only
links.

## Conventions

- **Shell scripts** use `set -euo pipefail` strict mode and POSIX-compatible
  patterns where possible.
- **WezTerm config** (`.wezterm.lua`) is Lua. It uses `wezterm.config_builder()`
  and adapts font weight and FreeType hinting at runtime based on display DPI
  (Retina vs non-Retina) via `window-config-reloaded` / `window-resized` events.
- Color scheme is **GruvboxDarkHard** throughout. Tab bar colors are defined as
  local constants at the top of the colors section — reuse those when adding
  UI elements.
- Tab rendering uses a custom `format-tab-title` handler with Nerd Font icons
  mapped per process name. To add icons for new tools, extend the
  `process_icons` table.

## How to test changes

There is no automated test suite. To verify:

- **Shell/install/statusline changes**: Run `scripts/check.sh all`.
- **install.sh behavior**: After `scripts/check.sh all`, test in a throwaway
  directory with `HOME=/tmp/test-home ./install.sh` when the change affects
  linking/bootstrap behavior.
- **.wezterm.lua**: Open WezTerm — it live-reloads on save. Check the debug
  overlay (`Ctrl+Shift+L`) for Lua errors.
