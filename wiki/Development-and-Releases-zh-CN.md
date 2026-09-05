# 开发与发布

[English](Development-and-Releases.md) | 简体中文

本页是检查、Wiki 发布、issues、tags 和 releases 的唯一可信来源。

## 修改前

先阅读要修改工具的 Wiki 页面。编辑 `config/` 或 `scripts/` 下的源文件，不要编辑 `$HOME` 中安装的链接。

保持改动小。不要添加任务不需要的新行为。

## Shell 规则

Shell 脚本使用：

```sh
#!/usr/bin/env bash
set -euo pipefail
```

保持 macOS Bash 3.2 支持：

- 不使用关联数组；
- 不使用 `printf '%(...)T'`；
- 不使用 Bash `\u` escapes；
- 使用可移植的 `awk`、`sed`、`grep` 和 `find`；
- 需要时间时，使用 `stat -f %m`，并提供 `stat -c %Y` fallback。

状态栏函数应尽量使用 `printf -v`，不要使用命令替换。

## 一起修改的文件

一个状态栏变化时，同时更新：

```text
config/claude/statusline.sh
config/copilot/statusline.sh
```

保持相同五行布局、palette 和每目录 Git cache。Provider 字段保持不同：Claude 显示费用；Copilot 显示 premium 请求和自定义 live-subagent rows。

模型家族保持分开：

- Sonnet 端默认值通过 `gptModel` 路由。
- Opus 名称通过 `opusModel` 路由。

任务只说一个家族时，不要修改两个。

任何用户可见或行为变化，都要在同一改动中更新对应英文和中文 Wiki 页面。根 README 保持简短。

## 本机检查

运行全部：

```sh
scripts/check.sh all
```

单项检查：

```sh
scripts/check.sh smoke
scripts/check.sh apollo
scripts/check.sh apollo-online
scripts/check.sh shellcheck
scripts/check.sh instructions
scripts/check.sh models
scripts/check.sh mcp
scripts/check.sh wiki
scripts/check.sh rmux
```

`models` 断言受管模型选择器：Claude 设置和启动器 wrapper 中的原生客户端 ID、Copilot 自己的 GPT-6 Astra 设置，以及 relay 独立的 Opus 路由。`mcp` 覆盖安装器只读的 GitHub MCP 覆盖警告。

状态栏布局、缓存和生成的 palette 由两个 provider 共享，所以修改任一脚本或生成器时，由 `apollo` 和 `smoke` 一起检查。provider 各自的强调仍然不同：Copilot 使用亮前景角色并保留实时 subagent 行，Claude 两者都不用。修改共享生成器时，保持 Claude 输出不变。

CI 使用同一个脚本：

- macOS 安装 RMUX 并运行 smoke checks；
- Ubuntu 安装 ShellCheck 并运行 ShellCheck target。

普通检查不会访问网络。`apollo-online` 是维护者专用检查，会下载所有固定的上游文件并验证 SHA-256。每次修改 `scripts/apollo-releases.tsv` 时都要运行它。

检查失败时不要推送。

## Wiki 源规则

源文件在扁平的 `wiki/` 文件夹中。

规则：

- `README.md` 是英文首页源文件。
- 它发布为 `Home.md`。
- 每个英文页面有一个 `-zh-CN.md` 页面。
- 每对页面互相链接。
- `_Sidebar.md` 在每种语言中只链接每个页面一次。
- 源链接使用 `Page-Name.md`。
- 不要使用跨页 `Page-Name.md#anchor` 链接。
- 同一页面的 `#anchor` 链接可以使用。

运行：

```sh
scripts/check.sh wiki
```

## Wiki 脚本

`scripts/wiki-render.sh` 把源页面复制到干净输出文件夹，把 `README.md` 重命名为 `Home.md`，并从扁平内部链接中去掉 `.md`。

`scripts/wiki-publish.sh` 克隆或使用 live Wiki repo，调用 render 脚本，替换受管 Markdown 页面，只在内容变化时提交，并且不会 force push。

Workflow 很小。它只 checkout 仓库并调用 publish 脚本。

网页编辑不是源。下一次发布会替换它们。

## Wiki 完成条件

合并后的 Wiki 改动，在检查 workflow 和 live 页面前不算完成：

```sh
gh run list --workflow=publish-wiki.yml --limit 3
gh run view <run-id>
git clone https://github.com/OWNER/REPO.wiki.git /tmp/REPO-wiki-live
grep -REn '\]\([A-Za-z0-9_-]+\.md\)' /tmp/REPO-wiki-live/*.md
```

最新 run 必须匹配 merge commit。Grep 不应找到内容。打开 live Wiki，在两种语言中点击新的或修改过的链接。

## Issues 与 milestones

每个工作项都需要 GitHub issue。把 issue 放到 release milestone 中。在 commit 中使用 closing words，或在改动进入 `main` 后关闭 issue。

Release 前：

1. 检查所有工作项 issue 已关闭。
2. 检查它们属于 release milestone。
3. 工作完成后关闭 milestone。

## 版本

Tag 使用 `vX.Y.Z`：

- patch 用于修复；
- minor 用于新功能；
- major 用于破坏性变化。

创建新的 annotated tag。永远不要移动或复用 release tag。

```sh
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

## Release notes

`scripts/release-notes.sh` 从 commit subjects 生成 notes。

它会：

1. 找到当前 tag commit；
2. 从 `${current_commit}^` 找到上一个可达 `v*.*.*` tag；
3. 使用 `git log --reverse --format='- %s'` 生成从旧到新的 bullets；
4. 没有旧 tag 时写入首次 release fallback。

Release workflow checkout 完整历史，调用脚本，并把 `release-notes.md` 交给 `softprops/action-gh-release@v2`。

## Release 完成条件

推送 tag 后，在检查 workflow 和 live release 前不算完成：

```sh
gh run list --workflow=release.yml --limit 3
gh run view <run-id>
gh release view vX.Y.Z
git log --reverse --format='- %s' vPREVIOUS..vX.Y.Z
```

Run 必须指向 tag commit。Live body 必须有正确的上一个 tag 标题，并按顺序包含精确 commit subjects。

## 安全 Git 工作

- 永远不要提交 secrets 或 runtime 文件。
- 除非用户要求，不使用 `--no-verify`。
- 不 force push。
- Commit 前检查 staged 文件。
- 不把无关本机修改放进 commit。
- 可能丢失工作前先运行 `git status`。

已安装文件和本机状态边界请看[仓库操作](Repository-Operations-zh-CN.md)。
