# 仓库操作

[English](Repository-Operations.md) | 简体中文

本页说明文件放在哪里，以及 `install.sh` 如何把文件安装到用户目录。

## 文件夹规则

```text
config/   现在使用的配置
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

清单检查会排除 SonicTerm 的 `*.save.lock` 运行时文件。保留这些已忽略的锁文件，不要加入清单或 Git。

## 生效路径

| 仓库源文件 | 用户目录目标或工作 |
|---|---|
| `config/git/ignore` | `~/.config/git/ignore` |
| `config/rmux/rmux.conf` | `~/.rmux.conf` |
| `config/tmux/tmux.conf` | `~/.tmux.conf` |
| `config/sonicterm/**.toml` | `~/.sonicterm/` 下的对应文件 |
| `config/zsh/**` | `~/.oh-my-zsh/custom/` 下的对应文件 |
| `config/zsh/zz-tmux.zsh` | `~/.oh-my-zsh/custom/zz-tmux.zsh` |
| `config/claude/**` | `~/.claude/` |
| `config/copilot/**` | `~/.copilot/` |
| `config/copilot-relay/config.yaml` | `~/.copilot-relay/config.yaml` |
| `config/mcp/mcp-shared.json` | 合并到本机 Copilot MCP 数据 |
| `config/launchd/*.plist` | 渲染到 `~/Library/LaunchAgents/` |
| `scripts/copilot/cleanup-legacy.sh` | `~/.copilot/cleanup-legacy.sh` |
| `scripts/rmux/rmux-store` | `~/.local/bin/rmux-store` |
| `scripts/rmux/store.py` | `~/.local/lib/rmux-store/store.py` |
| `scripts/tmux/tmux-store` | `~/.local/bin/tmux-store` |
| `scripts/tmux/store.py` | `~/.local/lib/tmux-store/store.py` |
| `scripts/mux/workspace.py` | `~/.local/lib/mux/workspace.py` |

清单不接受归档源文件。Wiki 页面永远不会被安装。

## 外部主题文件

Apollo 主题文件不保存在 Git 中，也不作为 manifest source。`scripts/apollo-releases.tsv` 固定精确的上游 tag 和 SHA-256。`install.sh` 验证这些文件，在 `~/.local/share/dot-configs/apollo/` 下构建完整本机 set，再把 SonicTerm、RMUX、原生 tmux、eza 和 Claude 的生效主题路径链接到该 set。

状态栏、shell prompt 和 Claude 主题的生成文件，是从已验证规范 palette 派生的本机运行状态。下载失败或 checksum 不匹配时，不会替换当前 set。请看 [Apollo 主题](Apollo-Theme-zh-CN.md)。

## 安全链接

对于大多数 `link` 行，`install.sh` 会这样做：

1. 如果链接已经指向正确源文件，就不改它。
2. 只有链接指向精确的旧仓库路径时，才删除旧链接。
3. 其他文件或链接会移动为 `<名称>.bak.YYYYMMDDHHMMSS`。
4. 创建新链接。
5. 为每个目标保留最新备份。

原生 tmux 链接使用不裁剪备份的路径。范围包括 `~/.tmux.conf`、`zz-tmux.zsh`、`tmux-store` 和 tmux-store/共享 mux 库。用户文件或外部链接会获得不会冲突的备份名，必要时加数字后缀。所有已有备份都会保留，即使受管链接已经正确也不清理。

用户文件不会被静默删除。指向其他位置的链接也不会被静默删除。它们会先变成备份，再创建受管链接。

从旧根目录路径迁移到 `config/` 会在同一次安装中完成。精确指向旧根目录受管源的 `~/.tmux.conf` 会迁移到 `config/tmux/tmux.conf`；它重新启用，不再属于停用项。

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

可选 MCP server 的 token 和 API key 只能放在本机 Copilot MCP 文件中。不要把它们加入本仓库。

Copilot 内置 `github-mcp-server`，使用已有的 GitHub 登录。Claude 通过已认证的 `gh` 处理 GitHub 工作。本仓库不再配置单独的 GitHub MCP 条目或 PAT；共享 MCP 同步仍服务于 Playwright 和其他已配置的 server。

Claude 的 local scope 条目位于 `~/.claude.json` 的 `projects[].mcpServers` 下。它们替换同名用户级条目，不会合并 header。MCP 导入会保留这些本机条目。

## 复用器生命周期

`tt`/`tr` 通过分离的引导进程创建原生 tmux 服务器，并在连接前验证父 PID 为 1。已有服务器直接复用，不重启，也不强制更换父进程。关闭 SonicTerm 只断开客户端，不停止服务器。退出前不需要 `ts`；`td` 才是主动删除会话。崩溃或系统重启仍可能丢失运行中的进程。完整生命周期和快照限制见 [Tmux](Tmux-zh-CN.md)。

## 本机状态

这些路径是本机状态，不是配置源：

- `~/.claude.json` — Claude onboarding、允许项、选中的 Apollo 主题、项目状态和 MCP 状态
- `~/.local/share/dot-configs/apollo/` — 已验证 Apollo releases 和生成的运行 adapters
- `~/.copilot-relay/github_token` — relay 认证
- `~/.copilot-relay/copilot_token.json` — relay token cache
- `~/.copilot-relay/logs/` — relay 日志
- `~/.sonicterm/logs/` — SonicTerm 日志
- SonicTerm save lock 和备份
- `~/.local/state/tmux-store/<socket-hash>/` — 原生 tmux 工作区状态，各 socket 独立
- `~/.local/state/rmux-store/` 和 `~/.local/share/rmux-store/` — RMUX 快照及保留的客户端/守护进程组合
- `~/.tmux/plugins/` 和旧 resurrect 文件 — 保留，不加载也不清理

本机状态和用户全局文件不是一回事。`~/.claude/CLAUDE.md` 和 `~/.copilot/copilot-instructions.md` 是用户全局文件：它们链接到 `config/` 中的受管源文件，在本仓库修改后重新安装。`~/.claude.json` 是工具自己拥有的本机状态。MCP 导入只替换其顶层 `mcpServers` 字段，不修改按项目设置的覆盖。安装器的其他步骤可能更新本机偏好，例如选中的 Apollo 主题。

## 已停用链接

WezTerm 仍然停用。只有当 `~/.wezterm.lua` 和停用的 SonicTerm `wezterm.toml` 仍指向本仓库过去的精确受管路径时，安装器才会删除它们。用户自己的文件和链接会保留。手动安装的编辑器主题永远不会删除。

原生 tmux 通过 `config/tmux/tmux.conf` 和 `~/.tmux.conf` 重新启用，但不恢复旧 TPM 设置。已有 plugins、resurrect 文件和 tmux 备份保持不动。请看 [Tmux](Tmux-zh-CN.md)。

重复的 `~/.copilot/AGENTS.md` 链接也只在指向本仓库当前或过去的受管源文件时删除。用户文件和其他链接会保留。

旧 tmux 配置和已停用的 WezTerm 配置保留在 Git 历史中。查看 v2.4.0 的副本：

```sh
git show v2.4.0:archive/tmux/.tmux.conf
git show v2.4.0:archive/wezterm/wezterm.lua
```

这些副本仅供参考，不是生效配置。以后添加受管文件时，仍须遵循当前清单规则。

## 应用与检查

```sh
scripts/check.sh all
# 修改 release pins 后还需运行 scripts/check.sh apollo-online。
./install.sh
./install.sh
```

然后检查主要链接：

```sh
ls -l ~/.rmux.conf ~/.tmux.conf ~/.claude/settings.json ~/.copilot/settings.json \
  ~/.copilot-relay/config.yaml ~/.sonicterm/sonicterm.toml
ls -l ~/.oh-my-zsh/custom/zz-tmux.zsh ~/.local/bin/tmux-store \
  ~/.local/lib/tmux-store/store.py ~/.local/lib/mux/workspace.py \
  ~/.config/tmux-apollo-theme/apollo.tmux
```

安装不会重载或停止运行中的 tmux 或 RMUX 服务器。新服务器会读取已安装配置。应用到已有服务器必须显式操作，请看 [Tmux](Tmux-zh-CN.md)。永远不要自动运行 `ts` 或 `rs`。

更多服务检查在[服务与自动化](Services-and-Automation-zh-CN.md)。
