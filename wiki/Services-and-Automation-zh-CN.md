# 服务与自动化

[English](Services-and-Automation.md) | 简体中文

`install.sh` 会设置工具、本机服务、共享 MCP 数据、WakaTime 和清理任务。

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
thinkEffort: max
gptModel: gpt-6-astra
opusModel: claude-opus-5
```

`claudeSetup: false` 会阻止 relay 重写链接的 Claude settings。

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

它有两个检查：

1. 每次运行都执行 `GET /healthz`。不是 200 时重启 relay。
2. 每 900 秒执行 `copilot-relay status --deep`。这会通过 Copilot 发送真实请求。

`/healthz` 返回 200 只表示有 socket 在监听。Deep check 还会检查认证和上游访问。

Deep 结果：

| 退出码 | 含义 | 操作 |
|---|---|---|
| `0` | Relay 正常 | 不做事 |
| `1` | Relay 没有运行 | 重启 |
| `2` | Relay 在监听，但不能访问 Copilot | 重新认证 |

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

## MCP 合并

`config/mcp/mcp-shared.json` 只包含安全共享项目。

安装器把它们合并到本机 Copilot MCP 数据，然后把 server map 导入 `~/.claude.json`。

所有 key 和 token 都应放在本机 `~/.config/github-copilot/mcp.json`。永远不要放进共享文件。

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
