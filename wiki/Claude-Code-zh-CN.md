# Claude Code

[English](Claude-Code.md) | 简体中文

在本设置中，Claude Code 使用本机 copilot-relay 服务。

```mermaid
flowchart LR
    C[Claude Code] --> R[127.0.0.1:4142]
    R --> G[GitHub Copilot]
```

源文件在 `config/claude/`。它们安装到 `~/.claude/`。

## 一次设置

```sh
./install.sh
npx copilot-relay auth
./install.sh
```

Claude Code 第一次启动时会问是否允许自定义 `dummy` API key。请选择允许。这个值只是 Claude Code 需要的占位符。真实 GitHub 登录由 copilot-relay 保存。

## 模型路由

受管默认值：

```text
Claude 端名称： claude-sonnet-5[1m]
Picker 名称：    Sonnet 5
客户端 effort：  max
Relay 路由：     gptModel
上游模型：       gpt-5.6-sol
```

名称中没有 `opus`，所以 copilot-relay 会把它发送到 `gptModel`。

其他路由：

| Claude 端名称 | Relay lane | 上游 |
|---|---|---|
| `claude-opus-5[1m]` | `opusModel` | `claude-opus-5` |
| Haiku / small-fast aliases | `gptModel` | `gpt-5.6-sol` |

`[1m]` 后缀让 Claude Code 使用一百万 token 的 context 计数。Relay 端 thinking 在 `config/copilot-relay/config.yaml` 中设为 `max`。

Sonnet 和 Opus 是两个模型家族。任务只要求修改一个家族时，不要同时修改两个。

## 主要设置

`config/claude/settings.json` 设置：

| Key | 值或作用 |
|---|---|
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:4142` |
| `ANTHROPIC_AUTH_TOKEN` | 本机占位符 `dummy` |
| `ANTHROPIC_MODEL` | `claude-sonnet-5[1m]` |
| `effortLevel` | `max` |
| `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | `16` |
| `statusLine.refreshInterval` | `100` |
| `theme` | `dark-ansi` |
| `autoCompactWindow` | `800000` |

`refreshInterval` 必须放在 `statusLine` 里面。

`~/.claude/settings.json` 和 `~/.claude.json` 是不同文件：

- `settings.json` 是链接的配置。
- `~/.claude.json` 是本机状态。它保存 onboarding、API key 允许项、项目数据和导入的 MCP servers。

不要把本机状态文件放进 Git。

## 启动器

`config/zsh/claude.zsh` 包装 `claude` 并添加：

```text
--permission-mode bypassPermissions
--model claude-sonnet-5[1m]
--effort max
```

二进制会拒绝 settings 中的 `permissions.defaultMode: bypassPermissions`。命令行 flag 可以工作。Claude Code 可能在运行时重写 settings，所以 wrapper 也固定模型和 effort。

`cc [标题]` 会设置 SonicTerm 标题，在 RMUX 中重命名窗口，并用相同默认值启动 Claude Code。

只有当 Claude Code 需要创建 agent-team 窗格时才使用 `rmux claude`。RMUX 会给这个进程一个私有 tmux 兼容 shim。不会安装全局 tmux shim。

## Agent 限制

需要 Claude Code v2.1.217 或更高版本。

原生 admission 值是 16。它不是全局硬上限：

- 用户启动的 `/subtask` 会占一个 slot，但不被同一个边界拦截；
- 恢复的 agent 可以超过设置数量；
- ultracode 不受此限制；
- workflow agents 和 team workers 使用其他限制。

不要恢复旧生命周期计数 hook。

## 状态栏

Claude 与 Copilot 状态栏共享五行布局、Gruvbox 颜色和每目录五秒 Git cache：

1. 时间、运行时间、费用、WakaTime
2. 模型、effort、context
3. MCP、skills、agents、style
4. 当前路径
5. repo、branch、diff、stash、worktree

Claude 自定义状态栏没有 live-subagent 数量或树。Claude Code 已有原生 subagent UI。Copilot 保留自定义 rows。

## Plugins

受管设置启用：

- `frontend-design@claude-plugins-official`
- `rust-analyzer-lsp@claude-plugins-official`
- `claude-code-wakatime@wakatime`

WakaTime marketplace 指向官方 `wakatime/claude-code-wakatime` Git 仓库。

## 常见问题

### Claude 每次都显示 onboarding

本机 `~/.claude.json` 缺少 `hasCompletedOnboarding`。在这台 Mac 上完成一次 onboarding。

### `dummy` key 被拒绝

第一次提示选择了拒绝。在本机 `~/.claude.json` 中，把 `dummy` 从 `customApiKeyResponses.rejected` 移到 `approved`，或重新完成允许流程。

### 小任务出现 `model_not_supported`

保持 Haiku 和 small-fast aliases 都是 `gpt-5.6-sol[1m]`。同时检查 relay base URL。

### Relay 重写 settings

`config/copilot-relay/config.yaml` 中的 `claudeSetup` 必须是 `false`。重新运行 `./install.sh`。

### Relay token 过期

```sh
npx copilot-relay auth
./install.sh
```

Deep relay 检查退出码为 2 时，一般需要重新登录，不是重启。

## 检查

```sh
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay" | grep state
curl -fsS http://127.0.0.1:4142/healthz
scripts/check.sh instructions
scripts/check.sh all
```

launchd 和健康检查请看[服务与自动化](Services-and-Automation-zh-CN.md)。
