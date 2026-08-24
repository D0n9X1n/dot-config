# 已归档的 tmux 配置

[English](Archive-Tmux.md) | 简体中文

原 `.tmux.conf` 保存在 `archive/tmux/.tmux.conf`，仅用于参考和回滚。它不再链接到 `~/.tmux.conf`，`install.sh` 也不再安装 tmux 或初始化 TPM。

## 已迁移到 RMUX 的行为

当前 `config/rmux/rmux.conf` 保留了 `C-q` prefix、顶部 Gruvbox 状态栏、从 1 开始的编号、继承当前目录的分割和窗口、vim 风格窗格移动与缩放、vi 复制模式、真彩色处理、固定标题，以及显式的 `prefix + Tab` 行为。

## 未迁移的内容

以下插件栈只作为历史配置保留：

- TPM
- tmux-sensible
- tmux-yank
- tmux-resurrect
- tmux-continuum

RMUX 支持大量 tmux 命令和配置格式，但不保证任意 TPM 插件兼容。让 RMUX 加载归档文件可能执行 `run-shell`、克隆 TPM 并调用恢复脚本；不要把它当作 RMUX 配置使用。

## 保留的本地状态

迁移不会删除已安装的 tmux 二进制、`~/.tmux/plugins/` 或 `~/.local/share/tmux/resurrect/`。它们是本地回滚数据，不属于当前生效的仓库配置。

若要恢复 tmux 管理，请把归档文件移回仓库根目录并命名为 `.tmux.conf`，恢复安装脚本中的 formula 和 TPM 逻辑，再运行 `install.sh`。切换复用器所有权之前先检查当前 RMUX 会话。

参阅 [RMUX](RMUX-zh-CN.md) 和[已归档的 WezTerm 配置](Archive-WezTerm-zh-CN.md)。
