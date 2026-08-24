# Archived configurations

These files are retained for reference and rollback only. `install.sh` never links content from `archive/`.

- `tmux/.tmux.conf` is the former active tmux profile. RMUX now owns the multiplexer layer through the repository-root `.rmux.conf`. The installer no longer installs tmux or bootstraps TPM, but it deliberately preserves an existing tmux binary, `~/.tmux/plugins/`, and resurrect snapshots.
- `wezterm/wezterm.lua` is the former managed WezTerm profile. The installer no longer installs WezTerm or links `~/.wezterm.lua`; SonicTerm is the actively managed outer terminal. Copilot still receives a process-scoped `TERM_PROGRAM=WezTerm` compatibility identity because that is a UI capability signal, not active WezTerm ownership.

To restore either profile, move it back to its former tracked path and restore the matching installer behavior. Do not symlink directly into `archive/`, because archived files are intentionally outside active configuration ownership.
