# Apollo 主题

[English](Apollo-Theme.md) | 简体中文

Apollo 是当前终端、multiplexer、shell、CLI 状态栏和文件列表共享的主题。

规范 palette 和应用 adapters 位于 [Apollo Theme monorepo](https://github.com/apollo-theme/apollo-theme)。本仓库不保存 palette 值或生成的主题文件。

## 生效范围

| 范围 | 来源 |
|---|---|
| SonicTerm | `apollo-theme/apollo-theme` 的 `sonicterm-v0.2.1` release asset `apollo.toml` |
| RMUX | `apollo-theme/apollo-theme` 的 `rmux-v0.2.1` release asset `apollo-rmux.conf` |
| 原生 tmux | `apollo-theme/apollo-theme` 的 `tmux-v0.2.1` release asset `apollo.tmux` |
| eza | `apollo-theme/apollo-theme` 的 `eza-v0.2.1` release asset `theme.yml` |
| Claude Code UI | 从带 tag 的规范 palette 在本机生成 |
| Claude 与 Copilot 状态栏 | 从规范 palette 生成一个本机共享 include |
| Oh My Zsh prompt（可选） | 结构在本仓库；颜色在本机生成；仅通过 `.zshrc` 选择 |
| fast-syntax-highlighting | 使用它的 Base16 主题和终端 ANSI palette |
| Copilot CLI UI | 使用内置 `default` 主题和终端 ANSI palette |

原生 tmux 和 RMUX 使用相同的 Apollo 主题及状态栏样式：斜边会话和窗口标签、应用图标、简洁时钟，以及 prefix/zoom 标记。两个引擎各用自己的官方 release asset。原生 tmux 主题不需要 TPM 或 plugin bootstrap。已有 tmux plugins 和 resurrect 文件保持不动。配置说明见 [Tmux](Tmux-zh-CN.md) 和 [RMUX](RMUX-zh-CN.md)。

Neovim 在另一个仓库中管理。本安装器不会修改 Neovim 配置、plugins 或运行状态。

## Release lock

`scripts/apollo-releases.tsv` 固定每个上游仓库、tag 和 artifact。它不记录 checksum：已发布的 `<id>-vX.Y.Z` release 就是版本。所有行都使用 `apollo-theme/apollo-theme` monorepo。palette 使用 `vX.Y.Z` tag；每个应用使用自己的 `<id>-vX.Y.Z` release，验证器会拒绝其他应用的 tag。各应用版本互相独立；不要根据 palette release 推断它们的 tag。

更新某个应用时，在 [releases 页面](https://github.com/apollo-theme/apollo-theme/releases) 选它最新的 `<id>-vX.Y.Z` release，把该 tag 写进对应行。`scripts/check.sh apollo-online` 会下载每个固定的文件。

安装器下载精确 tag 文件。它不跟踪 `main`，也不查询 `latest`。维护者可以在线检查发布文件：

```sh
scripts/check.sh apollo-online
```

普通 `scripts/check.sh all` 仍然离线运行。

## 本机 bundle

已验证文件位于：

```text
~/.local/share/dot-configs/apollo/
  blobs/
  sets/
  current -> sets/<bundle-hash>
  fsh/
```

Bundle hash 包含 release lock 和 adapter code。下载按仓库、tag 和 artifact 缓存：新 tag 只下载一次，未改变的 tag 不会再下载。安装器先创建完整 set；所有 release 文件和生成 adapters 都通过检查后，才切换 `current`。有效 bundle 可以离线使用。下载失败时，旧 bundle 保持生效。

使用者链接到 `current`：

```text
~/.sonicterm/themes/apollo.toml
~/.config/rmux-apollo-theme/apollo-rmux.conf
~/.config/tmux-apollo-theme/apollo.tmux
~/.config/eza-apollo-theme/theme.yml
~/.claude/themes/apollo.json
```

生成的运行文件是本机状态。不要提交它们。

### 状态栏颜色角色

共享 include 从规范 `foregroundBright` 颜色生成 `C_FG_BRIGHT`。Copilot 用它显示 Model、Effort、Path 和 Branch 的值。旧 bundle 回退到普通前景色；无色模式仍输出纯文本。Claude 保持原有颜色。

## 更新

更新 Apollo：

1. 在对应 Apollo 仓库中检查新 release。
2. 只修改 `scripts/apollo-releases.tsv` 中对应一行的 tag。
3. 运行 `scripts/check.sh apollo-online`。
4. 运行 `scripts/check.sh all`。
5. 运行两次 `./install.sh`。
6. 准备好后重载 SonicTerm，再启动新的 Claude 与 Copilot session。

安装不会重载或停止运行中的 tmux 或 RMUX 服务器。新服务器会读取配置。只有显式重载，才会把更改应用到已有服务器；请看 [Tmux](Tmux-zh-CN.md) 和 [RMUX](RMUX-zh-CN.md)。不要用 `ts` 或 `rs` 应用主题。

不要把上游颜色复制到 config、scripts 或 Wiki 页面中。

## 安全清理

旧 `themes/apollo/` 副本已经删除。

手动创建的 Vim、Neovim、VS Code 或 Windows Terminal 主题文件都属于用户，安装器永远不会删除。

请看 [SonicTerm 与 Shell](SonicTerm-and-Shell-zh-CN.md)、[Tmux](Tmux-zh-CN.md)、[RMUX](RMUX-zh-CN.md)和[开发与发布](Development-and-Releases-zh-CN.md)。
