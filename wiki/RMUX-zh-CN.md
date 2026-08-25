# RMUX

[English](RMUX.md) | 简体中文

本仓库使用 RMUX 0.10.x 作为终端复用器。受管源文件是 `config/rmux/rmux.conf`；`install.sh` 会把它链接到 `~/.rmux.conf`，并在新 Mac 上安装 Homebrew `rmux` formula。

## RMUX 是什么

RMUX 是一个独立实现的 Rust 终端复用器，采用客户端/守护进程架构。守护进程负责 shell、PTY、会话（session）、窗口（window）、窗格（pane）、回滚缓冲区、选项和进程生命周期。客户端通过本地 IPC 连接；客户端分离后，这些进程仍可继续运行。

```mermaid
flowchart LR
    T[外层终端：SonicTerm] --> C[rmux 客户端]
    C <--> D[通过本地 IPC 连接 rmux-daemon]
    D --> S[会话 Sessions]
    S --> W[窗口 Windows]
    W --> P[窗格与 PTY]
```

RMUX 不是：

- 终端模拟器：文本渲染、字体、原生标签页和窗口仍由外层终端负责；
- 对现有 tmux server 的封装：它拥有自己的守护进程和 socket 命名空间；
- 与 tmux 字节级完全一致的克隆：它实现了广泛的 tmux 命令和配置兼容层，同时保留有文档说明的差异。

通常每个 socket 对应一个守护进程。`-L name` 选择独立的命名 socket，`-S path` 选择明确的 socket 路径。默认生命周期允许客户端分离后会话继续运行，但守护进程退出或系统重启后不会自动从磁盘恢复。

## 配置搜索顺序

在 macOS 和 Linux 上，RMUX 0.10.0 按以下位置查找原生配置：

```text
/etc/rmux.conf
~/.rmux.conf
$XDG_CONFIG_HOME/rmux/rmux.conf
~/.config/rmux/rmux.conf
```

只有在没有加载任何原生配置时，RMUX 才可能回退到标准 tmux 配置路径。本仓库刻意避免这种回退：已归档的 tmux 配置包含可执行的 TPM 初始化命令。原生 `~/.rmux.conf` 可以让启动行为保持确定。诊断时也可设置 `RMUX_DISABLE_TMUX_FALLBACK=1` 禁用回退。

RMUX 使用 tmux 命令语法，不是 JSON、YAML 或 TOML。配置可以执行 `run-shell`、条件命令和其他 source 文件，因此必须把它当作可执行代码审查。

## 本仓库采用的配置

当前配置以 RMUX v0.10.0 的 human-friendly 示例为基础，并有选择地迁移原 tmux 配置中兼容的行为。

| 设置 | 本仓库取值 |
|---|---|
| Prefix | `C-q`；`prefix + C-q` 向窗格发送字面量 `C-q` |
| 重载 | `prefix + r` |
| 鼠标 | 默认开启；`prefix + T` 切换外层终端原生选择 |
| 历史 | 100000 行 |
| 窗口/窗格编号 | 从 1 开始；关闭窗口后自动重排 |
| 复制模式 | Vi 按键；`pbcopy` 加 OSC 52 |
| 状态栏 | 顶部、手工 Gruvbox Dark Hard 配色 |
| 标题 | 禁用自动重命名；向外传播 `#S · #W` |
| 终端身份 | `TERM=tmux-256color`；保留 `TERM_PROGRAM=rmux` |

配置会清除守护进程可能继承的陈旧 `TERMINFO`、`TERMINFO_DIRS` 和 `TERMCAP`，然后设置 `COLORTERM=truecolor` 与 `FORCE_COLOR=3`。它不会清除 RMUX 自己的 `TERM_PROGRAM` 身份。

## 会话助手与恢复

新的 SonicTerm 标签页会打开普通 shell。最后加载的 `zz-rmux.zsh` 提供显式助手：

```sh
rr main       # 创建或恢复 main
rl            # 列出所有会话
rd main       # 删除 main
```

`rr <名称>` 会先检查会话是否存在：存在时执行 `attach-session`，只有不存在时才执行 `new-session`，并打印所选择的路径。`rd <名称>` 执行 `kill-session`，因此会永久结束该会话。SonicTerm 使用真实的 `TERM_PROGRAM=SonicTerm`；只有 Copilot 子进程会收到 WezTerm 兼容身份。

在 RMUX 中，zsh 助手会把 `exit`、`logout` 以及空提示符上的 Ctrl+D 转换为 `detach-client`。编辑缓冲区中有文字时，Ctrl+D 仍保持正常的删除 / 列表行为。`prefix + d` 和关闭 SonicTerm 标签页也只会断开客户端，窗格会继续运行。之后执行 `rr main` 即可重新连接。

需要主动删除会话时使用 `rd <名称>`。持久性仍然只存在于内存中：执行 `rd` 或 `kill-server`、守护进程丢失或系统重启都会销毁会话；没有类似 resurrect 的磁盘恢复。

### 快捷键

[完整 RMUX 按键表](RMUX-Keymap-zh-CN.md)列出了 prefix、当前 Vi 复制模式、保留的 Emacs 复制模式以及 root 鼠标表中的全部 278 个生效绑定。

| 操作 | 快捷键 |
|---|---|
| 重载配置 | `prefix + r` |
| 切换鼠标/原生选择 | `prefix + T` |
| 在当前目录新建窗口 | `prefix + c` |
| 在当前目录向右分割 | `prefix + \|` |
| 在当前目录向下分割 | `prefix + -` |
| 移动焦点 | `prefix + h/j/k/l` |
| 连续调整大小 | `prefix + H/J/K/L` |
| 返回上一个窗口 | `prefix + Tab` |
| 进入复制模式 | `prefix + v` |
| 开始选择/整行/矩形 | 复制模式中的 `v` / `V` / `C-v` |
| 复制并退出 | 复制模式中的 `y` 或 `C-c` |
| 缩放窗格 | `prefix + z`（RMUX 默认） |
| 分离客户端 | `prefix + d`（RMUX 默认） |

`|`、`-` 和 `c` 都使用 `#{pane_current_path}`，因此新窗格和新窗口会继承当前工作目录。

## SonicTerm 鼠标集成

SonicTerm 的 Copilot 指南要求保留 RMUX 的条件式 root mouse bindings。受管配置会明确固定它们，不依赖 RMUX 默认值：

```tmux
set -g mouse on
bind -n MouseDown1Pane { select-pane -t=; send -M }
bind -n MouseDrag1Pane { if -F '#{||:#{pane_in_mode},#{mouse_any_flag}}' { send -M } { copy-mode -M } }
set -s set-clipboard on
```

`MouseDown1Pane` 会选择 pane 并转发按下事件。`MouseDrag1Pane` 会在 RMUX 已处于 pane mode 或内层应用请求鼠标输入时转发事件；否则 RMUX 会进入 copy mode。这样 Copilot 可以自己处理会话选择与边缘滚动。不要把所有拖动强制送入 RMUX copy mode；Shift-drag 仍可作为 SonicTerm 本地选择的后备方式。

## 剪贴板信任边界

当前配置同时使用 `copy-command 'pbcopy'` 和 `set-clipboard on`：

- 复制模式通过 `pbcopy` 把选中的 UTF-8 文本写入 macOS 剪贴板；
- OSC 52 允许窗格内受信任的程序（包括嵌套 SSH 应用）更新外层终端的剪贴板。

`set-clipboard on` 是明确的信任选择：窗格输出可以替换主机剪贴板。如果窗格中可能运行不受信任的程序，应改用更安全的 `external` 模式。

## Claude Code teammate mode

普通 Claude Code 会话继续使用 `claude` 或仓库提供的 `cc`。需要让 Claude Code 通过窗格启动 agent team 时，再显式使用 RMUX：

```sh
rmux claude --permission-mode bypassPermissions \
  --model 'claude-sonnet-5[1m]' --effort max
```

`rmux claude` 会启用 Claude Code 的 tmux teammate mode，并在 Claude 进程的 `PATH` 前加入私有、进程级的 `tmux` shim，使 teammate 命令指向 RMUX。它不会替换系统全局的 `tmux`。本仓库不会运行 `rmux setup tmux-shim`。

RMUX 窗格内同时提供原生变量和 tmux 兼容变量：`RMUX`、`RMUX_PANE`、`TMUX`、`TMUX_PANE`。`cc` 和 `gg` 在检测到 `RMUX` 时执行 `rmux rename-window`；它们不再调用旧 tmux 或 WezTerm CLI。

Copilot CLI 尚不能识别所有 RMUX/SonicTerm 终端身份。因此仓库中的 `copilot` wrapper 和 `gg` 只为 Copilot 子进程设置 `TERM_PROGRAM=WezTerm`、`COLORTERM=truecolor` 和 `FORCE_COLOR=3`，使其选择已支持的 WezTerm/真彩色路径。外层 RMUX 窗格及其他程序仍然看到正确的 `TERM_PROGRAM=rmux`。

## 自动化能力

除 tmux 风格命令外，RMUX 还提供：

- `pane-snapshot`、`capture-pane`、`stream-pane`、`collect-pane-output`；
- `wait-pane`、`expect-pane`、`locator`；
- `find-panes`、`find-sessions`、`broadcast-keys`、`with-session`；
- 可选的加密 `web-share`，用于共享指定窗格或会话。

测试和自动化应使用命名 socket，避免修改交互式默认 server。

## 迁移边界

原 tmux 源文件保存在 `archive/tmux/`，但不再生效。TPM、tmux-sensible、tmux-yank、resurrect 和 continuum 没有迁移，因为 RMUX 的兼容契约不保证这些插件的行为。现有 `~/.tmux/plugins/` 和 resurrect 快照保留用于回滚。

原 WezTerm Lua 配置保存在 `archive/wezterm/`。本仓库不再安装 WezTerm，也不再链接 `~/.wezterm.lua`；RMUX 使用当前受管的 SonicTerm 作为外层终端。

参阅[已归档的 tmux 配置](Archive-Tmux-zh-CN.md)和[已归档的 WezTerm 配置](Archive-WezTerm-zh-CN.md)。

## 验证

```sh
rmux -V
rmux diagnose --human
rmux capabilities --human
rmux doctor tmux-dropin
ls -l ~/.rmux.conf
```

仓库配置检查使用独立 socket，并保证退出时清理：

```sh
socket="rmux-check-$$"
trap 'rmux -L "$socket" kill-server >/dev/null 2>&1 || true' EXIT
rmux -L "$socket" -f /dev/null new-session -d -s validate
rmux -L "$socket" source-file -n -v config/rmux/rmux.conf
rmux -L "$socket" source-file config/rmux/rmux.conf
```

RMUX 0.10.0 的 parse-only 检查会把事件发生时才可用的 `{mouse}` target 报告为 deferred，并以状态 1 退出。`scripts/check.sh rmux` 只接受这一条明确的已知诊断，然后实际加载配置并检查生效 bindings；其它 parse 诊断都会使检查失败。

在已连接会话中检查 `C-q`、分割、目录继承、复制模式、鼠标切换、真彩色、undercurl、标题和 Gruvbox 状态栏。

## 故障排查

- 如果意外执行 TPM 或插件脚本，说明没有加载原生 RMUX 配置。检查 `~/.rmux.conf`，诊断期间设置 `RMUX_DISABLE_TMUX_FALLBACK=1`。
- `rmux -L name kill-server` 只应针对确认过的命名 socket；`kill-server` 会结束该 socket 上的全部会话。
- 如果升级版本的 wire protocol 不兼容，应先停止旧守护进程，再使用新二进制。
- 本地 IPC 模型信任同一用户下的其他进程。扩大 socket 访问权限前，应先审查 `server-access` 行为。
- Web Share 会产生可选的网络暴露。应使用 PIN、有限 TTL、权限最低的 viewer role，以及可信的前端和 tunnel。

## 权威资料

- [SonicTerm 使用说明](https://github.com/D0n9X1n/SonicTerm/blob/main/wiki/Usage.md)
- [RMUX v0.10.0 README](https://github.com/Helvesec/rmux/blob/v0.10.0/README.md)
- [Human-friendly 配置说明](https://github.com/Helvesec/rmux/blob/v0.10.0/docs/human-friendly-config.md)
- [起始配置](https://github.com/Helvesec/rmux/blob/v0.10.0/docs/examples/human-friendly.conf)
- [Claude Code 集成](https://github.com/Helvesec/rmux/blob/v0.10.0/docs/integrations/claude-code.md)
- [tmux 兼容性决策](https://github.com/Helvesec/rmux/blob/v0.10.0/docs/tmux-compat-decisions.md)
- [安全策略](https://github.com/Helvesec/rmux/blob/v0.10.0/SECURITY.md)
