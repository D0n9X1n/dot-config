# Archived tmux configuration

English | [简体中文](Archive-Tmux-zh-CN.md)

The former `.tmux.conf` is preserved at `archive/tmux/.tmux.conf` for reference and rollback. It is no longer linked to `~/.tmux.conf`, and `install.sh` no longer installs tmux or bootstraps TPM.

## What moved to RMUX

The active `.rmux.conf` retains the `C-q` prefix, Gruvbox top status bar, one-based indices, current-directory splits and windows, vim pane navigation and resizing, vi copy mode, truecolor handling, persistent titles, and explicit `prefix + Tab` behavior.

## What did not move

The following plugin stack remains historical:

- TPM
- tmux-sensible
- tmux-yank
- tmux-resurrect
- tmux-continuum

RMUX implements many tmux commands and config forms, but it does not guarantee arbitrary TPM plugin compatibility. Loading the archived file through RMUX can execute `run-shell`, clone TPM, and invoke restore scripts; do not use it as an RMUX config.

## Preserved local state

The migration deliberately leaves an already-installed tmux binary, `~/.tmux/plugins/`, and `~/.local/share/tmux/resurrect/` untouched. These are local rollback data, not active repository configuration.

To restore tmux management, move the archived file back to the repository root as `.tmux.conf`, restore the installer formula/TPM blocks, and run `install.sh`. Review current RMUX sessions before changing multiplexer ownership.

See [RMUX](RMUX.md) and [Archived WezTerm configuration](Archive-WezTerm.md).
