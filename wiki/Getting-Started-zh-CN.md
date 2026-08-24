# 开始使用

[English](Getting-Started.md) | 简体中文

本仓库只用于 macOS。`install.sh` 可以设置一台新 Mac。重复运行是安全的。

## 安装

```sh
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
cd ~/Public/dot-configs
./install.sh
```

脚本可以安装 Homebrew、RMUX、Claude Code、Copilot CLI、copilot-relay、shell 工具、字体和 oh-my-zsh。然后，它会链接 `config/manifest.tsv` 中列出的文件。

完整日志在这里：

```text
~/Library/Logs/dot-configs-install.log
```

## 连接 relay

Claude Code 使用本机 copilot-relay 服务。

执行一次浏览器登录：

```sh
npx copilot-relay auth
./install.sh
```

第二次安装会启动已认证的 launchd 服务。

检查服务：

```sh
curl -fsS http://127.0.0.1:4142/healthz >/dev/null && echo "relay healthy"
```

Claude Code 第一次启动时，请允许自定义 `dummy` API key。它只是本机占位符。真实登录由 copilot-relay 保存。

如果这个 key 被拒绝，请看 [Claude Code](Claude-Code-zh-CN.md)。

## 日常命令

```sh
rr main          # 创建或恢复 RMUX 会话 main
rl               # 列出 RMUX 会话
rd main          # 删除 RMUX 会话 main
claude           # 启动 Claude Code
cc my-project    # 启动 Claude Code 并设置窗口标题
copilot          # 启动 Copilot CLI
gg my-project    # 启动 Copilot CLI 并设置窗口标题
```

新的 SonicTerm 标签页是普通 shell。它不会自动加入 RMUX。

在 RMUX 中，下面的操作只会分离，并保留会话：

- `exit`
- `logout`
- 空提示符上的 Ctrl+D
- `Ctrl+q`，再按 `d`
- 关闭已连接的 SonicTerm 标签页

只有想删除会话时才使用 `rd <名称>`。RMUX 把会话放在内存中。重启电脑或 RMUX 守护进程停止后，会话会消失。

请看 [RMUX](RMUX-zh-CN.md) 和[完整按键表](RMUX-Keymap-zh-CN.md)。

## 更新

```sh
cd ~/Public/dot-configs
git pull
./install.sh
```

安装器是幂等的。正确链接不会改变。不同的文件或链接会先备份，再被替换。

## 检查仓库

```sh
scripts/check.sh all
```

也可以只运行一个检查：

```sh
scripts/check.sh instructions
scripts/check.sh wiki
scripts/check.sh rmux
```

## 本机数据留在本机

不要把这些内容放进 Git：

- API key 或 token
- `~/.copilot-relay/github_token`
- `copilot_token.json`
- relay 或 SonicTerm 日志
- SonicTerm save lock
- 本机 MCP secret
- 生成的 Claude 状态

带 secret 的 MCP 项目应放在每台 Mac 的 `~/.config/github-copilot/mcp.json`。

下一页：[仓库操作](Repository-Operations-zh-CN.md)。
