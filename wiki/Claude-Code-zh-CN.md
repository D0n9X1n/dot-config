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
Claude 端名称： claude-opus-5-5[1m]
Picker 别名：   opus[1m]
Opus 保存偏好： xhigh
启动器 effort： xhigh
Relay 路由：    opusModel
上游模型：      claude-opus-5.5
```

Claude Code 保留原生 Opus 5.5 身份。名称包含 `opus`，所以 copilot-relay 会把它发送到 `opusModel`。客户端拼写使用连字符，Copilot 上游 ID 使用小数点，两者不要混用。

其他路由：

| Claude 端名称 | Relay lane | 上游 |
|---|---|---|
| `claude-sonnet-5[1m]` | `gptModel` | `gpt-6-astra` |
| `claude-haiku-4-5-20251001`（Haiku / small-fast） | `gptModel` | `gpt-6-astra` |

客户端名称和上游模型是两层。客户端保留原生 Anthropic ID；上游模型由 relay 决定。不要把 GPT ID 或 `_NAME` / `_DESCRIPTION` 显示覆盖写进 Claude 端设置。

`[1m]` 后缀让 Claude Code 使用一百万 token 的 context 计数；relay 向上游发送不带该后缀的规范 ID `claude-opus-5.5`。Haiku 保留已安装 CLI 的 small-fast ID，不加 `[1m]`。Context 计数不保证保留完整的 1M-token 对话历史；自动压缩还取决于模型和输出预算。Claude 保存的 Opus 偏好、启动器和状态栏 effort 回退值都使用 `xhigh`，与 `config/copilot-relay/config.yaml` 中的 relay 回退值一致。

Claude Code 2.1.281 能识别原生 Opus 5.5 身份。修改模型和 effort 默认值时应同时更新 `config/claude/settings.json`、`config/zsh/claude.zsh` 和 `config/zsh/cc.zsh`；wrapper 的 `--model` 和 `--effort` flags 优先于保存的设置。Relay 的 `thinkEffort` 也应保持一致，作为未指定 effort 的请求回退值。独立的 `gptModel` 仍为 `gpt-6-astra`，空白的 `webSearchBackend` 仍使用 Astra。

切换模型前，运行 `copilot` 并输入 `/model`，检查账号可用性和 effort 选项。这是 Copilot 的选择器，不是 Claude Code 的选择器，也不是 relay 本地的 `/v1/models`。`scripts/check.sh all` 通过后，运行两次 `./install.sh` 应用配置，再启动新的 shell 和 Claude Code 会话。安装器会保留健康的 relay 进程；恢复不健康的 relay 时可能中断请求。

只修改 `opusModel` 不会让启动时选用 Opus。现在 `ANTHROPIC_MODEL`、保存的 `opus[1m]` 选择、`ANTHROPIC_DEFAULT_OPUS_MODEL` 和两个启动器都指向原生 Opus 5.5。Sonnet 与 Haiku 保留独立的 Astra 路由，不要把这些身份重映射到 Opus。Relay 路由和 effort 修改会热重载，无需重启。

[上游 Opus 5.5 验证](https://github.com/D0n9X1n/copilot-relay/issues/81)确认自动工具调用可用，但强制指定 `tool_choice` 为 `tool` 或 `any` 会返回 HTTP 400。Relay 保留该错误，不会静默改成自动选择。

## 主要设置

`config/claude/settings.json` 设置：

| Key | 值或作用 |
|---|---|
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:4142` |
| `ANTHROPIC_AUTH_TOKEN` | 本机占位符 `dummy` |
| `ANTHROPIC_MODEL` | `claude-opus-5-5[1m]` |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `claude-opus-5-5[1m]`；解析原生 Opus 别名 |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `claude-sonnet-5[1m]` |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `claude-haiku-4-5-20251001` |
| `ANTHROPIC_SMALL_FAST_MODEL` | `claude-haiku-4-5-20251001` |
| `model` | `opus[1m]`；选择器的原生别名 |
| `modelSettings.claude-opus-5-5.effortLevel` | `xhigh`；Opus 5.5 保存的 effort 偏好 |
| `modelSettings.claude-sonnet-5.effortLevel` | `xhigh`；保留本机选择的 Sonnet 偏好 |
| `MODEL_REASONING_EFFORT` | `xhigh`；状态栏回退值与启动器的 `--effort xhigh` 保持一致 |
| `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | `16` |
| `statusLine.refreshInterval` | `100` |
| `theme` | `custom:apollo`；生成的主题资源仍保留在本机 |
| `CLAUDE_CODE_TMUX_TRUECOLOR` | `"1"`；跳过 Claude 的 tmux 256 色限制 |
| `autoCompactEnabled` | `true` |
| `autoCompactWindow` | `770000`；保留的配置窗口，不是实测触发阈值 |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `"100"`；保留的百分比覆盖值 |
| `feedbackDrafts` | `off` |

`refreshInterval` 必须放在 `statusLine` 里面。保存的 Opus 与 Sonnet 偏好都使用 `xhigh`。`MODEL_REASONING_EFFORT` 是状态栏回退值，不控制 API effort。启动器传入 `--effort xhigh`；`claude` 命令上显式指定的 effort 会覆盖它。不管理顶层 `effortLevel`。[Copilot CLI](Copilot-CLI-zh-CN.md) 保留独立的 Astra/`high` 默认值。

独立的 Claude Code 2.1.281 检查验证了仅使用设置、picker 别名和 wrapper 启动时，请求均发送 `model: claude-opus-5-5`、`output_config.effort: xhigh` 和 1M context beta。显式指定 Sonnet/`low` 仍优先。检查使用回环 mock、临时 home 和 macOS sandbox，阻止外部网络及真实 home/keychain 访问；没有付费模型调用，也不是上游容量测试。

### 自动压缩

配置窗口不等于压缩触发阈值。`autoCompactWindow: 770000` 和 `100` 百分比覆盖值保持不变。之前的 750,000-token 计算使用 Claude Code 2.1.261 的 Sonnet 输出预留量，不是已验证的 Opus 5.5 阈值。当前离线 Opus 请求允许 128,000 输出 tokens，但单凭请求上限不能确定压缩预留量或触发点。

CLI 版本、模型、输出预算和环境覆盖都可能改变压缩时机；某一轮可能先越过触发点再开始压缩。不要把这些设置当作对话大小硬上限或历史保留保证。编辑源设置后请启动新的 Claude Code 会话。

`~/.claude/settings.json` 和 `~/.claude.json` 是不同文件：

- `settings.json` 是链接的配置，包括 `custom:apollo` 主题偏好。
- `~/.claude.json` 是本机状态。它保存 onboarding、API key 允许项、安装器同步选择的 Apollo 主题、项目数据和导入的 MCP servers。

`install.sh` 会从已验证的规范 Apollo release 生成 `~/.claude/themes/apollo.json`，并在选择 `custom:apollo` 时保留所有无关字段。生成主题是本机状态，不是 Git 源文件。

不要把本机状态文件放进 Git。

## 全局指令

`config/claude/CLAUDE.md` 安装为 `~/.claude/CLAUDE.md`，并设置用户级回复风格。对话文字默认直接、简短。明确要求更多细节时仍按要求回答；代码、命令、检查结果、证据、必要说明、安全信息和技术准确性必须保持完整。

全局文件只保留可复用行为，加一条条件指针：这些设置从 `~/Public/dot-configs` 同步；要修改它们，先读该目录的 `.claude/CLAUDE.md`。仓库专属规则——Wiki 是完整信息源、manifest、检查、双语页面——留在本仓库自己的 `.claude/CLAUDE.md`，这样无关项目不会加载它们。

PR 合并后，全局规则要求先完成本机清理，再宣布任务完成：确认合并，移除该 PR 干净且闲置的 worktree 和本地分支，清理失效引用，移除任务创建的临时文件，并停止不再需要的任务专属进程。保留未提交或未合并的工作、stash、活跃会话和锁、无关文件及共享进程。检查最终状态，并说明保留项。这是 agent 指令，不是无人值守的合并 hook。

## 启动器

`config/zsh/claude.zsh` 包装 `claude` 并添加：

```text
--permission-mode bypassPermissions
--model claude-opus-5-5[1m]
--effort xhigh
```

命令行上显式给出 `--model`、`--model=`、`--effort` 或 `--effort=` 时，对应的默认值不再注入；另一个默认值仍然生效。

安装后打开新 shell，或在空闲 shell 提示符中重新加载两个启动器，再启动新的 Claude 会话：

```zsh
source ~/.oh-my-zsh/custom/claude.zsh
source ~/.oh-my-zsh/custom/cc.zsh
```

二进制会拒绝 settings 中的 `permissions.defaultMode: bypassPermissions`。命令行 flag 可以工作。Claude Code 可能在运行时重写 settings，所以 wrapper 也固定模型和 effort。

`settings.json` 是符号链接，因此 CLI 持久化的偏好可能表现为源文件改动。提交前检查 `git diff -- config/claude/settings.json`，只按上面的受支持设置核对变动的键，再运行 `scripts/check.sh all`。不要整份恢复文件，以免丢失其他有意保留的修改。

`cc [标题]` 会设置 SonicTerm 标题，并用相同默认值启动 Claude Code。它先检查 RMUX 并直接重命名其窗口。在原生 tmux 中，通过 `tmux-store` 重命名当前 socket 的当前窗口，不添加 `PATH` shim，也不替换真正的全局 `tmux` 可执行文件。请看 [Tmux](Tmux-zh-CN.md)。

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
- `swift-lsp@claude-plugins-official`
- `claude-code-wakatime@wakatime`

WakaTime marketplace 指向官方 `wakatime/claude-code-wakatime` Git 仓库。

## 常见问题

### RMUX 内的颜色不同

Claude Code 2.1.278 在存在 `TMUX` 时会把输出限制为 256 色，即使已设置 `COLORTERM=truecolor` 和 `FORCE_COLOR=3`。RMUX 为兼容性导出 `TMUX`，但支持真彩色。受管的 `env.CLAUDE_CODE_TMUX_TRUECOLOR: "1"` 跳过这个客户端限制，不改动 Apollo 配色。原生 SonicTerm 没有 `TMUX` 时，也没有这个限制需要绕过。

应用设置后请启动新的 Claude Code 进程；已有进程已完成颜色初始化。可以用 `claude --continue` 恢复对话。不要重启 RMUX 服务器：它已经支持真彩色，重启会停止窗格内的应用。重载或重新连接 RMUX 不会重新初始化运行中 Claude 进程的颜色。保留 `TERM=tmux-256color`、`TERM_PROGRAM=rmux` 和 `rmux claude` 私有 teammate shim，不需要修改它们。

### Claude 每次都显示 onboarding

本机 `~/.claude.json` 缺少 `hasCompletedOnboarding`。在这台 Mac 上完成一次 onboarding。

### `dummy` key 被拒绝

第一次提示选择了拒绝。在本机 `~/.claude.json` 中，把 `dummy` 从 `customApiKeyResponses.rejected` 移到 `approved`，或重新完成允许流程。

### 小任务出现 `model_not_supported`

保持 Haiku 和 small-fast aliases 都是 `claude-haiku-4-5-20251001`，即已安装 CLI 自身的 small-fast ID。那里不要加 `[1m]` 后缀。同时检查 relay base URL。

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
