# 原生 tmux

[English](Tmux.md) | 简体中文

原生 tmux 与 [RMUX](RMUX-zh-CN.md) 并存。两者使用相同的 Apollo 配色和底部标签样式，但服务器、会话和恢复状态各自独立。受管配置面向 tmux 3.7c。`install.sh` 安装 Homebrew tmux，并把 `config/tmux/tmux.conf` 链接到 `~/.tmux.conf`。

## 启动与重连

安装后打开新 shell：

```sh
tt main       # 精确创建或恢复 main
tr main       # 与 tt main 相同
tl            # 列出会话，不启动服务器
td main       # 永久结束 main 及其中的程序
th            # 助手帮助和恢复限制
ts            # 确认、保存、重启并恢复当前服务器的工作区
```

RMUX 的 `rr`、`rl`、`rd`、`rh`、`rs` 保持可用。新的 SonicTerm 标签页仍打开普通 shell，不会自动连接任一复用器。

`tr NAME` 是交互式快捷命令。普通双参数或带选项的调用仍使用系统文本工具。可用 `command tr` 或 `/usr/bin/tr` 明确选择系统工具。

助手直接调用真实的 Homebrew tmux，不使用 `PATH` 中的 `tmux` shim。外部 shell 使用默认 socket；原生 tmux 内使用当前 socket，`tt` 切换已连接客户端而不嵌套连接。请先从 RMUX 分离，再运行 `tt` 或 `tr`；RMUX 的兼容 `TMUX` 变量不是原生 tmux 连接。

## 服务器生命周期

新服务器由 `tt`、`tr` 以分离方式创建；连接前，助手会验证服务器的**父 PID 为 1**。SonicTerm 拥有连接客户端，不拥有服务器。已有服务器会被复用，不重启，也不强制更换父进程。

在原生 tmux 中，`exit`、`logout`、空提示符 Ctrl+D 和 `prefix + d` 都只分离客户端。shell 编辑缓冲区有文字时，Ctrl+D 保持原有行为。关闭 SonicTerm 标签页或退出 SonicTerm 会断开客户端，服务器和窗格程序继续运行。用 `tt NAME` 重连即可；退出终端前不需要运行 `ts`。

只有想停止会话时才使用 `td NAME`。父 PID 为 1 不能防止服务器崩溃、系统关机、显式终止或最后一个窗格退出。

## 外观与操作

配置保留 RMUX 的可见设计：

- C-q prefix、底部单行状态栏、鼠标支持和 Vi 复制模式。
- 固定官方 tmux Apollo 主题提供状态栏、边框、消息和复制模式配色。
- 相同的斜边会话/窗口标签、间距、带编号的应用图标、深蓝底加粗白字的活动标签，以及状态栏底色的非活动标签。
- 图标与标题之间一个空格。图标跟随 Claude、Copilot、Vim/Neovim 或后备终端命令，不依赖自定义标题。
- `PREFIX`、`ZOOM`、活动/响铃状态和普通 `HH:MM` 时钟。
- 新窗格和窗口继承当前窗格的工作目录。

见 [tmux 按键表](Tmux-Keymap-zh-CN.md)。`cc` 和 `gg` 通过原生助手重命名当前 tmux 窗口；它们的 RMUX 行为和启动默认值保持独立。

安装器把验证后的主题链接到 `~/.config/tmux-apollo-theme/apollo.tmux`。不会安装 TPM、执行旧插件初始化，也不会加载归档的 tmux 配置。已有插件和 resurrect 目录保留不动。

## 重命名与提示框输入

使用 `prefix + n` 或 `prefix + ,`。提示框以 Vi 插入模式打开。Ctrl+W 删除前一个词，Ctrl+U 清空输入，Ctrl+G 在插入模式中取消。Escape 切换到 Vi 命令模式；在该模式用 `q` 或 Ctrl+C 取消。

受管提示框把引号、反斜杠、`#{...}`、`#(...)` 和分号当作标题文字，不执行为命令。目标始终是打开提示框时的窗口。提交空名称会为该窗口恢复基于当前应用的自动命名；随后设置自定义名称会再次关闭自动命名。运行中应用的图标始终保留。

原生 tmux 的窗口名称字段存储转义后的反斜杠；受管标题显示和提示框只显示一份字面反斜杠。需要精确保留文字时优先使用受管提示框；原始 `tmux rename-window` 有自己的格式展开规则。

此原生配置不会修复 [RMUX 独立的提示框问题](https://github.com/D0n9X1n/dot-config/issues/60)。

## 终端输入与集成

窗格保留原生 `TERM=tmux-256color` 和 `TERM_PROGRAM=tmux`。配置清除陈旧 terminfo 覆盖并设置真彩色变量，不冒充 SonicTerm 或 WezTerm；只有 Copilot 子进程保留文档中的 WezTerm 兼容覆盖。

扩展按键协商让 Shift+Enter 与 Enter 保持区别。请求该协议的窗格应用收到扩展 Shift+Enter；未请求的应用收到原生配置发送的 Ctrl+J。普通 Enter 不变。修改外层键盘能力后，请重载并分离/重连客户端，以重新协商。

OSC 7 目录报告、标题、条件式鼠标转发、`pbcopy` 和 OSC 52 与 RMUX 配置一致。剪贴板权限信任窗格程序：`set-clipboard on` 允许它们更新主机剪贴板。如果窗格应用不可信，请改用 `external`。

RMUX 的私有 teammate shim 仍只作用于对应进程。安装原生 tmux 不会替换它。离线配置测试不会运行真实模型驱动的 teammate 会话。

## 升级与恢复

```sh
brew upgrade tmux
ts
```

`ts` 是可选且会停止程序的操作：明确确认后，它会结束**所选 tmux socket 上的全部程序**，保存该服务器的全部会话，包括已分离会话。不会重启其他 socket 或 RMUX。

助手在停止服务器前验证稳定的工作区和服务器代次。独立于调用窗格的工作进程用新 shell 恢复会话/窗口名称、编号、尺寸、窗格布局、目录和活动选择。它不会恢复程序、内存、滚动历史、未保存缓冲区或环境，也不会重放捕获的命令。

不支持的分组/链接窗口、已结束/缩放窗格或不稳定布局会在停止前被拒绝。目录缺失时警告并回退到 HOME。恢复失败保留原快照；重试不会自动结束部分恢复后的服务器。

私有状态按 socket 分别保存在 `~/.local/state/tmux-store/` 下，不得提交。没有定时保存、LaunchAgent 或系统启动后的自动恢复。

与 RMUX 保留配套二进制不同，原生 tmux 使用兼容的已安装 Homebrew 可执行文件及其依赖。客户端或依赖缺失/不兼容时安全失败，不保证任意 Homebrew 依赖清理后仍可重连。不会复制单个二进制、重定位动态库或设置全局库路径覆盖。

## 应用与验证

```sh
scripts/check.sh all
./install.sh
./install.sh
ls -l ~/.tmux.conf ~/.config/tmux-apollo-theme/apollo.tmux
th
```

新服务器读取已安装配置。安装过程不会重载或重启已有 tmux 服务器。准备更新现有服务器时，使用 `prefix + r`；终端能力有变化时再分离/重连。

测试只使用私有 socket 和临时 HOME，不要对常用 socket 执行测试用 `kill-server`。PTY 字节测试验证原生提示框和按键转发，不代表已捕获物理 macOS 按键，也不保证所有终端和字体的像素渲染完全相同。
