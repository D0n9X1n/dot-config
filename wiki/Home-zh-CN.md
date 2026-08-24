# dot-config Wiki

[English](README.md) | 简体中文

本 Wiki 记录 [D0n9X1n/dot-config](https://github.com/D0n9X1n/dot-config) 中的 macOS dotfiles。仓库内的 `wiki/` 目录是唯一可信来源；下一次从 `main` 分支发布时，会覆盖在 GitHub Wiki 网页中直接进行的编辑。

## 从这里开始

- [RMUX](RMUX-zh-CN.md) — 终端复用器架构、配置、快捷键、Claude teammate mode、安全注意事项和验证方法。
- [已归档的 tmux 配置](Archive-Tmux-zh-CN.md) — 已停用的 TPM 配置及回滚说明。
- [已归档的 WezTerm 配置](Archive-WezTerm-zh-CN.md) — 已停用的 Lua 配置及仍保留兼容名称的原因。

## 仓库管理方式

- `install.sh` 用于初始化 macOS，并把受管配置以符号链接安装到用户目录。
- `.rmux.conf` 是当前使用的复用器配置，安装到 `~/.rmux.conf`。
- SonicTerm 是当前受管的外层终端；本仓库不再安装 tmux 或 WezTerm。
- `archive/` 只保存历史配置，不会被安装脚本链接。
- `QUICKREF.md` 仍是面向 agent 的运行规则来源；`ReadMe.md` 是完整的人类可读指南。

## 快速开始

```sh
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
bash ~/Public/dot-configs/install.sh
rmux
```

提交变更前运行 `scripts/check.sh all`。认证及各应用的详细安装步骤请参阅仓库 README。
