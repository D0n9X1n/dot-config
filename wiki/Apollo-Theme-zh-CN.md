# Apollo 主题

[English](Apollo-Theme.md) | 简体中文

Apollo 是当前终端、multiplexer、shell、CLI 状态栏和文件列表共享的主题。

规范 palette 和应用 adapters 位于 [Apollo Theme organization](https://github.com/apollo-theme)。本仓库不保存 palette 值或生成的主题文件。

## 生效范围

| 范围 | 来源 |
|---|---|
| SonicTerm | 带 tag 的 `sonicterm-apollo-theme` release asset |
| RMUX | 带 tag 的 `rmux-apollo-theme` release asset |
| eza | 带 tag 的 `eza-apollo-theme` release asset |
| Claude Code UI | 从带 tag 的规范 palette 在本机生成 |
| Claude 与 Copilot 状态栏 | 从规范 palette 生成一个本机共享 include |
| Oh My Zsh prompt | 结构在本仓库；颜色在本机生成 |
| fast-syntax-highlighting | 使用它的 Base16 主题和终端 ANSI palette |
| Copilot CLI UI | 使用内置 `default` 主题和终端 ANSI palette |

Neovim 在另一个仓库中管理。本安装器不会修改 Neovim 配置、plugins 或运行状态。

## Release lock

`scripts/apollo-releases.tsv` 固定每个上游仓库、tag、artifact 和 SHA-256。各子项目版本互相独立；不要根据规范 palette release 推断它们的 tag。

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

Bundle hash 包含 release lock 和 adapter code。安装器会先验证每个下载，再创建完整 set；所有 release 文件和生成 adapters 都通过检查后，才切换 `current`。有效 bundle 可以离线使用。下载失败或 checksum 不匹配时，旧 bundle 保持生效。

使用者链接到 `current`：

```text
~/.sonicterm/themes/apollo.toml
~/.config/rmux-apollo-theme/apollo-rmux.conf
~/.config/eza-apollo-theme/theme.yml
~/.claude/themes/apollo.json
```

生成的运行文件是本机状态。不要提交它们。

## 更新

更新 Apollo：

1. 在对应 Apollo 仓库中检查新 release。
2. 只修改 `scripts/apollo-releases.tsv` 中对应的一行。
3. 更新 SHA-256。
4. 运行 `scripts/check.sh apollo-online`。
5. 运行 `scripts/check.sh all`。
6. 运行两次 `./install.sh`。
7. 重载 SonicTerm 和 RMUX，然后启动新的 Claude 与 Copilot session。

不要把上游颜色复制到 config、scripts 或 Wiki 页面中。

## 安全清理

旧 `themes/apollo/` 副本已经删除。只有当原 SonicTerm `wezterm.toml` 是本仓库过去创建的精确 symlink 时，安装器才会删除它。

手动创建的 Vim、Neovim、VS Code、Windows Terminal 或 WezTerm 主题文件都属于用户，安装器永远不会删除。

请看 [SonicTerm 与 Shell](SonicTerm-and-Shell-zh-CN.md)、[RMUX](RMUX-zh-CN.md)和[开发与发布](Development-and-Releases-zh-CN.md)。
