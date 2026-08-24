# Archived WezTerm configuration

English | [简体中文](Archive-WezTerm-zh-CN.md)

The former managed Lua profile is preserved at `archive/wezterm/wezterm.lua`. `install.sh` no longer links it to `~/.wezterm.lua`.

## Why the old name still appears

RMUX is a terminal multiplexer, not a terminal emulator. SonicTerm is the actively managed outer terminal under `.sonicterm/`; the installer no longer installs WezTerm or manages its Lua config.

SonicTerm's WezTerm-compatible keymap names, palette provenance, and terminal identity remain intentional compatibility signals. Copilot also receives a process-scoped `TERM_PROGRAM=WezTerm` plus true-color variables because it recognizes that capability path; this does not mean WezTerm is installed or active.

## Local migration behavior

`install.sh` removes `~/.wezterm.lua` only when it is still the exact symlink formerly created by this repository. A regular file or a symlink to another target is preserved.

To restore the old profile, move `archive/wezterm/wezterm.lua` back to `wezterm/wezterm.lua`, restore the installer link block, and run `install.sh`.

See [RMUX](RMUX.md) and [Archived tmux configuration](Archive-Tmux.md).
