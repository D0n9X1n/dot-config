# dot-configs

Simple dotfiles linker. Keep your dotfiles in this folder and symlink them into
your home directory.

## Usage
Run the installer:

```
/Users/d0n9x1n/Public/dot-configs/install.sh
```

It will:
- Install required apps and fonts on macOS (Homebrew required).
- Link every top-level dotfile in this folder into `$HOME`.
- Back up any existing destination file with a timestamp suffix.

## What it links
- Files that start with a dot at the top level of this folder.
- It does not link directories or nested files.

## Example
If this folder contains `.wezterm.lua`, it will create:

```
$HOME/.wezterm.lua -> /Users/d0n9x1n/Public/dot-configs/.wezterm.lua
```

## Keymaps
### WezTerm
- Split right (horizontal): Cmd+Ctrl+Alt+v
- Split down (vertical): Cmd+Ctrl+Alt+h
- Previous/next tab: Cmd+Left/Right
- Focus pane (direction): Cmd+Ctrl+Alt+Arrows
- Resize pane: Cmd+Ctrl+Alt+Shift+Arrows
- Toggle pane zoom: Cmd+Ctrl+Alt+Enter

## Requirements
### Apps
- WezTerm

### Fonts
- Recursive (Rec Mono Baker)
- Recursive Mono Nerd Font
- LXGW WenKai
- Symbols Only Nerd Font
- Noto Color Emoji
