# dot-config Wiki

[English](README.md) | 简体中文

本 Wiki 是本仓库的完整说明。

源文件在扁平的 `wiki/` 文件夹中。GitHub Actions 会把它发布到 GitHub Wiki。网页中的直接修改，会在下一次从 `main` 发布时被替换。

## 开始

- [开始使用](Getting-Started-zh-CN.md) — 安装文件并运行常用工具。
- [仓库操作](Repository-Operations-zh-CN.md) — 了解文件夹、清单、链接和安全更新流程。

## 工具

- [Claude Code](Claude-Code-zh-CN.md) — relay、模型、设置、agents 和问题处理。
- [Copilot CLI](Copilot-CLI-zh-CN.md) — 默认模型、全局规则、状态栏和 WakaTime。
- [RMUX](RMUX-zh-CN.md) — 会话、窗格、恢复、剪贴板和 Claude teams。
- [RMUX 按键表](RMUX-Keymap-zh-CN.md) — 全部 278 个生效按键。
- [SonicTerm 与 Shell](SonicTerm-and-Shell-zh-CN.md) — 终端文件、zsh 助手和启动器。

## 维护

- [服务与自动化](Services-and-Automation-zh-CN.md) — 安装任务、relay 健康检查、MCP、WakaTime 和缓存清理。
- [开发与发布](Development-and-Releases-zh-CN.md) — 检查、Wiki 发布、issues、tags 和 releases。
- [Apollo 主题](Apollo-Theme-zh-CN.md) — 颜色数据和手动编辑器设置。

## 旧文件

- [已归档的 tmux](Archive-Tmux-zh-CN.md) — 旧 TPM 设置和回滚说明。
- [已归档的 WezTerm](Archive-WezTerm-zh-CN.md) — 旧 Lua 配置和兼容名称。

## 主要文件夹

| 文件夹 | 含义 |
|---|---|
| `config/` | 现在使用的配置 |
| `archive/` | 旧配置；永远不会安装 |
| `scripts/` | 会运行的代码 |
| `themes/` | 颜色文件 |
| `wiki/` | 完整说明 |

`install.sh` 保留在根目录。它读取 `config/manifest.tsv`，只安装清单中的文件。

## 快速开始

```sh
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
cd ~/Public/dot-configs
./install.sh
npx copilot-relay auth
./install.sh
```

推送前运行 `scripts/check.sh all`。

这是公开仓库。不要添加 token、key、认证文件、日志或运行状态。
