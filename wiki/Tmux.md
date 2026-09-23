# Native tmux

English | [简体中文](Tmux-zh-CN.md)

Native tmux runs alongside [RMUX](RMUX.md). It uses the same Apollo colors and bottom-tab style, but has its own server, sessions, and recovery state. The managed profile targets tmux 3.7c. `install.sh` installs Homebrew tmux and links `config/tmux/tmux.conf` to `~/.tmux.conf`.

## Start and reconnect

Open a new shell after installation:

```sh
tt main       # create or resume exactly main
tr main       # same as tt main
tl            # list sessions without starting a server
td main       # permanently end main and its programs
th            # helper help and recovery limits
ts            # confirm, save, restart, and restore this server's workspace
```

The RMUX helpers `rr`, `rl`, `rd`, `rh`, and `rs` stay available. New SonicTerm tabs still open a normal shell; neither engine auto-attaches.

`tr NAME` is an interactive shortcut. Normal two-operand or option forms still use the system text utility. Use `command tr` or `/usr/bin/tr` to select that utility explicitly.

The helpers call the real Homebrew tmux binary, not a `tmux` shim from `PATH`. Outside tmux they use its default socket. Inside native tmux they use the current socket, and `tt` switches the attached client instead of nesting another one. Detach from RMUX before running `tt` or `tr`; its `TMUX` compatibility variable is not a native tmux connection.

## Server lifetime

For a new server, `tt` and `tr` create the session detached and verify that the server's **parent PID is 1 before attaching**. SonicTerm owns the attached client, not the server. Existing servers are reused without restart or forced reparenting.

Inside native tmux, `exit`, `logout`, empty-prompt Ctrl+D, and `prefix + d` detach. Ctrl+D with text in the shell edit buffer keeps its normal behavior. Closing the SonicTerm tab or quitting SonicTerm disconnects the client while the server and pane programs remain running. Reconnect with `tt NAME`; do not run `ts` just to quit the terminal.

Use `td NAME` only when you intend to stop a session. PID 1 parentage does not protect against a server crash, system shutdown, explicit kill, or the last pane exiting.

## Appearance and controls

The profile keeps RMUX's user-visible design:

- C-q prefix, one bottom status row, mouse support, and Vi copy mode.
- Apollo status, border, message, and copy-mode colors from the pinned official tmux theme.
- The same sloped session/window labels, spacing, numbered app icons, dark-blue active tab with bold white text, and inactive tabs on the bar background.
- One space between each app icon and title. Icons follow Claude, Copilot, Vim/Neovim, or the fallback terminal command, not a custom title.
- `PREFIX`, `ZOOM`, activity and bell states, plus a plain `HH:MM` clock.
- Splits and new windows inherit the current pane's directory.

See the [tmux keymap](Tmux-Keymap.md). `cc` and `gg` rename the current native tmux window through the native helper. Their RMUX behavior and launcher defaults remain separate.

The installer links the verified theme to `~/.config/tmux-apollo-theme/apollo.tmux`. It does not install TPM, run old plugin bootstraps, or load archived tmux configuration. Existing plugin and resurrect directories are left alone.

## Rename and prompt input

Use `prefix + n` or `prefix + ,`. The rename prompt starts in Vi insert mode. Ctrl+W deletes the previous word and Ctrl+U clears the entry. Ctrl+G cancels in insert mode. Escape enters Vi command mode; use `q` or Ctrl+C there to cancel.

The managed prompt keeps quotes, backslashes, `#{...}`, `#(...)`, and semicolons as title text rather than commands. It preserves the window selected when the prompt opened. An empty submitted name restores automatic app-based naming for that window; a later custom rename disables it again. The running-app icon remains visible.

Native tmux stores escaped backslashes in its window-name field. The managed title display and prompt show one literal copy. Prefer the managed rename prompt when exact literal text matters; raw `tmux rename-window` has tmux's own format-expansion semantics.

This native profile does not fix [RMUX's separate prompt bug](https://github.com/D0n9X1n/dot-config/issues/60).

## Terminal input and integration

Panes retain native `TERM=tmux-256color` and `TERM_PROGRAM=tmux`. The profile removes stale terminfo overrides and sets truecolor variables. It does not impersonate SonicTerm or WezTerm; only Copilot child processes retain the documented WezTerm compatibility override.

Extended-key negotiation keeps Shift+Enter distinct from Enter. Requesting pane apps receive extended Shift+Enter; the native profile sends Ctrl+J to nonrequesting apps. Ordinary Enter remains unchanged. After changing outer keyboard capabilities, reload and detach/reconnect the client to renegotiate.

OSC 7 directory reports, titles, conditional mouse forwarding, `pbcopy`, and OSC 52 match the RMUX profile. Clipboard access trusts pane programs: `set-clipboard on` lets them update the host clipboard. Use `external` instead if your pane applications are untrusted.

RMUX's private teammate shim stays process-scoped. Installing native tmux does not replace it. Actual model-backed teammate launches are not part of the offline configuration tests.

## Upgrade and recovery

```sh
brew upgrade tmux
ts
```

`ts` is optional and destructive: it stops **all programs on the selected tmux socket** after an explicit confirmation. It saves all that server's sessions, including detached ones. It never restarts other sockets or RMUX.

The helper validates a stable workspace and server generation before stopping anything. A worker independent of the invoking pane restores session/window names, indices, dimensions, pane layouts, directories, and active selections as fresh shells. It does not restore programs, memory, scrollback, unsaved buffers, or the environment, and does not replay captured commands.

Unsupported grouped/linked, dead/zoomed, or unstable layouts are refused before stopping. Missing directories warn and fall back to HOME. Failed recovery keeps the original snapshot; retries do not automatically kill a partially restored server.

Private state is stored under `~/.local/state/tmux-store/`, separately for each socket. Do not commit it. There is no periodic save, LaunchAgent, or automatic reboot restore.

Unlike RMUX's retained executable pair, native tmux uses a compatible installed Homebrew executable and its libraries. Missing or incompatible clients/dependencies fail safely. This does not guarantee reconnecting after arbitrary Homebrew dependency cleanup; no copied binary, dylib relocation, or global library-path override is installed.

## Apply and verify

```sh
scripts/check.sh all
./install.sh
./install.sh
ls -l ~/.tmux.conf ~/.config/tmux-apollo-theme/apollo.tmux
th
```

New servers load the installed profile. Installation does not reload or restart existing tmux servers. When you choose to update an existing server, use `prefix + r`, then detach/reconnect for changed terminal capabilities.

Tests use private sockets and temporary homes. Do not run `kill-server` against your normal socket during testing. Byte-level PTY tests verify native prompt editing and forwarding; they are not a claim of physical macOS key-event capture or pixel-perfect rendering in every terminal/font.
