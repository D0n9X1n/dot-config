# QUICKREF

## Purpose
This folder is a minimal dotfiles linker. It keeps dotfiles in the repo and
creates symlinks into $HOME so the programs read them from this repo.

## How it works
- `install.sh` installs required apps and fonts (macOS + Homebrew).
- `install.sh` scans only top-level dotfiles in this folder (files starting
  with a dot).
- For each dotfile, it creates a symlink in `$HOME` with the same name.
- If a file already exists at the destination, it is backed up with a
  timestamp suffix: `.bak.YYYYMMDDHHMMSS`.
- If a correct symlink already exists, it is left alone.

## What gets linked
- Top-level dotfiles only, not directories.
- Example: `.wezterm.lua` -> `$HOME/.wezterm.lua`

## Requirements (from configs)
- Apps: WezTerm
- Fonts: Recursive (Rec Mono Baker), Recursive Mono Nerd Font, LXGW WenKai,
  Symbols Only Nerd Font, Noto Color Emoji

## Usage
Run from anywhere:

```
/Users/d0n9x1n/Public/dot-configs/install.sh
```

## Notes
- Safe to re-run; existing correct links are skipped.
- Backups are created only when a non-matching file/link exists.
