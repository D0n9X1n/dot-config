# 自定义

[English](Customization.md) | 简体中文

本页说明如何添加自己的文件，而不修改上游文件。这样你的修改永远不会和上游更新冲突。

## 规则

上游永远不会添加、修改或跟踪 `local/` 下的任何内容。CI 会检查这一点。把你自己的文件都放在这里。

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

要修改上游管理的工具，请添加一个该工具会加载的独立文件，而不是复制一份上游文件。

删除一行不会删除它以前的链接。请手动删除那个链接。

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
| 嵌套 local 仓库 | `local/` 是独立 Git 仓库 | 是 | `uu` |
| 公开 fork | 提交到 fork 的 `local/` | 否 | Sync fork，然后 `uu` |

本仓库是公开的，所以 fork 也是公开的。不要把 token、密钥或认证文件提交到 fork。私有内容请使用私有 overlay。

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

### 嵌套 local 仓库

在上游克隆中，把 `local/` 设为独立 Git 仓库：

```sh
cd ~/Public/dot-configs
git init local
echo local/ >> .git/info/exclude
```

`.git/info/exclude` 会对外层仓库隐藏 `local/`，且不修改被跟踪的 `.gitignore`。给 `local/` 添加 remote 可以保留备份。

### 公开 fork

Fork 上游，然后把你的文件提交到 fork 的 `local/` 下。上游从不修改 `local/`，所以同步不会冲突：

```sh
gh repo sync YOU/dot-config
uu
```

也可以在 GitHub 上点击 **Sync fork**，或运行 `git pull upstream main` 后再 push。

## 更新

`uu` 会 fast-forward 检出，然后运行 `./install.sh`。如果 overlay 文件夹有自己的 `.git`，`uu` 会先检查它，再一起 fast-forward。工作区有未提交修改、detached HEAD、没有 upstream，或分支无法 fast-forward 时，`uu` 会在任何检出移动前停止。

Fork 自己的提交会让它的 `main` 与上游不同。请先在 GitHub 上同步 fork，然后 `uu` 才能 fast-forward。

## 检查

```sh
scripts/check.sh local
scripts/check.sh all
./install.sh
ls -l ~/.oh-my-zsh/custom/zzz-local-*
```

上游清单和链接规则请看 [仓库操作](Repository-Operations-zh-CN.md)。
