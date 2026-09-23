# 开始使用

[English](Getting-Started.md) | 简体中文

本仓库只用于 macOS。`install.sh` 可以设置一台新 Mac。重复运行是安全的。

## 安装

```sh
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
cd ~/Public/dot-configs
./install.sh
```

脚本可以安装 Homebrew、原生 tmux、RMUX、Claude Code、Copilot CLI、copilot-relay、shell 工具、字体和 oh-my-zsh。它会下载并验证固定的 Apollo theme releases，构建本机 adapters，然后链接 `config/manifest.tsv` 中列出的文件。

原生 tmux 和 RMUX 并存，使用相同的 Apollo 主题和状态栏样式。会话与状态各自独立。原生配置面向 tmux 3.7，本机已经安装。

第一次 Apollo 安装需要网络。以后可以复用 `~/.local/share/dot-configs/apollo/` 下已验证的本机 bundle。

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
tt main          # 按完整名称连接或创建原生 tmux 会话 main
tr main          # 交互式 shell 中 tt main 的快捷方式
tl               # 列出原生 tmux 会话，不启动服务器
td main          # 按完整名称删除原生 tmux 会话 main
th               # 原生 tmux 帮助
rr main          # 创建或恢复 RMUX 会话 main
rl               # 列出 RMUX 会话
rd main          # 删除 RMUX 会话 main
claude           # 启动 Claude Code
cc my-project    # 启动 Claude Code 并设置窗口标题
copilot          # 启动 Copilot CLI
gg my-project    # 启动 Copilot CLI 并设置窗口标题
```

新的 SonicTerm 标签页是普通 shell。两个引擎都不会自动连接。`tt` 拒绝在 RMUX 内连接，请先分离。

`tt`/`tr` 以分离模式创建 tmux 服务器，并在连接前验证父 PID 为 1。已有服务器不受影响。关闭 SonicTerm 后服务器继续运行，不需要先执行 `ts`。

`tr` 只是交互式 zsh 的 shell 函数。一个非选项参数选择 tmux 会话；两个参数或选项形式调用文本工具。`command tr` 始终调用文本工具。

在原生 tmux 或 RMUX 中，下面的操作只会分离，并保留会话：

- `exit`
- `logout`
- 空提示符上的 Ctrl+D
- `Ctrl+q`，再按 `d`
- 关闭已连接的 SonicTerm 标签页

有文字时，Ctrl+D 保持正常编辑行为。两个引擎之外的 shell 退出行为不变。

用 `td <名称>` 删除原生 tmux 会话，用 `rd <名称>` 删除 RMUX 会话。分离不是备份：服务器停止或 Mac 重启后，两个引擎都会失去运行中的会话。`ts` 和 `rs` 是手动、需确认的全部会话重启操作，只以新 shell 恢复工作区布局，不恢复运行中的程序或历史。永远不要自动运行它们。

请看 [Tmux](Tmux-zh-CN.md)、[原生 tmux 按键表](Tmux-Keymap-zh-CN.md)、[RMUX](RMUX-zh-CN.md) 和 [RMUX 按键表](RMUX-Keymap-zh-CN.md)。

## 更新

```sh
cd ~/Public/dot-configs
git pull
./install.sh
```

安装器是幂等的。正确链接不会改变。不同的文件或链接会先备份，再被替换。原生 tmux 迁移会保留全部已有 tmux 备份。

安装器不会重载或停止运行中的 tmux 或 RMUX 服务器。新服务器使用已安装配置；只有自行决定时才重载已有服务器，请看 [Tmux](Tmux-zh-CN.md)。修改受管配置后，运行 `scripts/check.sh all`；release pins 有变化时还需运行 `scripts/check.sh apollo-online`，然后运行两次 `./install.sh`。

## 检查仓库

```sh
scripts/check.sh all
```

也可以只运行一个检查：

```sh
scripts/check.sh apollo
scripts/check.sh instructions
scripts/check.sh wiki
scripts/check.sh rmux
scripts/check.sh tmux
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
- 下载或生成的 Apollo 运行文件
- 原生 tmux 和 RMUX 的工作区快照或运行状态

带 secret 的 MCP 项目应放在每台 Mac 的 `~/.config/github-copilot/mcp.json`。

下一页：[仓库操作](Repository-Operations-zh-CN.md)。
