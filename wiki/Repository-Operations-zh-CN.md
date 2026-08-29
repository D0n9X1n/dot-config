# 仓库操作

[English](Repository-Operations.md) | 简体中文

本页说明文件放在哪里，以及 `install.sh` 如何把文件安装到用户目录。

## 文件夹规则

```text
config/   现在使用的配置
archive/  旧配置；永远不会安装
scripts/  会运行的代码和外部 release pins
wiki/     完整说明
```

这些文件必须留在固定位置，因为工具会在这里查找：

```text
.claude/CLAUDE.md
.github/copilot-instructions.md
.github/workflows/*.yml
.gitignore
install.sh
ReadMe.md
```

## 清单

`config/manifest.tsv` 是生效的安装清单。安装器不会扫描根目录中的随机 dotfile。

每行有三个 tab 分隔字段：

```text
type<TAB>source<TAB>home destination
```

类型：

| 类型 | 工作 |
|---|---|
| `link` | 在 `$HOME` 中创建符号链接 |
| `merge` | 把安全共享数据合并到本机文件 |
| `render` | 填充模板并写入本机文件 |

安装器会检查每个源文件存在、每个目标唯一，并且每个源文件都在 `config/` 或 `scripts/` 下。

## 生效路径

| 仓库源文件 | 用户目录目标或工作 |
|---|---|
| `config/git/ignore` | `~/.config/git/ignore` |
| `config/rmux/rmux.conf` | `~/.rmux.conf` |
| `config/sonicterm/**.toml` | `~/.sonicterm/` 下的对应文件 |
| `config/zsh/**` | `~/.oh-my-zsh/custom/` 下的对应文件 |
| `config/claude/**` | `~/.claude/` |
| `config/copilot/**` | `~/.copilot/` |
| `config/copilot-relay/config.yaml` | `~/.copilot-relay/config.yaml` |
| `config/mcp/mcp-shared.json` | 合并到本机 Copilot MCP 数据 |
| `config/launchd/*.plist` | 渲染到 `~/Library/LaunchAgents/` |
| `scripts/copilot/cleanup-legacy.sh` | `~/.copilot/cleanup-legacy.sh` |

安装器永远不会链接 `archive/` 或 `wiki/`。

## 外部主题文件

Apollo 主题文件不保存在 Git 中，也不作为 manifest source。`scripts/apollo-releases.tsv` 固定精确的上游 tag 和 SHA-256。`install.sh` 验证这些文件，在 `~/.local/share/dot-configs/apollo/` 下构建完整本机 set，再把 SonicTerm、RMUX、eza 和 Claude 的生效主题路径链接到该 set。

状态栏、shell prompt 和 Claude 主题的生成文件，是从已验证规范 palette 派生的本机运行状态。下载失败或 checksum 不匹配时，不会替换当前 set。请看 [Apollo 主题](Apollo-Theme-zh-CN.md)。

## 安全链接

对于每个 `link` 行，`install.sh` 会这样做：

1. 如果链接已经指向正确源文件，就不改它。
2. 只有链接指向精确的旧仓库路径时，才删除旧链接。
3. 其他文件或链接会移动为 `<名称>.bak.YYYYMMDDHHMMSS`。
4. 创建新链接。
5. 为每个目标保留最新备份。

用户文件不会被静默删除。指向其他位置的链接也不会被静默删除。它们会先变成备份，再创建受管链接。

从旧根目录路径迁移到 `config/` 会在同一次安装中完成。

## 添加或修改配置

编辑仓库源文件。不要编辑 `$HOME` 中的链接文件。

添加受管文件：

1. 把它放到 `config/` 或 `scripts/`。
2. 在 `config/manifest.tsv` 中添加一行。
3. 添加或更新对应的双语 Wiki 页面。
4. 运行 `scripts/check.sh all`。
5. 运行两次 `./install.sh`。
6. 检查链接或渲染文件。

第二次安装不应产生意外变化。

## 安装器开关

只在需要时使用：

```sh
SKIP_BREW=1 ./install.sh
SKIP_NPM_GLOBALS=1 ./install.sh
SKIP_OH_MY_ZSH=1 ./install.sh
DOT_CONFIGS_INSTALL_LOG=/tmp/install.log ./install.sh
```

普通日志在 `~/Library/Logs/dot-configs-install.log`。

## 共享与秘密 MCP 数据

`config/mcp/mcp-shared.json` 只能包含安全、公开的 server 数据。

安装器会把它合并到：

```text
~/.config/github-copilot/mcp.json
```

本机 Copilot 项目会保留。同名 server 存在时，共享项目优先。然后，合并后的 Copilot server map 会替换 `~/.claude.json` 顶层的 `mcpServers` 字段。

只添加到 `~/.claude.json` 的 server 会在下一次安装时被删除。两个工具都需要的 server 应放在本机 Copilot MCP 文件中。

Token 和 API key 只能放在本机 Copilot MCP 文件中。不要把它们加入本仓库。

托管 GitHub MCP 使用 Bearer PAT header。它的 OAuth dynamic client registration 不适用于当前设置。

## 本机状态

这些路径是本机状态，不是配置源：

- `~/.claude.json` — Claude onboarding、允许项、选中的 Apollo 主题、项目状态和 MCP 状态
- `~/.local/share/dot-configs/apollo/` — 已验证 Apollo releases 和生成的运行 adapters
- `~/.copilot-relay/github_token` — relay 认证
- `~/.copilot-relay/copilot_token.json` — relay token cache
- `~/.copilot-relay/logs/` — relay 日志
- `~/.sonicterm/logs/` — SonicTerm 日志
- SonicTerm save lock 和备份
- `~/.tmux/plugins/` 和旧 resurrect 文件

## 已停用链接

安装器不再安装 tmux 或 WezTerm。只有当 `~/.tmux.conf`、`~/.wezterm.lua` 和停用的 SonicTerm `wezterm.toml` 仍指向本仓库过去的精确受管路径时，才会删除它们。用户自己的文件和链接会保留。手动安装的编辑器主题永远不会删除。

请看[已归档的 tmux](Archive-Tmux-zh-CN.md)和[已归档的 WezTerm](Archive-WezTerm-zh-CN.md)。

## 应用与检查

```sh
./install.sh
./install.sh
scripts/check.sh all
```

然后检查主要链接：

```sh
ls -l ~/.rmux.conf ~/.claude/settings.json ~/.copilot/settings.json \
  ~/.copilot-relay/config.yaml ~/.sonicterm/sonicterm.toml
```

更多服务检查在[服务与自动化](Services-and-Automation-zh-CN.md)。
