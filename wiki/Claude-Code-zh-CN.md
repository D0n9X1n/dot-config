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
Claude 端名称： gpt-6-astra[1m]
Picker 名称：    GPT-6 Astra
客户端 effort：  max
Relay 路由：     gptModel
上游模型：       gpt-6-astra
```

名称中没有 `opus`，所以 copilot-relay 会把它发送到 `gptModel`。

其他路由：

| Claude 端名称 | Relay lane | 上游 |
|---|---|---|
| `claude-opus-5[1m]` | `opusModel` | `claude-opus-5` |
| Haiku / small-fast aliases | `gptModel` | `gpt-6-astra` |

`[1m]` 后缀让 Claude Code 使用一百万 token 的模型 context 计数；relay 向上游发送规范 ID `gpt-6-astra`。自动压缩刻意在 75,000 tokens 时触发，远早于 Astra 的 1M 总窗口内公布的 872,000-token prompt 上限。这并不意味着会保留完整的 1M-token 对话历史。Relay 端 thinking 在 `config/copilot-relay/config.yaml` 中设为 `max`。

使用本设置前，请先使用支持 GPT-6 Astra 的 relay 构建（见 [copilot-relay issue #57](https://github.com/D0n9X1n/copilot-relay/issues/57)）。修改模型时应同时更新 `config/claude/settings.json`、`config/zsh/claude.zsh` 和 `config/zsh/cc.zsh`；wrapper 的 `--model` 优先于设置文件。Relay 的 `gptModel` 不带后缀，空白的 `webSearchBackend` 也使用 Astra。Opus 路由保持独立。

切换模型前，运行 `copilot` 并输入 `/model`，检查账号可用性和 effort 选项。这是 Copilot 的选择器，不是 Claude Code 的选择器，也不是 relay 本地的 `/v1/models`。`scripts/check.sh all` 通过后，运行两次 `./install.sh` 应用配置，再启动新的 shell 和 Claude Code 会话。安装器会重启 relay，可能中断正在进行的请求；请先等待请求结束。

Sonnet-facing 槽位通过 `gptModel` 路由到 GPT-6 Astra；Opus 仍使用独立的 `opusModel` 路由。任务只要求修改一条路由时，不要同时修改两条。

## 主要设置

`config/claude/settings.json` 设置：

| Key | 值或作用 |
|---|---|
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:4142` |
| `ANTHROPIC_AUTH_TOKEN` | 本机占位符 `dummy` |
| `ANTHROPIC_MODEL` | `gpt-6-astra[1m]` |
| `MODEL_REASONING_EFFORT` | `max`；启动器同时传入 `--effort max` |
| `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | `16` |
| `statusLine.refreshInterval` | `100` |
| `theme` | `custom:apollo`；生成的主题资源仍保留在本机 |
| `autoCompactEnabled` | `true` |
| `autoCompactWindow` | `120000`，尚未扣除输出 token 预留量 |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `"75"`；默认输出预算下在 75,000 tokens 时触发压缩 |
| `feedbackDrafts` | `off` |

`refreshInterval` 必须放在 `statusLine` 里面。Max effort 保留在环境变量和启动器 flag 中：Claude Code 2.1.261 不接受在持久化的顶层 `effortLevel` 设置中填写 `max`。

### 75k 自动压缩

Claude Code 2.1.261 要求 `autoCompactWindow` 至少为 100,000，因此不能直接设置为 `75000`。受管配置采用 120,000-token 窗口和 `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "75"`。默认输出预算下，Claude 先预留 20,000 tokens：`(120000 - 20000) × 75% = 75000`。

使用这些受管设置、且未覆盖输出预算的隔离 CLI 运行报告了 `effective_window: 100000`、`threshold: 75000` 和 `enforced: true`，没有发送上游请求。这是触发阈值，不是对话大小的硬上限；某一轮可能先越过阈值，再执行压缩。修改模型、输出预算或 `CLAUDE_CODE_AUTO_COMPACT_WINDOW` 覆盖值可能改变计算结果。编辑源设置后请启动新的 Claude Code 会话。

`~/.claude/settings.json` 和 `~/.claude.json` 是不同文件：

- `settings.json` 是链接的配置，包括 `custom:apollo` 主题偏好。
- `~/.claude.json` 是本机状态。它保存 onboarding、API key 允许项、安装器同步选择的 Apollo 主题、项目数据和导入的 MCP servers。

`install.sh` 会从已验证的规范 Apollo release 生成 `~/.claude/themes/apollo.json`，并在选择 `custom:apollo` 时保留所有无关字段。生成主题是本机状态，不是 Git 源文件。

不要把本机状态文件放进 Git。

## 全局指令

`config/claude/CLAUDE.md` 安装为 `~/.claude/CLAUDE.md`，并设置用户级回复风格。对话文字默认直接、简短。明确要求更多细节时仍按要求回答；代码、命令、检查结果、证据、必要说明、安全信息和技术准确性必须保持完整。

## 启动器

`config/zsh/claude.zsh` 包装 `claude` 并添加：

```text
--permission-mode bypassPermissions
--model gpt-6-astra[1m]
--effort max
```

二进制会拒绝 settings 中的 `permissions.defaultMode: bypassPermissions`。命令行 flag 可以工作。Claude Code 可能在运行时重写 settings，所以 wrapper 也固定模型和 effort。

`settings.json` 是符号链接，因此 CLI 持久化的偏好可能表现为源文件改动。提交前检查 `git diff -- config/claude/settings.json`，只按上面的受支持设置核对变动的键，再运行 `scripts/check.sh all`。不要整份恢复文件，以免丢失其他有意保留的修改。

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

Claude 与 Copilot 状态栏共享五行布局、本机生成的 Apollo 颜色和每目录五秒 Git cache：

1. 时间、运行时间、费用、WakaTime
2. 模型、effort、context
3. MCP、skills、agents、style
4. 当前路径
5. repo、branch、diff、stash、worktree

两个脚本读取同一个本机生成 Apollo 颜色 include。文件缺失或禁用颜色时，它们仍会输出可读的无色内容。Claude 自定义状态栏没有 live-subagent 数量或树，因为 Claude Code 已有原生 subagent UI。Copilot 保留自定义 rows。

## Plugins

受管设置启用：

- `frontend-design@claude-plugins-official`
- `rust-analyzer-lsp@claude-plugins-official`
- `clangd-lsp@claude-plugins-official`
- `claude-code-wakatime@wakatime`

WakaTime marketplace 指向官方 `wakatime/claude-code-wakatime` Git 仓库。

## 常见问题

### Claude 每次都显示 onboarding

本机 `~/.claude.json` 缺少 `hasCompletedOnboarding`。在这台 Mac 上完成一次 onboarding。

### `dummy` key 被拒绝

第一次提示选择了拒绝。在本机 `~/.claude.json` 中，把 `dummy` 从 `customApiKeyResponses.rejected` 移到 `approved`，或重新完成允许流程。

### 小任务出现 `model_not_supported`

保持 Haiku 和 small-fast aliases 都是 `gpt-6-astra[1m]`。同时检查 relay base URL。

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
