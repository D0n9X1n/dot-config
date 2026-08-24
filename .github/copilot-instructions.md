# Copilot Instructions

Read `QUICKREF.md` at the repo root first — it is the single source of truth
for how this repository works. Keep it up to date when making changes.

`ReadMe.md` is the human-facing README; update it separately when user-visible
details change.

## Architecture

This is a dotfiles repository using a symlink-based linker pattern. `install.sh`
symlinks every **top-level non-ignored dotfile** (files starting with `.`) into
`$HOME`. Directories, nested files, and gitignored generated files are never
linked, with one explicit exception: `.sonicterm/` is tracked as an app config
directory, and `install.sh` links only its TOML config/keymap/theme files into
`~/.sonicterm/` so logs and runtime backups stay machine-local.
`.copilot-relay/config.yaml` is another explicit app-config file; only that
secret-free file is linked into `~/.copilot-relay/`, while relay tokens and logs
remain local and must not be committed.

Adding a new config means dropping a dotfile at the repo root — `install.sh`
picks it up automatically with no manifest to update. Top-level files under
`claude/` and `copilot/` are also auto-linked. `claude/CLAUDE.md` and
`copilot/AGENTS.md` carry coupled global Wiki/release guidance; the latter is
activated by `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` in `custom.zsh` while
`copilot-instructions.md` remains Copilot's native global entry point.
`.rmux.conf` is the active multiplexer profile. `archive/` is inert and never
linked. For SonicTerm, add TOML under `.sonicterm/`, `.sonicterm/keymaps/`, or
`.sonicterm/themes/`.

The install script also handles brand-new macOS bootstrap: installs Homebrew if
missing, installs Homebrew formulae/casks (including Claude Code via
`claude-code`), installs npm globals for Copilot CLI + `copilot-relay`, installs
oh-my-zsh, downloads custom RecMono fonts from `MOSconfig/recursive-code-config`,
and then links configs. On non-macOS systems it skips installation and only
links.

## Conventions

- **Shell scripts** use `set -euo pipefail` strict mode and POSIX-compatible
  patterns where possible.
- **Claude Code's native concurrent-subagent limit is set to 16.** Keep
  `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS="16"` in `claude/settings.json` and
  require Claude Code v2.1.217+. Do not describe it as an absolute ceiling:
  `/subtask` and resumed agents can pass the admission boundary, ultracode is
  exempt, and workflows/agent teams use separate limits. Do not restore the
  obsolete lifecycle counter hook.
- **RMUX config** (`.rmux.conf`) uses tmux command syntax but must be tested
  against RMUX itself. Preserve `TERM_PROGRAM=rmux`, use a unique `-L` socket
  for checks, and do not add TPM/plugin bootstrap or a global tmux shim.
- **Archives are inert.** `archive/tmux/.tmux.conf` and
  `archive/wezterm/wezterm.lua` are historical references, never active config.
  SonicTerm is the managed outer terminal; this repository installs neither
  tmux nor WezTerm.
- **Wiki pages are bilingual and flat.** Pair every English page with a
  `-zh-CN` page, keep one `_Sidebar.md`, use source `.md` links, and run
  `scripts/check.sh wiki`. Browser edits are overwritten on publication.
- Color scheme is **Gruvbox Dark Hard** throughout active RMUX, SonicTerm, and
  statusline configuration.
- Copilot launchers set process-scoped `TERM_PROGRAM=WezTerm`,
  `COLORTERM=truecolor`, and `FORCE_COLOR=3` so Copilot takes its supported
  true-color UI path. Do not set this globally: other RMUX pane programs should
  continue to see `TERM_PROGRAM=rmux`.

## How to test changes

- **All local/CI checks**: Run `scripts/check.sh all`.
- **RMUX config and retirement migration**: Run `scripts/check.sh rmux`; it
  uses an isolated socket and tests exact legacy-link removal.
- **Global instruction discovery/content**: Run `scripts/check.sh instructions`.
- **Wiki source/publication graph**: Run `scripts/check.sh wiki`.
- **install.sh behavior**: After checks pass, run `install.sh` twice and verify
  the second run is idempotent.
