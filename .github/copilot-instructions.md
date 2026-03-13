# Copilot Instructions

Read `QUICKREF.md` at the repo root first — it is the single source of truth
for how this repository works. Keep it up to date when making changes.

`ReadMe.md` is the human-facing README; update it separately when user-visible
details change.

## Architecture

This is a dotfiles repository using a symlink-based linker pattern. `install.sh`
symlinks every **top-level dotfile** (files starting with `.`) into `$HOME`.
Directories and nested files are never linked.

Adding a new config means dropping a dotfile at the repo root — `install.sh`
picks it up automatically with no manifest to update.

The install script also handles macOS dependency installation via Homebrew
(apps and fonts). On non-macOS systems it skips installation and only links.

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

- **install.sh**: Run `bash -n install.sh` for syntax checking, then test in a
  throwaway directory with `HOME=/tmp/test-home ./install.sh`.
- **.wezterm.lua**: Open WezTerm — it live-reloads on save. Check the debug
  overlay (`Ctrl+Shift+L`) for Lua errors.
