# Apollo theme

English | [简体中文](Apollo-Theme-zh-CN.md)

Apollo is a warm dark color theme.

It uses a Gruvbox Dark Hard base, warm beige ANSI white, and a dark `#141617` canvas.

Apollo is reference data. `install.sh` does not install it.

## Files

| File | Target |
|---|---|
| `themes/apollo/palette.json` | Machine-readable color source |
| `themes/apollo/apollo.lua` | WezTerm |
| `themes/apollo/apollo.vim` | Vim |
| `themes/apollo/apollo.nvim.lua` | Neovim |
| `themes/apollo/apollo-color-theme.json` | VS Code |
| `themes/apollo/apollo.terminal.json` | Windows Terminal |

When a color changes, update `palette.json` and every target file.

## Main colors

| Role | Hex |
|---|---|
| Background | `#141617` |
| Foreground | `#ebdbb2` |
| Cursor | `#ebdbb2` |
| Selection background | `#3c3836` |
| Dim text | `#928374` |
| Text | `#d5c4a1` |
| Accent | `#fabd2f` |

ANSI 0–7:

```text
#1d2021 #cc241d #98971a #d79921 #458588 #b16286 #689d6a #d4be98
```

Bright 8–15:

```text
#928374 #fb4934 #b8bb26 #fabd2f #83a598 #d3869b #8ec07c #ebdbb2
```

## Vim

```sh
mkdir -p ~/.vim/colors
ln -sf "$PWD/themes/apollo/apollo.vim" ~/.vim/colors/apollo.vim
```

Then add:

```vim
colorscheme apollo
```

## Neovim

```sh
mkdir -p ~/.config/nvim/colors
ln -sf "$PWD/themes/apollo/apollo.nvim.lua" ~/.config/nvim/colors/apollo.lua
```

Then use:

```lua
vim.cmd('colorscheme apollo')
```

## WezTerm reference

The WezTerm app is not managed by this repo. To use the old reference theme manually:

```lua
local apollo = dofile("/path/to/themes/apollo/apollo.lua")
config.color_schemes = { Apollo = apollo }
config.color_scheme = "Apollo"
```

## VS Code

Put `apollo-color-theme.json` in a local VS Code theme extension, then select `Apollo` as the workbench color theme.

## Windows Terminal

Put the object from `apollo.terminal.json` in the `schemes` array, then set a profile's `colorScheme` to `Apollo`.

## Check

```sh
jq . themes/apollo/palette.json >/dev/null
```

The active SonicTerm theme is separate. See [SonicTerm and shell](SonicTerm-and-Shell.md).
