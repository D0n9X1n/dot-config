# 编辑器

[English](Editors.md) | 简体中文

本仓库同步 Zed 和 Neovide 设置。Neovim 本身在独立的 `nvim-config` 仓库中；本仓库从不修改它。

## Zed

`config/zed/settings.json` 链接到 `~/.config/zed/settings.json`。它包含主题、图标主题、字体、Vim 模式和 agent servers。新窗口会打开一个空标签页。编辑器工具栏整行隐藏：面包屑、快捷操作、Selections 菜单和 agent review 按钮都关闭，`code_actions` 默认已关闭。文件名只在标签页显示一次。

标签页标题比编辑器文字大。Zed 没有单独的标签页字号设置：标签页标题使用默认标签字号，即 `ui_font_size` 的 14/16。`ui_font_size` 为 `15`、`buffer_font_size` 为 `13` 时，标签页标题约为 13.1px。`scripts/check.sh editors` 会检查标签页标题始终大于编辑器文字。

Zed 会通过链接写入设置，因此在 Zed 中修改设置后，本仓库会出现 Git 改动。请提交它，或用 `git checkout` 丢弃。

### 文本文件的默认应用

在 macOS 上，`install.sh` 把 Zed 设为文本和代码文件的默认应用：纯文本、Markdown、JSON、YAML、TOML、XML、property list，以及源代码和脚本文件。列表在 `scripts/zed-default-types.txt`，每行一个统一类型标识符。`scripts/zed-defaults.js`（用 `osascript` 运行，不需要 Xcode）只为 Zed 尚未处理的类型请求 Launch Services。macOS 随后为每个类型弹出一个 “Use Zed?” 对话框；点 **Use "Zed"**。已经是 Zed 的类型不会改动，所以之后的安装不会再询问。设置 `SKIP_ZED_DEFAULTS=1` 可跳过此步骤。

有意不在列表中：`.ts`（macOS 把它识别为 MPEG-2 视频）、网页、CSV 和日志。查看某个类型现在用什么打开：

```sh
osascript -l JavaScript scripts/zed-defaults.js dev.zed.Zed check public.yaml
```

不同步：`~/.config/zed/themes/`（为空）和 `~/.config/zed/prompts/`（Zed 的本地 prompt 数据库）。

## Neovide

`config/neovide/config.toml` 链接到 `~/.config/neovide/config.toml`。它只设置 `fork = true`，所以从 shell 启动 `neovide` 后会立即返回提示符。

字体和 `guifont` 等 GUI 选项属于 Neovim 设置，因此保留在 `nvim-config` 中。

## `nv`

`config/zsh/nv.zsh` 提供 `nv`。它在同一个共享 Neovide 窗口中打开文件：

```sh
nv main.cc            # 打开文件
nv main.cc:42         # 打开并跳到第 42 行
nv main.cc:42:7       # 忽略列号
nv a.cc b.cc          # 打开多个文件
nv                    # 把窗口切到前台
```

第一次调用会用 `open -n -a Neovide` 在当前目录启动空的 Neovide，并让 Neovim 监听固定 socket。它最多等待 10 秒让 socket 就绪。之后每次调用都会用 `nvim --server --remote-send` 把文件发送到该窗口，并把窗口切到前台。窗口关闭后，下一次调用会启动新窗口。

Neovide 以空窗口启动，因为 dashboard 等 Neovim 启动插件可能替换命令行传入的文件。

| 设置 | 默认值 |
|---|---|
| `NV_SOCKET` | `$TMPDIR/neovide-nv.sock` |

`nv` 使用 `--remote-send`，因为 Neovim 停在 "Press ENTER" 提示时它仍然有效；`--remote-expr` 会在那里阻塞。按原样存在的路径不会被拆分，因此名为 `a:1` 的文件仍能打开。

`nv` 只适用于 macOS。

## 检查

```sh
scripts/check.sh editors
ls -l ~/.config/zed/settings.json ~/.config/neovide/config.toml
zsh -ic 'type nv'
```
