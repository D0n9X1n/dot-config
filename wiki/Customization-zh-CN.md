# 自定义

[English](Customization.md) | 简体中文

本页说明如何添加自己的文件，而不修改上游文件。这样你的修改永远不会和上游更新冲突。

## 规则

上游永远不会添加、修改或跟踪 `local/` 下的任何内容。CI 会检查这一点；被跟踪的 `.gitignore` 也忽略 `/local/`，所以你的文件不会出现在 `git status` 中，也不会阻止 `uu`。把你自己的文件都放在这里。

不要为个人修改去编辑 `config/manifest.tsv`、`wiki/_Sidebar.md` 或 `scripts/check.sh` 等上游文件。如果确实需要修改这些文件，请在上游开 issue。

## Overlay 文件夹

Overlay 是检出中的 `local/`。把 `DOT_CONFIGS_LOCAL` 设为绝对路径，可以改用其他文件夹。

```text
local/
  manifest.tsv   你自己的链接行
  zsh/*.zsh      你自己的 shell 文件，在所有上游助手之后加载
  check.sh       你自己的检查
  README.md      你自己的说明
```

每一部分都是可选的。文件夹不存在时，`install.sh` 和 `scripts/check.sh` 什么也不做。

### `manifest.tsv`

它使用与 `config/manifest.tsv` 相同的三个 Tab 分隔字段。只允许 `link` 行。源路径相对于 overlay 文件夹。

```text
# type	source	destination
link	config/npmrc	.npmrc
link	bin/my-tool	.local/bin/my-tool
```

出现以下任一情况时，`install.sh` 会在做任何修改前停止：

- 不是 `link` 行；
- 源或目标是绝对路径，或包含 `..`；
- 源文件不存在；
- 目标重复；
- 目标已由上游管理，例如 `.tmux.conf`；
- 使用保留的 `.oh-my-zsh/custom/zzz-local-*` 名称。

要修改上游管理的工具，请添加一个该工具会加载的独立文件，而不是复制一份上游文件。原生 tmux 和 RMUX 会最后加载这样的文件；见下文。

删除一行不会删除它以前的链接。请手动删除那个链接。

### tmux 与 RMUX 覆盖

`~/.tmux.conf` 末尾是 `source-file -q ~/.tmux.local.conf`，`~/.rmux.conf` 末尾是 `source-file -q ~/.rmux.local.conf`。上游从不提供这两个文件。它们最后加载，所以其中设置的任何选项都会生效，包括活动标签颜色 `window-status-current-style`。

```text
# local/manifest.tsv
link	tmux/local.conf	.tmux.local.conf
link	tmux/local.conf	.rmux.local.conf
```

```tmux
# local/tmux/local.conf
set -g window-status-current-style 'bg=#89b4fa,fg=#1e1e2e,bold'
```

新服务器会读取它。要应用到运行中的服务器，请自己运行 `tmux source-file ~/.tmux.conf`（或 RMUX 对应命令）。

### `zsh/*.zsh`

每个 `local/zsh/NAME.zsh` 都会链接到 `~/.oh-my-zsh/custom/zzz-local-NAME.zsh`。Oh-my-zsh 按名称顺序加载文件，所以你的文件最后加载，可以替换上游的 alias 和函数。

删除或重命名 `local/zsh/` 中的文件后，下一次安装会删除它旧的 `zzz-local-*` 链接。它不会删除普通文件，也不会删除指向别处的链接。

### `check.sh`

`scripts/check.sh all`、`smoke` 和 `local` 会先验证 `local/manifest.tsv`，再在仓库根目录用 Bash 运行 `local/check.sh`。`DOT_CONFIGS_LOCAL` 保存 overlay 路径。非零退出码会让检查失败。

上游 ShellCheck 会跳过 `local/`。请在 `local/check.sh` 中检查你自己的文件。zsh 文件可以用 `zsh -n FILE` 检查语法。

### `README.md`

在这里写你自己的说明。上游 Wiki 检查和 Wiki 发布脚本只读取 `wiki/`，所以你的说明不会影响侧边栏或 `-zh-CN` 页面规则。

## 选择方式

| 方式 | 你的文件 | 私有 | 更新 |
|---|---|---|---|
| 私有 overlay 仓库（推荐） | 独立的私有 Git 仓库 | 是 | `uu` |
| 本地文件夹 | 检出中的 `local/`，被 Git 忽略 | 是 | `uu` |
| Fork 镜像 | 本地文件夹或私有 overlay | 是 | `uu`（也会 push 到 fork） |

每种方式中，你的文件都不进入上游历史，所以 `uu` 总能 fast-forward。本仓库是公开的，所以 fork 也是公开的。不要把 token、密钥或认证文件提交到 fork。

### 私有 overlay 仓库

克隆上游，并把你的文件放在独立的私有仓库中：

```sh
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
git clone git@github.com:YOU/dot-config-local.git ~/Public/dot-configs-local
```

在 `~/.zshrc` 中、oh-my-zsh 加载之前添加：

```sh
export DOT_CONFIGS_LOCAL="$HOME/Public/dot-configs-local"
```

然后运行 `./install.sh`。

### 本地文件夹

在上游克隆中创建 `local/`。Git 已经忽略它。

```sh
cd ~/Public/dot-configs
mkdir -p local/zsh
```

要保留备份或历史，用 `git init local` 把它设为独立 Git 仓库，并添加私有 remote。之后 `uu` 也会 fast-forward 它。

### Fork 镜像

让 fork 与上游保持一致，并把你的文件放在本地文件夹或私有 overlay 中。克隆 fork，然后让 `main` 跟踪上游：

```sh
git clone git@github.com:YOU/dot-config.git ~/Public/dot-configs
cd ~/Public/dot-configs
git remote add upstream https://github.com/D0n9X1n/dot-config.git
git fetch upstream
git branch --set-upstream-to=upstream/main main
```

之后 `uu` 会从上游 fast-forward，并把同样的提交 push 到 `origin`，两个仓库保持一致。fork remote 使用其他名字时，设置 `DOT_CONFIGS_FORK_REMOTE`。push 从不强制，也不会等待密码或 SSH passphrase。push 失败时（例如 fork 有自己的提交），`uu` 会显示 Git 的错误，但仍更新检出并安装；请手动同步一次 fork。设置 `DOT_CONFIGS_FORK_REMOTE=none` 可关闭 push。

不要把你自己的文件提交到 fork：那样 fork 就不再与上游一致，push 也会失败。

## 更新

`uu` 会 fast-forward 检出，然后运行 `./install.sh`。如果 overlay 文件夹有自己的 `.git`，`uu` 会先检查它，再一起 fast-forward。工作区有未提交修改、detached HEAD、没有 upstream，或分支无法 fast-forward 时，`uu` 会在任何检出移动前停止。

`./install.sh` 不会修改任何被跟踪的文件。第二次运行不会产生变化；只有 MCP server 映射不同时，它才会重写 `~/.claude.json`。

## 检查

```sh
scripts/check.sh local
scripts/check.sh all
./install.sh
ls -l ~/.oh-my-zsh/custom/zzz-local-*
```

上游清单和链接规则请看 [仓库操作](Repository-Operations-zh-CN.md)。
