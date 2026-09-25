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
| 字体 | Rec Mono St.Helens，大小 13.5 |
| 字重缩放 | 1 |
| 行高 | 1.1 |
| 新窗口网格 | 80 × 40 |
| 顶部 / 底部留白 | 4 / 0 逻辑像素 |
| Scrollback | 1000 行 |
| 数字键盘模式 | `numeric`：传统输入使用普通数字、运算符和回车；Kitty 协议保持不变 |
| 光标 | block，不闪烁 |
| 背景 | opaque |
| 软件渲染模式 | auto |
| 子进程身份 | `TERM_PROGRAM=SonicTerm` |

修改配置后，在 SonicTerm command palette 中使用 **Reload Config**（`Cmd+Shift+R`）。有些原生窗口修改可能需要重启。

顶部留白为 4 逻辑像素；底部留白为零，去掉原生标签栏上方的配置边距。终端只能显示完整文字行，因此仍可能留下不足一行的空隙，其大小取决于窗口高度。`panel_padding` 只影响弹出面板，不影响这里的空隙。

当前 keymap 是 `sonicterm-macos`；仓库也管理 `sonicterm-linux` 和 `sonicterm-windows`。它们的自定义按键保持不变。外观使用 `[appearance]`；已省去无效的旧 window 和 render 配置项。

## 终端身份

普通 SonicTerm shell 看到：

```text
TERM_PROGRAM=SonicTerm
```

RMUX 中的 shell 看到：

```text
TERM_PROGRAM=rmux
```

原生 tmux 窗格保留 `TERM_PROGRAM=tmux`，不冒充 RMUX。只有 Copilot 子进程会收到进程级 WezTerm 兼容名称，外层 shell 保留真实身份。请看 [Copilot CLI](Copilot-CLI-zh-CN.md) 和 [Tmux](Tmux-zh-CN.md)。

RMUX 会向外层 SonicTerm 客户端声明 `xterm-256color:RGB:osc7`，并保持 `set-titles` 开启。Oh My Zsh 会在每次显示提示符时发出带主机名的 OSC 7 报告，因此 RMUX 可以把活动 pane 的准确工作目录转发给 SonicTerm。这样 SonicTerm 就能按正确 pane 解析相对路径和 bare file name。修改外层终端能力后，请重载 RMUX 并 detach/reattach。

RMUX 配置会明确保留条件式鼠标 bindings。Copilot 等支持鼠标的内层应用会收到完整鼠标事件流；否则拖动会进入 RMUX copy mode。Shift-drag 会绕过 mouse reporting，在 SonicTerm 本地选择文字。请看 [RMUX](RMUX-zh-CN.md)。

## Zsh 文件

`config/zsh/` 下的文件安装到 `~/.oh-my-zsh/custom/`。Oh-my-zsh 按名称顺序加载它们。

| 文件 | 作用 |
|---|---|
| `custom.zsh` | eza/Base16 路径、aliases、proxy 助手、补全、SDK 路径 |
| `terminal-keys.zsh` | ZLE 提示符编辑使用的精确终端按键序列 |
| `themes/apollo.zsh-theme` | Prompt 结构；读取本机生成的 Apollo 颜色 |
| `claude.zsh` | Claude wrapper 和固定启动 flags |
| `cc.zsh` | 带标题的 Claude 启动器 |
| `copilot.zsh` | allow-all Copilot alias、真彩色 wrapper 和清理 |
| `gg.zsh` | 带标题、allow-all 的 Copilot 启动器 |
| `zz-rmux.zsh` | RMUX 助手和共享安全分离分派器；较晚加载 |
| `zz-tmux.zsh` | 原生 tmux 会话助手和交互式 `tr` 分派 |

## 提示符中的 Command-Backspace

`terminal-keys.zsh` 在 `emacs` 和 `viins` keymap 中，将 SonicTerm 默认的 Cmd+Backspace 序列 `ESC [ 127 ; 9 u` 绑定到 ZLE 内置的 `backward-kill-line`。它删除光标到当前逻辑行开头之间的文字，并保留光标右侧的内容。它不会切换编辑模式、修改 Ctrl+U / Option+Backspace / Ctrl+Backspace，也不会改变传给 Vim、less、tmux 或 RMUX 的按键。

安装后打开新终端标签页即可生效。若只想在已有 zsh 提示符中应用这项绑定，请运行：

```zsh
source ~/.oh-my-zsh/custom/terminal-keys.zsh
```

这是 shell 绑定，不是 SonicTerm 编码器修改，也不修复复用器的重命名提示框。它覆盖已报告的默认终端模式；DECBKM 或 modifyOtherKeys 可能产生不同序列。回归测试使用独立的真实 ZLE/PTY，覆盖行中光标、空内容、Unicode 和多行缓冲区，不模拟物理键盘事件。

## 小 aliases

```text
ls      eza
ll      eza -l
c       cd ..
vim     nvim
proxy   启用 SOCKS5 proxy
unproxy 关闭 proxy
copilot 以 allow-all / YOLO 权限启动 Copilot
```

Proxy 地址是 `127.0.0.1:46971`。助手会修改 shell、Git 和 npm proxy 设置。

`copilot` 和 `gg` 会自动添加 `--yolo`，允许工具、路径和 URL，不再请求批准。不需要手动附加默认 flags。`copilot` alias 保留参数转发和成功更新后的清理；权限默认值与现有 shell 的重新加载方法见 [Copilot CLI](Copilot-CLI-zh-CN.md)。

## Homebrew 更新

`custom.zsh` 导出 `HOMEBREW_NO_AUTO_UPDATE=1`。`brew install` 和 `brew upgrade` 等命令会跳过自动更新软件包目录及其提示。需要最新软件包版本时，请先手动运行 `brew update`，再升级。

打开新 shell 即可生效，也可以在现有 shell 中运行 `export HOMEBREW_NO_AUTO_UPDATE=1`。

## 补全与路径

提示符主题由 `.zshrc` 中的 `ZSH_THEME` 选择。受管 zsh 助手不会设置或覆盖它，安装器也不会修改 `.zshrc`。需要时仍可在该文件中选择 Apollo。`custom.zsh` 会让 eza 使用固定的上游主题。

安装 fast-syntax-highlighting 后，安装器会在独立本机工作目录中准备它自带的 Base16 主题。语法颜色随后使用 SonicTerm 的 Apollo ANSI slots。`custom.zsh` 也会加载 autojump、添加 Homebrew 补全、在 `compinit -i` 前修复 group-writable 补全文件夹，并添加本机 .NET 与 Android SDK 路径。

## rX 助手

`zz-rmux.zsh` 较晚加载，所以它的函数会覆盖前面的 shell 定义。平台规则：Windows 使用 RMUX；macOS 和 Linux 使用原生 tmux。

在 macOS 和 Linux 上，每个 `rX` 助手都运行对应的 `tX`。没有 `rmux` shell 函数。

```sh
rr main       # 等同于 tt main
rl            # 等同于 tl
rd main       # 等同于 td main
rh            # 等同于 th
rs            # 等同于 ts
```

在 Windows zsh（`msys`、`cygwin` 或 `win32`）上，助手保持 RMUX 行为：

```sh
rr main       # main 存在时连接；只有不存在时才创建
rl            # 列出会话
rd main       # 删除 main
rs            # 保存全部会话，确认重启后恢复
rh            # 助手、父 PID 1、升级步骤
```

所有助手都不会自动连接新标签页。`rr` 新启动的服务器必须在连接前具有父 PID 1；终端只拥有连接客户端。已有服务器保持不变。用 `brew upgrade rmux` 升级，准备好以新 shell 重建全部会话时再执行 `rs`。受管 `rmux` shell 函数会保留与当前服务器兼容的客户端版本。快照限制请看 [RMUX](RMUX-zh-CN.md)。

## 原生 tmux 助手

`zz-tmux.zsh` 提供独立的一组助手：

```sh
tt main       # 按完整名称连接，仅在不存在时创建
tr main       # 交互式 shell 中 tt main 的快捷方式
tl            # 列出会话，不启动服务器
td main       # 按完整名称删除会话
th            # 帮助与重启警告
ts            # 保存此 socket 的全部会话，确认后重启并恢复
```

`tr` 只在交互式 zsh 中定义为 shell 函数，不是可执行文件或 alias。恰好一个非选项参数会交给 `tt`。普通的双参数和选项形式仍调用文本工具。用 `command tr` 可显式调用文本工具。

复用器之外，原生助手使用 tmux 默认 socket；原生 tmux 内使用当前 socket。`tt` 拒绝从 RMUX 嵌套连接，请先分离。两组助手都不会自动连接新标签页。

`tt`/`tr` 以分离的引导进程创建新服务器，并在**连接前验证父 PID 为 1**。已有服务器直接复用，不重启，也不强制更换父进程。退出 SonicTerm 只会断开客户端，服务器继续运行，不需要先执行 `ts`。只有主动删除时才使用 `td`。父 PID 为 1 不能让运行中的进程跨服务器崩溃或系统重启保留。

`ts` 影响所选 socket 的全部会话，包括已分离的会话。它需要稳定且有效的快照、兼容二进制、通过预检，并要求交互式输入 `yes`。恢复会用新 shell 重建保存的名称、目录、布局、尺寸和活动选择。不重放进程，不恢复历史，也没有自动保存。永远不要自动运行 `ts` 或 `rs`。完整的 socket 和升级规则见 [Tmux](Tmux-zh-CN.md)。

## 安全分离

`zz-rmux.zsh` 中已有的分派器处理两个引擎。因为 RMUX 也导出 `TMUX`，所以先检查 `RMUX`，再检查原生 tmux。

在任一引擎中：

- `exit` 会分离；
- `logout` 会分离；
- 空提示符上的 Ctrl+D 会分离；
- 有文字时，Ctrl+D 保持正常 ZLE 行为。

在两个引擎之外，`exit`、`logout` 和 Ctrl+D 保持普通 shell 行为。

## 标题

`cc [标题]` 和 `gg [标题]` 会向 SonicTerm 发送 OSC 1 和 OSC 2 标题。它们先检查 RMUX 并直接重命名其窗口；在原生 tmux 中，通过 `tmux-store` 重命名当前 socket 的当前窗口。没有标题时使用当前路径。

原生路径不会修改 `PATH`，也不会替换全局 `tmux` 命令。RMUX 的私有 teammate shim 保持独立。CLI 运行时会设置 `DISABLE_AUTO_TITLE`，所以 oh-my-zsh 不会覆盖标题。

`claude` 和 `cc` 默认使用原生 `claude-opus-5-5[1m]` 与 `--effort xhigh`；relay 将其映射到 `claude-opus-5.5`。`gg` 保留独立的 Astra/`high` 默认值。安装后打开新 shell，或按 [Claude Code](Claude-Code-zh-CN.md) 中的步骤重载。

原生 tmux 3.7 使用 `status-keys vi` 时，Esc 切换提示框模式，`C-g` 才是取消。这不修复 RMUX 独立的[提示框问题 #60](https://github.com/D0n9X1n/dot-config/issues/60)。请看[原生按键表](Tmux-Keymap-zh-CN.md)。

## 检查

```sh
zsh -n config/zsh/*.zsh
zsh -ic 'type tt tr tl td th ts rr rd rl rh rs cc gg; print -r -- "$ZSH_THEME $EZA_CONFIG_DIR $FAST_WORK_DIR"'
grep -F 'theme = "apollo"' ~/.sonicterm/sonicterm.toml
ls -l ~/.sonicterm/themes/apollo.toml ~/.config/eza-apollo-theme/theme.yml
scripts/check.sh rmux
scripts/check.sh tmux
```

会话模型请看 [Tmux](Tmux-zh-CN.md) 和 [RMUX](RMUX-zh-CN.md)。
