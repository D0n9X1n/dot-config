# Tmux keymap

English | [简体中文](Tmux-Keymap-zh-CN.md)

These are the managed bindings for native tmux 3.7c. See [Tmux](Tmux.md) for setup, server lifetime, and recovery. RMUX remains separate; its [keymap](RMUX-Keymap.md) is not a list of native tmux defaults.

## Sessions

| Command | Action |
|---|---|
| `tt NAME` or `tr NAME` | Attach to the exact session, or create it detached before attaching |
| `tl` | List sessions without starting a server |
| `td NAME` | Permanently stop that session and its programs |
| `th` | Helper help |
| `ts` | Confirm, save, restart, and restore the selected server's workspace as fresh shells |

`tr NAME` is interactive. Use `command tr` for the Unix text utility; ordinary two-operand and option forms keep working. No helper runs on shell startup.

## Prefix keys

Press **Ctrl+Q**, release it, then press the next key. `C-` means Ctrl; uppercase letters require Shift.

| Key after prefix | Action |
|---|---|
| `C-q` | Send literal Ctrl+Q to the pane |
| `r` | Reload `~/.tmux.conf` |
| `n` or `,` | Rename the window, keeping its running-app icon |
| `T` | Toggle tmux mouse handling / outer-terminal selection |
| `c` | New window in the active pane's directory |
| `\|` | Split right in the active pane's directory |
| `-` | Split down in the active pane's directory |
| `h`, `j`, `k`, `l` | Focus left, down, up, right |
| `H`, `J`, `K`, `L` | Resize left/right by 5 cells or up/down by 3 |
| `Left`, `Right` | Previous / next window; repeatable |
| `Tab` | Last window |
| `v` | Enter Vi copy mode |
| `z` | Zoom / unzoom pane (native default) |
| `d` | Detach client, leaving pane programs running (native default) |

Inside tmux, `exit`, `logout`, and Ctrl+D on an empty shell prompt also detach. Ctrl+D with input text keeps its normal delete/list behavior. Quitting SonicTerm does not require `ts`.

## Rename prompt

| Input | Action |
|---|---|
| Ordinary or shifted letters | Insert text |
| `Ctrl+W` | Delete the preceding word |
| `Ctrl+U` | Clear the entry in Vi insert mode |
| `Enter` | Submit |
| Empty entry then `Enter` | Restore the current app-based window name |
| `Ctrl+G` in insert mode | Cancel |
| `Escape` | Enter Vi command mode; this alone is not cancellation |
| `q` or `Ctrl+C` in command mode | Cancel |

The managed prompt preserves literal quotes, backslashes, hashes, and format-like text. This differs from raw `tmux rename-window`, which uses native format expansion.

## Pane input without a prefix

Shift+Enter sends a newline to nonrequesting apps and preserves extended input for apps requesting it. Plain Enter is not remapped. Ctrl+Q remains the prefix in legacy, modifyOtherKeys, and CSI-u encodings.

## Vi copy mode

| Key | Action |
|---|---|
| `v` | Begin selection |
| `V` | Select line |
| `Ctrl+V` | Toggle rectangle selection |
| `y` or `Ctrl+C` | Copy through `pbcopy` and leave copy mode |
| `q` | Leave copy mode (native default) |
| Mouse drag release | Copy without clearing the selection or leaving copy mode |

`mode-keys vi` selects this table. The separate native Emacs copy table remains available but is not selected.

## Mouse ownership

- Click a status tab to select that window.
- Click a pane to focus it and forward the event.
- Dragging goes to an application that requested mouse input, or to an active pane mode; otherwise it starts tmux copy mode.
- Shift-drag can use SonicTerm's native selection.
- `prefix + T` toggles tmux mouse handling.

## Inspect the full native tables

Within the intended native tmux server:

```sh
tmux list-keys -T prefix
tmux list-keys -T copy-mode-vi
tmux list-keys -T copy-mode
tmux list-keys -T root
```

These commands list the installed version's defaults plus the managed overrides. Native tmux's binding count need not equal RMUX's.
