# RMUX

English | [简体中文](RMUX-zh-CN.md)

This repository uses RMUX 0.10.x as its terminal multiplexer. The tracked source is `config/rmux/rmux.conf`; `install.sh` links it to `~/.rmux.conf` and installs the Homebrew `rmux` formula on new Macs.

## What RMUX is

RMUX is an independent Rust multiplexer with a client/daemon architecture. The daemon owns shells, PTYs, sessions, windows, panes, scrollback, options, and process lifetime. A client attaches over local IPC and can detach without terminating those processes.

```mermaid
flowchart LR
    T[Outer terminal: SonicTerm] --> C[rmux client]
    C <--> D[rmux-daemon over local IPC]
    D --> S[Sessions]
    S --> W[Windows]
    W --> P[Panes and PTYs]
```

RMUX is not:

- a terminal emulator — an outer terminal still renders text, fonts, tabs, and native windows;
- a wrapper around a running tmux server — it has its own daemon and socket namespace;
- a byte-for-byte tmux clone — it implements a broad tmux command/config contract with documented differences.

One daemon normally serves each socket. `-L name` selects an isolated named socket, and `-S path` selects an explicit socket path. The default lifecycle keeps sessions alive when clients detach, but it is not disk persistence across daemon termination or reboot.

## Configuration discovery

On macOS and Linux, RMUX 0.10.0 checks these native locations:

```text
/etc/rmux.conf
~/.rmux.conf
$XDG_CONFIG_HOME/rmux/rmux.conf
~/.config/rmux/rmux.conf
```

If no native file loads, RMUX can fall back to standard tmux config locations. That fallback is intentionally avoided here: the archived tmux config contains executable TPM bootstrap commands. A native `~/.rmux.conf` makes startup deterministic. For diagnostics, `RMUX_DISABLE_TMUX_FALLBACK=1` also disables fallback.

RMUX config is tmux command syntax, not JSON, YAML, or TOML. It can execute `run-shell`, conditionals, and sourced files, so treat it as executable code.

## Repository profile

The profile is adapted from RMUX's v0.10.0 human-friendly example and selected compatible behavior from the retired tmux config.

| Setting | Repository value |
|---|---|
| Prefix | `C-q`; `prefix + C-q` sends a literal `C-q` |
| Reload | `prefix + r` |
| Mouse | On; `prefix + T` toggles native terminal selection |
| History | 100000 lines |
| Window/pane indices | Start at 1; windows renumber after close |
| Copy mode | Vi keys; `pbcopy` plus OSC 52 |
| Status | Top, hand-built Gruvbox Dark Hard |
| Titles | Automatic rename off; `#S · #W` propagated outward |
| Terminal identity | `TERM=tmux-256color`; `TERM_PROGRAM=rmux` is preserved |

The config clears stale `TERMINFO`, `TERMINFO_DIRS`, and `TERMCAP` inherited by a long-lived daemon, then sets `COLORTERM=truecolor` and `FORCE_COLOR=3`. It does not clear RMUX's own `TERM_PROGRAM` identity.

## Session helpers and resume

New SonicTerm tabs open normal shells. The late-loading `zz-rmux.zsh` file provides explicit helpers:

```sh
rr main       # create or resume main
rl            # list all sessions
rd main       # delete main
```

`rr <name>` checks whether the session exists, runs `attach-session` when it does, and runs `new-session` only when it is absent. It prints which path it chose. `rd <name>` runs `kill-session`, so it permanently ends that session. SonicTerm advertises its real `TERM_PROGRAM=SonicTerm`; only Copilot child processes receive the WezTerm compatibility identity.

Inside RMUX, the zsh helpers turn `exit`, `logout`, and Ctrl+D at an empty prompt into `detach-client`. Ctrl+D with text in the edit buffer keeps its normal delete/list behavior. `prefix + d` and closing the SonicTerm tab also disconnect the client while leaving panes running. Run `rr main` later to reconnect.

Use `rd <name>` for intentional session deletion. Persistence is still in memory only: `rd`, `kill-server`, daemon loss, or reboot destroys the session; there is no resurrect-style disk restore.

### Keybindings

The [complete RMUX keymap](RMUX-Keymap.md) lists all 278 effective bindings across the prefix, active Vi copy-mode, retained Emacs copy-mode, and root mouse tables.

| Action | Binding |
|---|---|
| Reload config | `prefix + r` |
| Toggle mouse/native selection | `prefix + T` |
| New window in current directory | `prefix + c` |
| Split right in current directory | `prefix + \|` |
| Split down in current directory | `prefix + -` |
| Focus pane | `prefix + h/j/k/l` |
| Resize pane, repeatable | `prefix + H/J/K/L` |
| Last window | `prefix + Tab` |
| Copy mode | `prefix + v` |
| Start/select line/rectangle | `v` / `V` / `C-v` in copy mode |
| Copy and exit | `y` or `C-c` in copy mode |
| Zoom pane | `prefix + z` (RMUX default) |
| Detach | `prefix + d` (RMUX default) |

The `|`, `-`, and `c` commands use `#{pane_current_path}`, so new panes and windows inherit the active working directory.

## SonicTerm mouse integration

SonicTerm's Copilot guide requires RMUX's conditional root mouse bindings. The tracked config pins them instead of relying on RMUX defaults:

```tmux
set -g mouse on
bind -n MouseDown1Pane { select-pane -t=; send -M }
bind -n MouseDrag1Pane { if -F '#{||:#{pane_in_mode},#{mouse_any_flag}}' { send -M } { copy-mode -M } }
bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-no-clear
set -s set-clipboard on
```

`MouseDown1Pane` selects the pane and forwards the press. `MouseDrag1Pane` forwards input when RMUX is already in a pane mode or the nested application requested mouse input; otherwise RMUX starts copy mode. Releasing the mouse copies RMUX-owned selections without clearing the highlight or leaving copy mode; press `q` to leave copy mode. This lets Copilot own transcript selection and edge scrolling. Do not force every drag into RMUX copy mode. Shift-drag remains the SonicTerm-local selection fallback.

## Clipboard trust

The profile uses both `copy-command 'pbcopy'` and `set-clipboard on`:

- copy-mode sends selected UTF-8 text to the macOS clipboard through `pbcopy`;
- OSC 52 allows trusted programs inside a pane, including nested SSH applications, to update the outer terminal clipboard.

`set-clipboard on` is a deliberate trust choice: pane output can replace the host clipboard. Use RMUX's safer `external` mode instead if panes may run untrusted programs.

## Claude Code teammate mode

Use normal `claude` or the repository's `cc` helper for an ordinary Claude Code session. Use RMUX explicitly when Claude Code should launch agent-team panes:

```sh
rmux claude --permission-mode bypassPermissions \
  --model 'claude-sonnet-5[1m]' --effort max
```

`rmux claude` enables Claude Code's tmux teammate mode and prepends a private, process-scoped `tmux` shim so Claude's teammate commands target RMUX. It does not replace the global `tmux` executable. This repository deliberately does not run `rmux setup tmux-shim`.

Inside RMUX panes, the daemon exports both RMUX-native and tmux-compatible environment names (`RMUX`, `RMUX_PANE`, `TMUX`, and `TMUX_PANE`). The `cc` and `gg` helpers use `rmux rename-window` when `RMUX` is present; they do not call legacy tmux or the WezTerm CLI.

Copilot CLI does not yet recognize every RMUX/SonicTerm identity. The repository's `copilot` wrapper and `gg` therefore launch only the Copilot process with `TERM_PROGRAM=WezTerm`, `COLORTERM=truecolor`, and `FORCE_COLOR=3`. This selects Copilot's supported WezTerm/true-color path while the surrounding RMUX pane and all other programs continue to see `TERM_PROGRAM=rmux`.

## Automation surface

In addition to tmux-style commands, RMUX exposes automation helpers such as:

- `pane-snapshot`, `capture-pane`, `stream-pane`, and `collect-pane-output`;
- `wait-pane`, `expect-pane`, and `locator`;
- `find-panes`, `find-sessions`, `broadcast-keys`, and `with-session`;
- optional encrypted `web-share` for a selected pane or session.

Use a named socket for tests and automation so they cannot alter the interactive default server.

## Migration boundaries

The previous tmux source is preserved under `archive/tmux/`, but it is inactive. TPM, tmux-sensible, tmux-yank, resurrect, and continuum were not ported because RMUX's compatibility contract does not guarantee plugin behavior. Existing `~/.tmux/plugins/` and resurrect snapshots are preserved for rollback.

The previous WezTerm Lua config is preserved under `archive/wezterm/`. The repository no longer installs WezTerm or links `~/.wezterm.lua`; SonicTerm is the actively managed outer terminal RMUX uses.

See [Archived tmux configuration](Archive-Tmux.md) and [Archived WezTerm configuration](Archive-WezTerm.md).

## Verification

```sh
rmux -V
rmux diagnose --human
rmux capabilities --human
rmux doctor tmux-dropin
ls -l ~/.rmux.conf
```

A repository config check uses an isolated socket and always kills it afterward:

```sh
socket="rmux-check-$$"
trap 'rmux -L "$socket" kill-server >/dev/null 2>&1 || true' EXIT
rmux -L "$socket" -f /dev/null new-session -d -s validate
rmux -L "$socket" source-file -n -v config/rmux/rmux.conf
rmux -L "$socket" source-file config/rmux/rmux.conf
```

RMUX 0.10.0's parse-only pass reports the event-time `{mouse}` target as deferred and exits with status 1. `scripts/check.sh rmux` accepts only that exact diagnostic, then live-loads the config and verifies the effective bindings. Any other parse diagnostic fails the check.

Within an attached session, verify `C-q`, splits, CWD inheritance, copy mode, mouse toggle, truecolor, undercurl, titles, and the Gruvbox status line.

## Troubleshooting

- Unexpected TPM/plugin execution means no native RMUX config loaded. Check `~/.rmux.conf` and use `RMUX_DISABLE_TMUX_FALLBACK=1` while diagnosing.
- Use `rmux -L name kill-server` only for the intended named socket; `kill-server` terminates all sessions on that socket.
- After an RMUX upgrade with an incompatible wire version, stop old daemons before using the new binary.
- The local IPC model trusts other processes running as the same user. Do not widen socket access without reviewing `server-access` behavior.
- Web Share is opt-in network exposure. Use a PIN, a bounded TTL, the least-powerful viewer role, and a trusted frontend/tunnel.

## Authoritative sources

- [SonicTerm usage](https://github.com/D0n9X1n/SonicTerm/blob/main/wiki/Usage.md)
- [RMUX v0.10.0 README](https://github.com/Helvesec/rmux/blob/v0.10.0/README.md)
- [Human-friendly configuration](https://github.com/Helvesec/rmux/blob/v0.10.0/docs/human-friendly-config.md)
- [Starter configuration](https://github.com/Helvesec/rmux/blob/v0.10.0/docs/examples/human-friendly.conf)
- [Claude Code integration](https://github.com/Helvesec/rmux/blob/v0.10.0/docs/integrations/claude-code.md)
- [tmux compatibility decisions](https://github.com/Helvesec/rmux/blob/v0.10.0/docs/tmux-compat-decisions.md)
- [Security policy](https://github.com/Helvesec/rmux/blob/v0.10.0/SECURITY.md)
