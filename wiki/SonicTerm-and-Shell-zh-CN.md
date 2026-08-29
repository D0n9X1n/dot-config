# SonicTerm 与 Shell

[English](SonicTerm-and-Shell.md) | 简体中文

SonicTerm 是当前外层终端。Zsh 文件提供日常助手和 CLI wrappers。

## SonicTerm 文件

清单会链接这些文件：

```text
config/sonicterm/sonicterm.toml
config/sonicterm/keymaps/*.toml
```

它们安装到 `~/.sonicterm/`。`install.sh` 还会验证固定的上游 Apollo release，并把其中的 `apollo.toml` 链接到 `~/.sonicterm/themes/`。

整个文件夹不会被链接。日志、save lock、备份和 crash 数据保留在本机。

## 主要终端设置

受管配置使用：

| 设置 | 值 |
|---|---|
| 主题 | `apollo`，来自固定的上游 release |
| Keymap | `sonicterm-macos` |
| 字体 | Rec Mono St.Helens，大小 14 |
| 行高 | 1.2 |
| 新窗口网格 | 100 × 30 |
| Scrollback | 1000 行 |
| 光标 | block，不闪烁 |
| 背景 | opaque |
| 软件渲染模式 | auto |
| 子进程身份 | `TERM_PROGRAM=SonicTerm` |

修改配置后，在 SonicTerm command palette 中使用 **Reload Config**。有些原生窗口修改可能需要重启。

名为 `wezterm` 的 keymap 保留旧按键兼容。当前主题是 Apollo，SonicTerm 仍会告诉子 shell 它的真实名称。

## RMUX 身份

普通 SonicTerm shell 看到：

```text
TERM_PROGRAM=SonicTerm
```

RMUX 中的 shell 看到：

```text
TERM_PROGRAM=rmux
```

只有 Copilot 子进程会收到进程级 WezTerm 兼容名称。请看 [Copilot CLI](Copilot-CLI-zh-CN.md)。

RMUX 会向外层 SonicTerm 客户端声明 `xterm-256color:RGB:osc7`，并保持 `set-titles` 开启。Oh My Zsh 会在每次显示提示符时发出带主机名的 OSC 7 报告，因此 RMUX 可以把活动 pane 的准确工作目录转发给 SonicTerm。这样 SonicTerm 就能按正确 pane 解析相对路径和 bare file name。修改外层终端能力后，请重载 RMUX 并 detach/reattach。

RMUX 配置会明确保留条件式鼠标 bindings。Copilot 等支持鼠标的内层应用会收到完整鼠标事件流；否则拖动会进入 RMUX copy mode。Shift-drag 会绕过 mouse reporting，在 SonicTerm 本地选择文字。请看 [RMUX](RMUX-zh-CN.md)。

## Zsh 文件

`config/zsh/` 下的文件安装到 `~/.oh-my-zsh/custom/`。Oh-my-zsh 按名称顺序加载它们。

| 文件 | 作用 |
|---|---|
| `custom.zsh` | Apollo prompt 选择、eza/Base16 路径、aliases、proxy 助手、补全、SDK 路径 |
| `themes/apollo.zsh-theme` | Prompt 结构；读取本机生成的 Apollo 颜色 |
| `claude.zsh` | Claude wrapper 和固定启动 flags |
| `cc.zsh` | 带标题的 Claude 启动器 |
| `copilot.zsh` | Copilot 真彩色 wrapper 和清理 |
| `gg.zsh` | 带标题的 Copilot 启动器 |
| `zz-rmux.zsh` | RMUX 会话和安全分离助手；最后加载 |

## 小 aliases

```text
ls      eza
ll      eza -l
c       cd ..
vim     nvim
proxy   启用 SOCKS5 proxy
unproxy 关闭 proxy
```

Proxy 地址是 `127.0.0.1:46971`。助手会修改 shell、Git 和 npm proxy 设置。

## 补全与路径

`custom.zsh` 会在 Oh My Zsh 加载主题前选择受管 Apollo prompt。它不会修改 `.zshrc`。它还会让 eza 使用固定的上游主题。

安装 fast-syntax-highlighting 后，安装器会在独立本机工作目录中准备它自带的 Base16 主题。语法颜色随后使用 SonicTerm 的 Apollo ANSI slots。`custom.zsh` 也会加载 autojump、添加 Homebrew 补全、在 `compinit -i` 前修复 group-writable 补全文件夹，并添加本机 .NET 与 Android SDK 路径。

## RMUX 助手

`zz-rmux.zsh` 最后加载，所以它的函数会覆盖前面的 shell 定义。

```sh
rr main       # main 存在时连接；只有不存在时才创建
rl            # 列出会话
rd main       # 删除 main
```

它永远不会自动连接新标签页。

在 RMUX 中：

- `exit` 会分离；
- `logout` 会分离；
- 空提示符上的 Ctrl+D 会分离；
- 有文字时，Ctrl+D 保持正常 ZLE 行为。

在 RMUX 外，`exit`、`logout` 和 Ctrl+D 保持普通 shell 行为。

## 标题

`cc [标题]` 和 `gg [标题]` 会向 SonicTerm 发送 OSC 1 和 OSC 2 标题。在 RMUX 中，它们也会重命名 RMUX 窗口。没有标题时，它们使用当前路径。

CLI 运行时会设置 `DISABLE_AUTO_TITLE`，所以 oh-my-zsh 不会覆盖标题。

## 检查

```sh
zsh -n config/zsh/*.zsh
zsh -ic 'type rr rd rl cc gg; print -r -- "$ZSH_THEME $EZA_CONFIG_DIR $FAST_WORK_DIR"'
grep -F 'theme = "apollo"' ~/.sonicterm/sonicterm.toml
ls -l ~/.sonicterm/themes/apollo.toml ~/.config/eza-apollo-theme/theme.yml
scripts/check.sh rmux
```

会话模型请看 [RMUX](RMUX-zh-CN.md)。
