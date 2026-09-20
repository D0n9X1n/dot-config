# 服务与自动化

[English](Services-and-Automation.md) | 简体中文

`install.sh` 会设置工具、本机服务、共享 MCP 数据、WakaTime 和清理任务。

Copilot 使用内置 GitHub 集成；Claude 使用已认证的 `gh`。不需要额外的 GitHub MCP 条目或 PAT。共享 MCP 数据和本机秘密边界请看[仓库操作](Repository-Operations-zh-CN.md)。

## 新 Mac 设置

在 macOS 上，安装器可以添加：

- Homebrew
- RMUX
- Homebrew cask 中的 Claude Code
- npm 中的 Copilot CLI 和 copilot-relay
- oh-my-zsh
- `eza`、`jq`、`neovim` 和 autojump 等 shell 工具
- Recursive 和 Nerd 字体
- MOSconfig release 中的 RecMono Baker 与 St.Helens 字体
- SonicTerm、RMUX 和 eza 的固定 Apollo theme releases
- Claude、两个状态栏和 shell prompt 的本机 Apollo adapters

Claude Code 需要 v2.1.217 或更高版本。`theme.yml` 需要 eza v0.23.5 或更高版本。

使用这些开关跳过慢的设置工作：

```sh
SKIP_BREW=1 ./install.sh
SKIP_NPM_GLOBALS=1 ./install.sh
SKIP_OH_MY_ZSH=1 ./install.sh
```

安装日志在 `~/Library/Logs/dot-configs-install.log`。

## Apollo release bundle

`scripts/apollo-releases.tsv` 固定精确的上游 tag 和 SHA-256。安装器会复用已验证本机 blobs，在一个由 release lock 和 adapter code 派生的 bundle hash 下构建全部文件，并且只在完整 set 通过检查后切换 `current` symlink。第二次安装会直接使用已有 bundle，不下载或重写。

第一次安装需要网络。只要固定 blobs 仍位于 `~/.local/share/dot-configs/apollo/`，以后就能离线安装。下载失败或 checksum 不匹配时，旧 bundle 保持生效。请看 [Apollo 主题](Apollo-Theme-zh-CN.md)。

## copilot-relay

Relay 监听：

```text
http://127.0.0.1:4142
```

受管配置是 `config/copilot-relay/config.yaml`。它安装为 `~/.copilot-relay/config.yaml`。

重要值：

```yaml
claudeSetup: false
thinkEffort: medium
upstreamTimeoutSeconds: 600
gptModel: gpt-6-astra
opusModel: claude-opus-5
```

`claudeSetup: false` 会阻止 relay 重写链接的 Claude settings。Relay 对未指定 effort 的请求仍回退到 `medium`。Claude 保存的 Sonnet 偏好和启动器使用 `high`，Copilot CLI 设置及 `gg` 启动器也使用 `high`；客户端显式指定的 effort 优先于 relay 回退值。`upstreamTimeoutSeconds: 600` 允许单个 Claude 请求的上游 Copilot 调用最多等待十分钟。

登录一次：

```sh
npx copilot-relay auth
./install.sh
```

认证和日志保留在本机 `~/.copilot-relay/` 中。

## launchd 文件

`config/launchd/` 下的文件是模板。它们不是符号链接。

安装器会替换：

```text
__HOME__      为用户目录路径
__REPO_ROOT__ 为仓库路径
```

它把结果写到 `~/Library/LaunchAgents/`，然后为 `gui/<uid>` 运行 `bootout` 和 `bootstrap`。

不要编辑渲染文件。下一次安装会替换它们。

### 易读启动名称

启动器使用易读名称改善 macOS 后台项目归属显示；不会重命名运行中的进程，也不改变任务标签、计划、参数或恢复行为：

| 任务标签 | 启动器名称 |
|---|---|
| `com.d0n9x1n.copilot-relay` | Copilot Relay |
| `com.d0n9x1n.copilot-relay-healthcheck` | Copilot Relay Health Check |
| `com.d0n9x1n.npm-cache-clean` | Weekly npm Cache Cleanup |

三个名称均已在后台任务管理（BTM）中验证。BTM 可以根据文件变更刷新名称，而 launchd 仍保留运行中任务的旧定义；这是两个独立状态。Relay 已加载的定义会在后续重新注册时更新，无需为了改名立即重启。用 `sfltool dumpbtm` 验证归属显示，不要仅凭文件名判断，也不要重置 BTM 来刷新名称。启动器链接依赖仓库保持在安装路径；移动仓库后需重新运行安装器。

## Relay 服务

`com.d0n9x1n.copilot-relay` 在登录时启动 relay。Crash 后会再次启动，间隔至少十秒。

检查它：

```sh
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay"
launchctl kickstart -k "gui/$(id -u)/com.d0n9x1n.copilot-relay"
```

日志：

```text
~/Library/Logs/copilot-relay.out.log
~/Library/Logs/copilot-relay.err.log
~/.copilot-relay/logs/copilot-relay.log
```

## Relay 健康检查

`com.d0n9x1n.copilot-relay-healthcheck` 在加载时运行，以后每 60 秒运行一次。

可执行入口是 `~/.local/libexec/Copilot Relay Health Check`，它链接到 `scripts/launchd/` 中受版本控制的启动器。启动器用 `/bin/bash` 执行原有健康检查脚本并替换自身进程；任务标签、计划、参数和恢复策略保持不变。易读文件名用于 macOS 后台项目归属显示，不改变运行中的进程名称，后者仍是 Bash。安装后用 `sfltool dumpbtm` 验证当前 macOS 版本显示的名称；不要通过重置后台项目数据库来刷新名称。

它有两个检查：

1. 每次运行都执行 `GET /healthz`。不是 200 时重启 relay。
2. 每 900 秒执行 `copilot-relay status --deep --json`，超时为 45 秒。这会通过 Copilot 发送真实请求。

`/healthz` 返回 200 只表示有 socket 在监听。Deep check 还会检查认证和上游访问。

Deep 结果：

| 退出码 | 含义 | 操作 |
|---|---|---|
| `0` | Relay 正常 | 不做事 |
| `1` | 探针报告 Relay 没有运行 | 重新检查本地健康状态；HTTP 200 时保持运行 |
| `2` | 健康探针或上游探针失败 | 重新检查本地健康状态；HTTP 200 时保持运行 |
| `124` | 诊断超时 | 只停止诊断进程；重新检查本地健康状态 |
| 其他非零值 | 诊断失败 | 重新检查本地健康状态；HTTP 200 时保持运行 |

即使连续失败，deep check 也不会重启本地健康的 relay。只有新的本地检查也失败时才执行恢复。探针运行前会写入时间戳，因此失败不会导致每分钟发送付费请求。恢复后只检查本地健康状态，下次 deep probe 等待正常间隔。

失败日志只记录退出码、新的本地状态，以及同一次 JSON 探针中白名单允许的布尔值、有界耗时和 HTTP 状态码。原始详情、凭证、路径、提示词和 stderr 不会复制到 watchdog 日志。JSON 缺失或无效时记录 `diagnostic=unavailable`，不改变恢复决定。不把退出码 `2` 直接当作认证过期；应检查上游可用性，仅在需要时重新认证。

可以用下面的变量调整 deep check：

```text
COPILOT_RELAY_DEEP_INTERVAL
COPILOT_RELAY_DEEP_MAX_TIME
```

把 interval 设为 0 可关闭 deep check。

健康日志和状态：

```text
~/Library/Logs/copilot-relay-healthcheck.log
~/Library/Caches/copilot-relay-healthcheck.deep
```

## npm cache 清理

`com.d0n9x1n.npm-cache-clean` 每周日 03:17 运行。安装时不会运行。

它会：

- 运行 `npm cache clean --force`；
- 按文件夹修改时间删除超过 14 天的 `~/.npm/_npx` 副本；
- 保留 `~/Library/Caches/ms-playwright` 中的 Playwright 浏览器。

现在运行：

```sh
launchctl kickstart -k "gui/$(id -u)/com.d0n9x1n.npm-cache-clean"
```

主日志是 `~/Library/Logs/npm-cache-clean.log`。脚本最多保留 500 行。

## 第三方启动项目名称

`startup-item-names` 是一次性审查工具，不是服务。默认只读预览；只有显式指定用户范围的应用或回滚才会写入覆盖层：

```sh
startup-item-names
startup-item-names --apply
startup-item-names --rollback
```

应用和回滚仅限用户范围；工具拒绝以 root 身份执行这两种操作。经审查的 V2rayU 映射为：

| 任务标签 | 易读名称 |
|---|---|
| `yanue.v2rayu.v2ray-core` | V2rayU V2Ray Proxy Core (Legacy) |
| `yanue.v2rayu.xray-core` | V2rayU Xray Proxy Core |
| `yanue.v2rayu.sing-box` | V2rayU sing-box Proxy Core |
| `yanue.v2rayu.tun-helper`（系统） | V2rayU TUN Network Helper — 暂缓重命名 |

三个用户核心保留 `~/.V2rayU` 工作目录。系统 sing-box TUN 辅助程序缺少 root 配置，因此暂缓重命名，且不得为了调整名称而运行它。

只有合法应用与辅助程序的 TeamID 匹配时，才关联 Adobe、Charles、AutoUpdate、iStat 安装器和 Steam 等已签名应用。系统范围的更改需单独由管理员审查，并使用 macOS 内置工具应用；不要提权运行此用户管理工具。

应用和回滚保留原有的阻止/允许状态。工具不会重新加载服务、重置后台项目数据库或编辑已签名的应用包。备份仅保存在本机 `~/.local/state/dot-configs/startup-names/`，永远不进入仓库。第三方更新可能恢复旧名称，重新应用前必须再次审查；遇到冲突会拒绝操作，而不是静默覆盖。用 `sfltool dumpbtm` 验证实际归属显示；覆盖层不保证显示立即改变。

并非所有详细名称都应修改：iStat daemon 和 TeamViewer 辅助程序已经有清晰的应用分组归属。Teams agent、CleanerOne 的 `TCLoginItemHelper` 以及 Quick Look/Spotlight 扩展使用第三方内部的已签名名称。应解释这些名称的用途，而不是覆盖它们。

## MCP 合并

`config/mcp/mcp-shared.json` 只包含安全共享项目。

安装器把它们合并到本机 Copilot MCP 数据，然后把 server map 导入 `~/.claude.json`。

可选 MCP server 的 key 和 token 保留在本机 `~/.config/github-copilot/mcp.json`。永远不要放进共享文件。

## WakaTime

Copilot 使用官方 `wakatime/copilot-cli-wakatime` plugin。Claude 使用官方 `wakatime/claude-code-wakatime` plugin。

安装器从 `~/.wakatime.cfg` 读取 key。没有 key 且安装为交互模式时，它会要求输入两次，并且不会打印 key。

安装器也会删除旧 WakaTime 路径：

- 旧本机 WakaTime MCP runtime 和 entries；
- Homebrew `wakatime-cli`；
- 旧 `@geeknees/copilot-cli-wakatime` npm package。

## 验证

```sh
curl -fsS http://127.0.0.1:4142/healthz
copilot-relay status --deep; echo "exit=$?"
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay"
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay-healthcheck"
launchctl print "gui/$(id -u)/com.d0n9x1n.npm-cache-clean"
scripts/check.sh all
```

清单和安全链接请看[仓库操作](Repository-Operations-zh-CN.md)。
