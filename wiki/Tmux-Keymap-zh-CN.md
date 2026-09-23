# Tmux 按键表

[English](Tmux-Keymap.md) | 简体中文

这里列出原生 tmux 3.7c 的受管按键。安装、服务器生命周期和恢复见 [Tmux](Tmux-zh-CN.md)。RMUX 保持独立；其[按键表](RMUX-Keymap-zh-CN.md)不是原生 tmux 默认按键列表。

## 会话

| 命令 | 操作 |
|---|---|
| `tt NAME` 或 `tr NAME` | 精确连接会话；不存在时先分离创建，再连接 |
| `tl` | 列出会话，不启动服务器 |
| `td NAME` | 永久结束该会话及其中程序 |
| `th` | 助手帮助 |
| `ts` | 确认、保存、重启所选服务器，并用新 shell 恢复工作区 |

`tr NAME` 只在交互式 shell 中作为快捷命令。Unix 文本工具可用 `command tr`；普通双参数及带选项的调用保持可用。shell 启动时不会自动执行任何会话助手。

## Prefix 按键

先按 **Ctrl+Q**，松开后再按下一个键。`C-` 表示 Ctrl，大写字母需要 Shift。

| Prefix 后的键 | 操作 |
|---|---|
| `C-q` | 向窗格发送字面 Ctrl+Q |
| `r` | 重载 `~/.tmux.conf` |
| `n` 或 `,` | 重命名窗口，保留运行中应用图标 |
| `T` | 切换 tmux 鼠标处理与外层终端选择 |
| `c` | 在活动窗格目录新建窗口 |
| `\|` | 在活动窗格目录向右分割 |
| `-` | 在活动窗格目录向下分割 |
| `h`、`j`、`k`、`l` | 焦点向左、下、上、右移动 |
| `H`、`J`、`K`、`L` | 左右调整 5 格，上下调整 3 格 |
| `Left`、`Right` | 上一个 / 下一个窗口，可连续按 |
| `Tab` | 返回上一个窗口 |
| `v` | 进入 Vi 复制模式 |
| `z` | 缩放 / 取消缩放窗格（原生默认） |
| `d` | 分离客户端，窗格程序继续运行（原生默认） |

在 tmux 中，`exit`、`logout` 和空 shell 提示符的 Ctrl+D 也只分离。输入中有文字时，Ctrl+D 保持正常删除/列表行为。退出 SonicTerm 前不需要 `ts`。

## 重命名提示框

| 输入 | 操作 |
|---|---|
| 普通或带 Shift 的字母 | 插入文字 |
| `Ctrl+W` | 删除前一个词 |
| `Ctrl+U` | 在 Vi 插入模式清空输入 |
| `Enter` | 提交 |
| 清空后按 `Enter` | 恢复基于当前应用的窗口名称 |
| 插入模式中的 `Ctrl+G` | 取消 |
| `Escape` | 进入 Vi 命令模式；单独按此键不会取消 |
| 命令模式中的 `q` 或 `Ctrl+C` | 取消 |

受管提示框保留字面引号、反斜杠、井号及类似格式表达式的文字。这与会进行原生格式展开的 `tmux rename-window` 不同。

## 不带 Prefix 的窗格输入

Shift+Enter 为未请求扩展协议的应用发送换行；请求协议的应用保留扩展按键。普通 Enter 不重映射。Ctrl+Q 在传统、modifyOtherKeys 和 CSI-u 编码中都保持为 prefix。

## Vi 复制模式

| 按键 | 操作 |
|---|---|
| `v` | 开始选择 |
| `V` | 选择整行 |
| `Ctrl+V` | 切换矩形选择 |
| `y` 或 `Ctrl+C` | 通过 `pbcopy` 复制并退出复制模式 |
| `q` | 退出复制模式（原生默认） |
| 释放鼠标拖动 | 复制但保留选择和复制模式 |

`mode-keys vi` 选择此表。原生 Emacs 复制模式表仍存在，但当前未选用。

## 鼠标归属

- 点击状态栏标签选择对应窗口。
- 点击窗格聚焦并转发事件。
- 应用请求鼠标输入或窗格已进入某种模式时，拖动交给它处理；否则进入 tmux 复制模式。
- Shift-drag 可使用 SonicTerm 的原生选择。
- `prefix + T` 切换 tmux 鼠标处理。

## 查看完整原生按键表

在目标原生 tmux 服务器中执行：

```sh
tmux list-keys -T prefix
tmux list-keys -T copy-mode-vi
tmux list-keys -T copy-mode
tmux list-keys -T root
```

这些命令显示当前安装版本的默认按键与受管覆盖。原生 tmux 的按键数量不必与 RMUX 相同。
