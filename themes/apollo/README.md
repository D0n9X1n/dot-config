# Apollo

A warm-dark color theme. Gruvbox dark hard base + Material's warm beige
ANSI 7 (`#d4be98`) + a deeper canvas (`#141617`) for higher contrast.

See `PALETTE.md` for the full color table — single source of truth for
every file in this directory.

## Files

| File                         | Target              |
| ---------------------------- | ------------------- |
| `apollo.lua`                 | WezTerm color scheme |
| `apollo.vim`                 | Vim colorscheme     |
| `apollo.nvim.lua`            | Neovim colorscheme  |
| `apollo-color-theme.json`    | VS Code theme       |
| `apollo.terminal.json`       | Windows Terminal    |

## Install

### WezTerm

```lua
local apollo = dofile("/path/to/themes/apollo/apollo.lua")
config.color_schemes = { Apollo = apollo }
config.color_scheme  = "Apollo"
```

### Vim

```sh
mkdir -p ~/.vim/colors
ln -sf "$PWD/apollo.vim" ~/.vim/colors/apollo.vim
```

Then in `.vimrc`: `colorscheme apollo`

### Neovim

```sh
mkdir -p ~/.config/nvim/colors
ln -sf "$PWD/apollo.nvim.lua" ~/.config/nvim/colors/apollo.lua
```

Then in your init: `vim.cmd('colorscheme apollo')`

### VS Code (local extension)

```sh
mkdir -p ~/.vscode/extensions/apollo-theme-0.0.1/themes
ln -sf "$PWD/apollo-color-theme.json" \
  ~/.vscode/extensions/apollo-theme-0.0.1/themes/apollo-color-theme.json
# Plus a package.json — see the installed copy for reference.
```

Then set `"workbench.colorTheme": "Apollo"` in settings.json.

### Windows Terminal

Open `settings.json`, paste the contents of `apollo.terminal.json` into
the `"schemes"` array, then set `"colorScheme": "Apollo"` on the
profile(s) you want.
