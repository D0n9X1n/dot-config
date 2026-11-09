# Herdr

[English](Herdr.md) | 简体中文

[Herdr](https://herdr.dev) 是本仓库用 Apollo 布局配置的终端工作区。布局放在独立的公开仓库 [herdr-config](https://github.com/D0n9X1n/herdr-config) 中。本仓库把它作为 Git 子模块固定在 `config/herdr`。

## 安装做什么

`./install.sh`（以及运行它的 `uu`）在 macOS 上执行这些 Herdr 步骤：

1. **缺少时安装 Herdr。** 如果 `~/Applications` 和 `/Applications` 中都没有 `Herdr.app`，`PATH` 上也没有 `herdr-app`，就运行 `brew install --cask herdr-app`。已有的安装从不改动。失败时只输出一条警告，其余安装继续。`SKIP_BREW=1` 会跳过这一步。
2. **更新子模块。** 运行 `git submodule update --init config/herdr`。离线时会跳过 Herdr 行，并输出一行 `Herdr config:`，其他内容照常安装。
3. **保留你的当前值。** 读取当前的 `settings.json` 和 `keys.json`，有差异时写入 `config/herdr/user/`。如果你的 `keys.json` 仍是 Herdr 默认值，则使用 Apollo 按键表。
4. **安装文件。** 布局、主题、`settings.json`、`keys.json` 和 agent 脚本是链接。mod 是副本；见下文。
5. **恢复程序坞图标。** Herdr 更新会替换应用并去掉它的自定义图标。如果 `config/herdr/scripts/set-app-icon.sh --check` 没有发现自定义图标，安装器会重新设置 Apollo 图标。失败时输出警告并继续。

不保留任何备份：没有种子文件夹、没有归档、没有 `.bak` 文件。

## 安装路径

| 源 | 家目录目标 | 类型 |
|---|---|---|
| `config/herdr/layouts/*` | `~/.config/herdr-app/layouts/*` | `link` |
| `config/herdr/themes/*` | `~/.config/herdr-app/themes/*` | `link` |
| `config/herdr/user/settings.json` | `~/.config/herdr-app/settings.json` | `link` |
| `config/herdr/user/keys.json` | `~/.config/herdr-app/keys.json` | `link` |
| `config/herdr/mods/**` | `~/.config/herdr-app/mods/**` | `copy` |
| `config/herdr/agent/herdr-context.sh` | `~/.local/bin/herdr-agent-context` | `link` |

## 为什么 mod 是副本

Herdr 不会通过链接加载 mod 的 `svg()` 和 `image()` 文件，这样图标会是空白的。所以每个 mod 文件都是 `copy` 行。副本如何保持同步和被删除，请看 [仓库操作](Repository-Operations-zh-CN.md)。

## Agent hook

Claude Code 和 Copilot CLI 在会话开始时运行：

```sh
[ -x ~/.local/bin/herdr-agent-context ] && ~/.local/bin/herdr-agent-context claude || true
```

（Copilot 用 `copilot` 代替 `claude`。）在 Herdr 终端里，它会加入一段简短说明：这是 Herdr、终端地址，以及先运行 `herdr-app --skill` 和 `hc --skill`。在 Herdr 之外、在 Claude 桌面应用中，或者脚本不存在时，它什么也不输出。

## 设置修改

`config/herdr` 设置了 `ignore = dirty`，所以 Herdr 自己对 `settings.json` 和 `keys.json` 的写入不会阻止 `uu`。要让某个修改在所有机器上生效，请在 herdr-config 中提交，然后在这里更新固定版本。

## 更新固定版本

```sh
git -C config/herdr fetch --tags
git -C config/herdr checkout vX.Y.Z
git add config/herdr
```

把 `scripts/check.sh` 中的 `HERDR_PIN` 改成相同版本，运行 `scripts/check.sh all`，然后提交。
