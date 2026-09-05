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
| Font | Rec Mono St.Helens, size 14 |
| Line height | 1.2 |
| New window grid | 100 × 30 |
| Scrollback | 1000 lines |
| Cursor | block, no blink |
| Backdrop | opaque |
| Software render mode | auto |
| Child identity | `TERM_PROGRAM=SonicTerm` |

Use **Reload Config** from the SonicTerm command palette after a config change. Some native window changes may need a restart.

The active keymap is `sonicterm-macos`; `sonicterm-linux` and `sonicterm-windows` are also managed. Their custom bindings stay unchanged. Appearance uses `[appearance]`; unused legacy window and render keys are omitted.

## RMUX identity

A normal SonicTerm shell sees:

```text
TERM_PROGRAM=SonicTerm
```

A shell in RMUX sees:

```text
TERM_PROGRAM=rmux
```

Only a Copilot child gets the process-scoped WezTerm compatibility name. See [Copilot CLI](Copilot-CLI.md).

RMUX advertises `xterm-256color:RGB:osc7` to its outer SonicTerm client and keeps `set-titles` enabled. Oh My Zsh emits a host-qualified OSC 7 report at each prompt, so RMUX can relay the active pane's exact working directory to SonicTerm. This lets SonicTerm resolve relative and bare file paths against the correct pane. Reload RMUX and detach/reattach after changing the outer terminal capabilities.

The RMUX config keeps its conditional mouse bindings explicit. Mouse-aware nested applications such as Copilot receive the full mouse stream; otherwise dragging starts RMUX copy mode. Shift-drag bypasses mouse reporting for a local SonicTerm selection. See [RMUX](RMUX.md).

## Zsh files

Files under `config/zsh/` install into `~/.oh-my-zsh/custom/`. Oh-my-zsh loads them in name order.

| File | Work |
|---|---|
| `custom.zsh` | Apollo prompt selection, eza/Base16 paths, aliases, proxy helpers, completions, SDK paths |
| `themes/apollo.zsh-theme` | Prompt structure; sources locally generated Apollo colors |
| `claude.zsh` | Claude wrapper and pinned launch flags |
| `cc.zsh` | titled Claude launch |
| `copilot.zsh` | Copilot true-color wrapper and cleanup |
| `gg.zsh` | titled Copilot launch |
| `zz-rmux.zsh` | RMUX session and safe-detach helpers; loads late |

## Small aliases

```text
ls      eza
ll      eza -l
c       cd ..
vim     nvim
proxy   enable the SOCKS5 proxy
unproxy disable the proxy
```

The proxy address is `127.0.0.1:46971`. The helpers update shell, Git, and npm proxy settings.

## Completions and paths

`custom.zsh` selects the managed Apollo prompt before Oh My Zsh loads its theme. It does not edit `.zshrc`. It also points eza at the pinned upstream theme.

When fast-syntax-highlighting is installed, the installer prepares its shipped Base16 theme in an isolated local work folder. Syntax colors then use SonicTerm's Apollo ANSI slots. `custom.zsh` also loads autojump, adds Homebrew completions, fixes group-writable completion folders before `compinit -i`, and adds local .NET and Android SDK paths.

## RMUX helpers

`zz-rmux.zsh` loads late so its functions win over earlier shell definitions.

```sh
rr main       # attach if main exists; create only when absent
rl            # list sessions
rd main       # delete main
```

It never auto-attaches a new tab.

Inside RMUX:

- `exit` detaches;
- `logout` detaches;
- Ctrl+D at an empty prompt detaches;
- Ctrl+D with text keeps normal ZLE behavior.

Outside RMUX, `exit`, `logout`, and Ctrl+D keep normal shell behavior.

## Titles

`cc [title]` and `gg [title]` send OSC 1 and OSC 2 titles to SonicTerm. In RMUX, they also rename the RMUX window. When no title is given, they use the current path.

They set `DISABLE_AUTO_TITLE` while the CLI runs so oh-my-zsh does not replace the title.

## Check

```sh
zsh -n config/zsh/*.zsh
zsh -ic 'type rr rd rl cc gg; print -r -- "$ZSH_THEME $EZA_CONFIG_DIR $FAST_WORK_DIR"'
grep -F 'theme = "apollo"' ~/.sonicterm/sonicterm.toml
ls -l ~/.sonicterm/themes/apollo.toml ~/.config/eza-apollo-theme/theme.yml
scripts/check.sh rmux
```

See [RMUX](RMUX.md) for the session model.
