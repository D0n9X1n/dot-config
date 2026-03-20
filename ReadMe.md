# dot-configs

Simple dotfiles linker. Keep your dotfiles in this folder and symlink them into
your home directory.

## Usage

Run the installer:

```bash
./install.sh
```

It will:

- Install required apps and fonts on macOS (Homebrew required).
- Link every top-level dotfile (files starting with `.`) into `$HOME`.
- Back up any existing destination file with a `.bak.YYYYMMDDHHMMSS` suffix.
- Skip files that are already correctly symlinked.

Safe to re-run at any time.

## What it links

Only top-level dotfiles in this folder (not directories or nested files).

Example: `.wezterm.lua` → `$HOME/.wezterm.lua`

## Included configs

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
| Primary (EN) | RecMonoBaker Nerd Font | 14pt |
| CJK fallback | LXGW WenKai Mono | scaled 17/14 |
| Icons/Powerline | Symbols Nerd Font Mono | — |
| Emoji | Noto Color Emoji | — |

- **Line height:** 1.2
- **Weight:** Auto-detects Retina displays — uses Regular on Retina, DemiBold on non-Retina.
- **Bold:** Native bold rendering enabled, `bold_brightens_ansi_colors` disabled.
- `custom_block_glyphs` disabled for correct Powerline/NERD glyph rendering.

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
| Split right (horizontal) | `Cmd+Ctrl+Alt+V` |
| Split down (vertical) | `Cmd+Ctrl+Alt+H` |
| Previous tab | `Cmd+←` |
| Next tab | `Cmd+→` |
| Focus pane (direction) | `Ctrl+Shift+Arrows` |
| Resize pane (small steps) | `Cmd+Ctrl+Alt+Shift+Arrows` |
| Toggle pane zoom | `Cmd+Ctrl+Alt+Enter` |

#### Other settings

| Setting | Value |
|---|---|
| TERM | `xterm-256color` |
| Scrollback lines | 20,000 |
| Audible bell | Disabled |

## Requirements

### Apps

- [WezTerm](https://wezfurlong.org/wezterm/)

### Fonts (installed automatically via Homebrew)

- Recursive (Rec Mono Baker) — `font-recursive`
- Recursive Mono Nerd Font — `font-recursive-mono-nerd-font`
- LXGW WenKai — `font-lxgw-wenkai`
- Symbols Only Nerd Font — `font-symbols-only-nerd-font`
- Noto Color Emoji — `font-noto-color-emoji`

## License

See [LICENSE](LICENSE).
