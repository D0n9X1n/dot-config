# Apollo 主题

[English](Apollo-Theme.md) | 简体中文

Apollo 是暖色深色主题。

它使用 Gruvbox Dark Hard 基础、暖米色 ANSI white 和深色 `#141617` 画布。

Apollo 是参考数据。`install.sh` 不会安装它。

## 文件

| 文件 | 目标 |
|---|---|
| `themes/apollo/palette.json` | 机器可读颜色源 |
| `themes/apollo/apollo.lua` | WezTerm |
| `themes/apollo/apollo.vim` | Vim |
| `themes/apollo/apollo.nvim.lua` | Neovim |
| `themes/apollo/apollo-color-theme.json` | VS Code |
| `themes/apollo/apollo.terminal.json` | Windows Terminal |

修改颜色时，请更新 `palette.json` 和所有目标文件。

## 主要颜色

| 作用 | Hex |
|---|---|
| 背景 | `#141617` |
| 前景 | `#ebdbb2` |
| 光标 | `#ebdbb2` |
| 选择背景 | `#3c3836` |
| 暗文字 | `#928374` |
| 文字 | `#d5c4a1` |
| 强调色 | `#fabd2f` |

ANSI 0–7：

```text
#1d2021 #cc241d #98971a #d79921 #458588 #b16286 #689d6a #d4be98
```

Bright 8–15：

```text
#928374 #fb4934 #b8bb26 #fabd2f #83a598 #d3869b #8ec07c #ebdbb2
```

## Vim

```sh
mkdir -p ~/.vim/colors
ln -sf "$PWD/themes/apollo/apollo.vim" ~/.vim/colors/apollo.vim
```

然后添加：

```vim
colorscheme apollo
```

## Neovim

```sh
mkdir -p ~/.config/nvim/colors
ln -sf "$PWD/themes/apollo/apollo.nvim.lua" ~/.config/nvim/colors/apollo.lua
```

然后使用：

```lua
vim.cmd('colorscheme apollo')
```

## WezTerm 参考

本仓库不管理 WezTerm app。需要手动使用旧参考主题时：

```lua
local apollo = dofile("/path/to/themes/apollo/apollo.lua")
config.color_schemes = { Apollo = apollo }
config.color_scheme = "Apollo"
```

## VS Code

把 `apollo-color-theme.json` 放入本机 VS Code theme extension，然后选择 `Apollo` workbench color theme。

## Windows Terminal

把 `apollo.terminal.json` 中的 object 放入 `schemes` 数组，然后把 profile 的 `colorScheme` 设为 `Apollo`。

## 检查

```sh
jq . themes/apollo/palette.json >/dev/null
```

当前 SonicTerm 主题是另一套配置。请看 [SonicTerm 与 Shell](SonicTerm-and-Shell-zh-CN.md)。
