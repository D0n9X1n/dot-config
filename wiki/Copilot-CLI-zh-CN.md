# Copilot CLI

[English](Copilot-CLI.md) | 简体中文

Copilot CLI 文件在 `config/copilot/`。它们安装到 `~/.copilot/`。

## 默认值

`config/copilot/settings.json` 使用：

```text
model:       gpt-6-astra
context:     long_context
effort:      max
theme:       default（终端 Base-16）
keep alive:  busy
streaming:   on
```

运行 `copilot`，然后在其交互会话中输入 `/model`，即可查看账号可用模型及其 effort 选项。Astra 公布的档位为 `low`、`medium`、`high`、`xhigh`、`max`；可用性取决于账号和组织策略。CLI 使用规范 ID `gpt-6-astra`，不带 Claude Code 的 `[1m]` 后缀。

修改受管默认值时，应同时编辑 `config/copilot/settings.json` 和 `config/zsh/gg.zsh` 中的 `--model`，然后运行 `scripts/check.sh all`。非受管安装可通过 `/config model` 修改 Copilot 用户默认值；本仓库应修改受版本控制的源文件，避免下次安装覆盖选择。

自定义 footer 隐藏内置字段，并运行 `~/.copilot/statusline.sh`。

Copilot 可能在运行时添加或删除 `staff` 字段。不要把它留在受管文件中。在 `statusLine` 中，只有简单的 `padding` 字段受支持。每个方向的间距应由 shell 脚本处理。

## 全局指令

Copilot 安装两个指令文件：

- `config/copilot/copilot-instructions.md` → `~/.copilot/copilot-instructions.md`
- `config/copilot/AGENTS.md` → `~/.copilot/AGENTS.md`

原生文件保存 Copilot 的用户级行为。它让对话文字默认直接、简短。明确要求更多细节时仍按要求回答；代码、命令、检查结果、证据、必要说明、安全信息和技术准确性必须保持完整。

`AGENTS.md` 只保留 Wiki 指针，用于可复用的 GitHub Wiki 和 release 工作。

`config/zsh/custom.zsh` 把 `~/.copilot` 加入 `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`。它会保留已有路径，也不会重复添加。

## 终端身份

SonicTerm 和 RMUX 使用真实终端名称。Copilot 还不能识别所有 RMUX 或 SonicTerm 能力路径。

`copilot` wrapper 和 `gg` 只为 Copilot 子进程设置：

```text
TERM_PROGRAM=WezTerm
COLORTERM=truecolor
FORCE_COLOR=3
```

这样会启用 Copilot 支持的终端路径。受管 `default` 主题使用终端 Base-16 颜色，因此会继承 SonicTerm 的 Apollo ANSI palette。它不会安装或运行 WezTerm。其他程序仍看到 `SonicTerm` 或 `rmux`。

## 启动命令

```sh
copilot          # 普通 Copilot wrapper
gg my-project    # 带标题、不限制工具和路径的 Copilot session
```

`gg` 使用 GPT-6 Astra、长 context 和 max effort。它也会传入 `--allow-all-tools --allow-all-paths`，所以工具和路径不会请求允许。不想使用这种访问模式时，请使用普通 `copilot`。

`gg` 会向 SonicTerm 发送 OSC 标题。它在 RMUX 中也会运行 `rmux rename-window`。它不会调用 tmux 或 WezTerm CLI。

## 状态栏

Copilot 状态栏与 Claude 共享五行布局和本机生成的 Apollo 颜色：

1. 时间、运行时间、请求、WakaTime
2. 模型、effort、context
3. MCP、skills、agents、tasks、style
4. 当前路径
5. repo、branch、diff、stash、worktree

它用一次 `jq` 读取 session JSON。两个 provider 状态脚本读取同一个本机生成 Apollo 颜色 include；文件缺失时会回退为可读的无色输出。Git 数据按工作目录缓存五秒。GitHub auth 数据缓存五分钟。

有用的环境变量：

| 变量 | 作用 |
|---|---|
| `COPILOT_STATUSLINE_NO_ICONS=1` | 隐藏图标 |
| `COPILOT_STATUSLINE_NO_COLOR=1` | 隐藏颜色 |
| `COPILOT_STATUSLINE_PAD_TOP=N` | 添加顶部空白 |
| `COPILOT_STATUSLINE_PAD_LEFT=N` | 添加左侧空白 |
| `COPILOT_STATUSLINE_PAD_RIGHT=N` | 添加右侧空白 |
| `COPILOT_STATUSLINE_SEGMENTS="..."` | 设置 segment 顺序 |
| `COPILOT_STATUSLINE_GIT_TTL=N` | 设置 Git cache 秒数 |
| `COPILOT_STATUSLINE_MAX_SUBAGENTS=N` | 限制 live rows |

运行字符测试：

```sh
~/.copilot/statusline.sh --test
```

## Live subagents

Copilot 保留自定义 live-subagent UI。Hooks 调用 `~/.copilot/subagent-state.sh`：

- session 开始或结束时重置 rows；
- subagent 开始时添加一行；
- subagent 停止时删除匹配行。

状态栏先读 hook rows。Rows 缺失时，它可以读取 session event log。

Claude 的同类状态栏不复制这部分，因为 Claude Code 已有原生 agent UI。

## 清理

`scripts/copilot/cleanup-legacy.sh` 安装为 `~/.copilot/cleanup-legacy.sh`。

它保留当前 Copilot package payload，删除旧 payload、旧备份文件，并只保留最新 process log。`install.sh` 在链接后运行它。成功的 `copilot update` 也会运行它。

## WakaTime

`install.sh` 安装或更新官方 plugin：

```text
wakatime/copilot-cli-wakatime
```

它使用 `~/.wakatime.cfg` 中的 API key。Plugin 会管理自己的 WakaTime CLI。

安装器发现旧 WakaTime MCP、旧 Homebrew `wakatime-cli` 或旧第三方 npm plugin 时，会删除它们。

## Session sync

受管设置会同步选定仓库的用户 session，并让其他 session 留在本机。修改列表前请检查 `sessionSync`。

## 检查

```sh
copilot --version
copilot plugin list
~/.copilot/statusline.sh --test
scripts/check.sh instructions
scripts/check.sh all
```

Wrapper 和标题细节请看 [SonicTerm 与 Shell](SonicTerm-and-Shell-zh-CN.md)。
