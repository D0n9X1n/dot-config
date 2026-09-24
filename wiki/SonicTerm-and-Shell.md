# SonicTerm and shell

English | [简体中文](SonicTerm-and-Shell-zh-CN.md)

SonicTerm is the active outer terminal. Zsh files provide daily helpers and CLI wrappers.

## SonicTerm files

The manifest links these files:

```text
config/sonicterm/sonicterm.toml
config/sonicterm/keymaps/*.toml
```

They land under `~/.sonicterm/`. `install.sh` also verifies the pinned upstream Apollo release and links its `apollo.toml` into `~/.sonicterm/themes/`.

The whole folder is not linked. Logs, save locks, backups, and crash data stay local.

## Main terminal settings

The tracked config uses:

| Setting | Value |
|---|---|
| Theme | `apollo`, from the pinned upstream release |
| Keymap | `sonicterm-macos` |
| Font | Rec Mono St.Helens, size 13.5 |
| Font weight scale | 1 |
| Line height | 1.1 |
| New window grid | 80 × 40 |
| Top / bottom padding | 4 / 0 logical pixels |
| Scrollback | 1000 lines |
| Keypad mode | `numeric`: ordinary digits, operators, and Enter in legacy input; Kitty protocol unchanged |
| Cursor | block, no blink |
| Backdrop | opaque |
| Software render mode | auto |
| Child identity | `TERM_PROGRAM=SonicTerm` |

Use **Reload Config** from the SonicTerm command palette (`Cmd+Shift+R`) after a config change. Some native window changes may need a restart.

Top padding is 4 logical pixels; zero bottom padding removes the configured margin above the native tab bar. A partial-row gap may remain because the terminal uses whole text rows; its size depends on the window height. `panel_padding` affects popup panels, not this gap.

The active keymap is `sonicterm-macos`; `sonicterm-linux` and `sonicterm-windows` are also managed. Their custom bindings stay unchanged. Appearance uses `[appearance]`; unused legacy window and render keys are omitted.

## Terminal identity

A normal SonicTerm shell sees:

```text
TERM_PROGRAM=SonicTerm
```

A shell in RMUX sees:

```text
TERM_PROGRAM=rmux
```

Native tmux panes keep `TERM_PROGRAM=tmux`; they do not impersonate RMUX. Only a Copilot child gets the process-scoped WezTerm compatibility name. The surrounding shell keeps its real identity. See [Copilot CLI](Copilot-CLI.md) and [Tmux](Tmux.md).

RMUX advertises `xterm-256color:RGB:osc7` to its outer SonicTerm client and keeps `set-titles` enabled. Oh My Zsh emits a host-qualified OSC 7 report at each prompt, so RMUX can relay the active pane's exact working directory to SonicTerm. This lets SonicTerm resolve relative and bare file paths against the correct pane. Reload RMUX and detach/reattach after changing the outer terminal capabilities.

The RMUX config keeps its conditional mouse bindings explicit. Mouse-aware nested applications such as Copilot receive the full mouse stream; otherwise dragging starts RMUX copy mode. Shift-drag bypasses mouse reporting for a local SonicTerm selection. See [RMUX](RMUX.md).

## Zsh files

Files under `config/zsh/` install into `~/.oh-my-zsh/custom/`. Oh-my-zsh loads them in name order.

| File | Work |
|---|---|
| `custom.zsh` | eza/Base16 paths, aliases, proxy helpers, completions, SDK paths |
| `terminal-keys.zsh` | Exact terminal key sequences for ZLE prompt editing |
| `themes/apollo.zsh-theme` | Prompt structure; sources locally generated Apollo colors |
| `claude.zsh` | Claude wrapper and pinned launch flags |
| `cc.zsh` | titled Claude launch |
| `copilot.zsh` | allow-all Copilot alias, true-color wrapper, and cleanup |
| `gg.zsh` | titled, allow-all Copilot launch |
| `zz-rmux.zsh` | RMUX helpers and the shared safe-detach dispatcher; loads late |
| `zz-tmux.zsh` | Native tmux session helpers and interactive `tr` dispatch |

## Command-Backspace at the prompt

`terminal-keys.zsh` binds SonicTerm's default Cmd+Backspace sequence, `ESC [ 127 ; 9 u`, to ZLE's built-in `backward-kill-line` in the `emacs` and `viins` keymaps. It deletes from the cursor back to the beginning of the current logical line and preserves text after the cursor. It does not switch your editing mode, change Ctrl+U / Option+Backspace / Ctrl+Backspace, or alter keys delivered to Vim, less, tmux, or RMUX.

Open a new terminal tab after installation. To apply only this binding to an existing zsh prompt, run:

```zsh
source ~/.oh-my-zsh/custom/terminal-keys.zsh
```

This is a shell binding, not a SonicTerm encoder change or a fix for a multiplexer rename prompt. It covers the reported default terminal modes; DECBKM or modifyOtherKeys can produce different sequences. The regression uses a private real ZLE/PTY with mid-line, empty, Unicode and multiline buffers; it does not synthesize physical keyboard events.

## Small aliases

```text
ls      eza
ll      eza -l
c       cd ..
vim     nvim
proxy   enable the SOCKS5 proxy
unproxy disable the proxy
copilot launch Copilot with allow-all / YOLO permissions
```

The proxy address is `127.0.0.1:46971`. The helpers update shell, Git, and npm proxy settings.

`copilot` and `gg` add `--yolo` automatically, allowing tools, paths, and URLs without approval prompts. No default flags need to be appended. The `copilot` alias keeps argument forwarding and successful-update cleanup; see [Copilot CLI](Copilot-CLI.md) for permission defaults and reloading existing shells.

## Homebrew updates

`custom.zsh` exports `HOMEBREW_NO_AUTO_UPDATE=1`. Commands such as `brew install` and `brew upgrade` skip the automatic catalog update and its announcements. Run `brew update` manually before upgrading when you want the latest package versions.

Open a new shell to apply it, or run `export HOMEBREW_NO_AUTO_UPDATE=1` in an existing shell.

## Completions and paths

`.zshrc` owns prompt theme selection through `ZSH_THEME`. Managed zsh helpers do not set or override it, and the installer does not edit `.zshrc`. Apollo remains available if selected there. `custom.zsh` points eza at the pinned upstream theme.

When fast-syntax-highlighting is installed, the installer prepares its shipped Base16 theme in an isolated local work folder. Syntax colors then use SonicTerm's Apollo ANSI slots. `custom.zsh` also loads autojump, adds Homebrew completions, fixes group-writable completion folders before `compinit -i`, and adds local .NET and Android SDK paths.

## RMUX helpers

`zz-rmux.zsh` loads late so its functions win over earlier shell definitions. The `rr`, `rl`, `rd`, `rh`, and `rs` commands keep their existing behavior.

```sh
rr main       # attach if main exists; create only when absent
rl            # list sessions
rd main       # delete main
rs            # save all sessions, confirm restart, restore
rh            # helpers, parent PID 1, upgrade steps
```

It never auto-attaches a new tab. New servers started by `rr` must have parent PID 1 before attachment; the terminal owns only the attached client. Existing servers remain untouched. Upgrade with `brew upgrade rmux`, then run `rs` when ready to restart all sessions as fresh shells. The managed `rmux` shell function retains the client version compatible with the running server. See [RMUX](RMUX.md) for snapshot limits.

## Native tmux helpers

`zz-tmux.zsh` adds a separate helper family:

```sh
tt main       # exact attach; create only when absent
tr main       # interactive shortcut for tt main
tl            # list sessions without starting a server
td main       # delete the exact session
th            # help and restart warnings
ts            # save all sessions on this socket, confirm, restart, restore
```

`tr` is a shell function only in interactive zsh, not an executable or alias. It sends exactly one non-option argument to `tt`. Normal two-argument and option forms still call the text utility. Use `command tr` to request the utility explicitly.

Outside a multiplexer, native helpers use tmux's default socket. Inside native tmux, they use the current socket. `tt` refuses nested attachment from RMUX; detach first. Neither helper family auto-attaches a new tab.

For a new server, `tt`/`tr` use a detached bootstrap and verify **parent PID 1 before attachment**. Existing servers are reused without restart or forced reparenting. Quitting SonicTerm disconnects the client and leaves the server running; no `ts` is needed. Use `td` only for deliberate deletion. PID 1 does not preserve live processes through a server crash or reboot.

`ts` affects every session on the selected socket, including detached sessions. It requires a stable, valid snapshot, compatible binaries, successful preflight, and an explicit interactive `yes`. Restore opens fresh shells with saved names, directories, layouts, dimensions, and active selections. It does not replay processes or restore history. There is no autosave. Never run `ts` or `rs` automatically. Full socket and upgrade rules are in [Tmux](Tmux.md).

## Safe detach

The existing dispatcher in `zz-rmux.zsh` handles both engines. It checks `RMUX` first, because RMUX also exports `TMUX`, then checks native tmux.

Inside either engine:

- `exit` detaches;
- `logout` detaches;
- Ctrl+D at an empty prompt detaches;
- Ctrl+D with text keeps normal ZLE behavior.

Outside both engines, `exit`, `logout`, and Ctrl+D keep normal shell behavior.

## Titles

`cc [title]` and `gg [title]` send OSC 1 and OSC 2 titles to SonicTerm. They check RMUX first and rename its window directly. In native tmux, they use `tmux-store` to rename the current window on the current socket. When no title is given, they use the current path.

The native path does not change `PATH` or replace the global `tmux` command. RMUX's private teammate shim remains separate. They set `DISABLE_AUTO_TITLE` while the CLI runs so oh-my-zsh does not replace the title.

`claude` and `cc` default to native `claude-opus-5-5[1m]` with `--effort xhigh`; the relay maps that to `claude-opus-5.5`. `gg` keeps its separate Astra/`high` defaults. Open a new shell after installation or follow the reload steps in [Claude Code](Claude-Code.md).

With native tmux 3.7 and `status-keys vi`, Esc changes prompt mode; `C-g` cancels. This does not fix RMUX's separate [prompt issue #60](https://github.com/D0n9X1n/dot-config/issues/60). See the [native keymap](Tmux-Keymap.md).

## Check

```sh
zsh -n config/zsh/*.zsh
zsh -ic 'type tt tr tl td th ts rr rd rl rh rs cc gg; print -r -- "$ZSH_THEME $EZA_CONFIG_DIR $FAST_WORK_DIR"'
grep -F 'theme = "apollo"' ~/.sonicterm/sonicterm.toml
ls -l ~/.sonicterm/themes/apollo.toml ~/.config/eza-apollo-theme/theme.yml
scripts/check.sh rmux
scripts/check.sh tmux
```

See [Tmux](Tmux.md) and [RMUX](RMUX.md) for the session models.
