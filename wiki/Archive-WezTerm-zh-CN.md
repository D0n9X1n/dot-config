# 已归档的 WezTerm 配置

[English](Archive-WezTerm.md) | 简体中文

原受管 Lua 配置保存在 `archive/wezterm/wezterm.lua`。`install.sh` 不再把它链接到 `~/.wezterm.lua`。

## 为什么仍会出现 WezTerm 名称

RMUX 是终端复用器，不是终端模拟器。当前由 `.sonicterm/` 主动管理的 SonicTerm 负责外层终端；安装脚本不再安装 WezTerm，也不再管理其 Lua 配置。

SonicTerm 中与 WezTerm 兼容的 keymap 名称和配色来源仍然是历史兼容信号，但子 PTY 使用原生 `TERM_PROGRAM=SonicTerm`。只有 Copilot 子进程会收到 `TERM_PROGRAM=WezTerm` 及真彩色变量，因为它能识别这条能力路径；这不表示 WezTerm 已安装或正在使用。

## 本地迁移行为

只有当 `~/.wezterm.lua` 仍是本仓库过去创建的精确符号链接时，`install.sh` 才会移除它。普通文件或指向其他目标的符号链接都会保留。

若要恢复旧配置，请把 `archive/wezterm/wezterm.lua` 移回 `wezterm/wezterm.lua`，恢复安装脚本中的链接逻辑，再运行 `install.sh`。

参阅 [RMUX](RMUX-zh-CN.md) 和[已归档的 tmux 配置](Archive-Tmux-zh-CN.md)。
