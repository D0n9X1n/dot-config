# QUICKREF

Condensed, machine-readable summary for agents and skim reading. See
`ReadMe.md` for full details.

## Purpose
Personal dotfiles repo. Single source of truth for shell, terminal, and editor
configuration; synced across machines via git + an idempotent installer that
creates symlinks into `$HOME` (and `~/.oh-my-zsh/custom/`).

## Layout
- `install.sh` — single entry point; idempotent; safe to re-run.
- `<repo>/.<name>` — root dotfiles linked to `$HOME/.<name>`. Currently:
  - `.wezterm.lua` → `$HOME/.wezterm.lua`
- `<repo>/copilot/<file>` — files linked to `$HOME/.copilot/<file>`. Currently:
  - `settings.json` — Copilot CLI settings (model: `claude-opus-4.7-1m-internal`,
    theme `dark`, `keepAlive: busy`, `continueOnAutoMode: true`, full footer
    UX, custom status line with `paddingTop: 2` to separate it from the
    input prompt, experimental features). Note: Copilot itself injects/strips
    a `"staff": true` field at runtime based on org membership — keep that
    field out of the committed file to avoid spurious diffs.
  - `statusline.sh` — executable script printing the custom status line.
    Renders 11 segments separated by `│` (each shown only when its data is
    available): `<icon> <Label> <value>` — Time, Req, Run, API, Cache,
    Last, Repo (clean/dirty + ↑↓), Stash, Venv, GH, MCP. The whole line is
    wrapped in ANSI dim (`\e[2m`…`\e[0m`) so it recedes from the prompt.
    Env overrides: `COPILOT_STATUSLINE_NO_ICONS=1` drops icons (keeps text
    labels); `COPILOT_STATUSLINE_NO_DIM=1` drops the dim wrap. Run
    `~/.copilot/statusline.sh --test` to verify each codepoint renders in
    your terminal (uses `fc-list` if installed). Parses Copilot's session
    JSON from stdin (single `jq` call) and caches `gh auth status` for
    5 min. Bash 3.2-compatible. `install.sh` ensures the executable bit
    is set.
  - `copilot-instructions.md` — global agent instructions (autonomous mode).
- `<repo>/oh-my-zsh-custom/<file>` — files linked to
  `$HOME/.oh-my-zsh/custom/<file>`. Currently:
  - `custom.zsh` — aliases, proxy helpers (`enable_proxy`/`disable_proxy`),
    brew completions, `PATH` extras (`.NET`, Android SDK).
  - `gg.zsh` — defines `gg <title>` which sets the WezTerm tab + window title
    (via OSC 1/2 escapes and `wezterm cli`) and runs `command copilot
    --allow-all-tools --allow-all-paths --effort xhigh`. Also sets
    `DISABLE_AUTO_TITLE=true` so oh-my-zsh hooks don't overwrite the title
    during the session.

## How install.sh works
1. macOS only (auto-installs Homebrew apps and fonts; failures are warnings,
   never fatal — handles deprecated taps and conflicting casks gracefully).
2. Symlinks every top-level `.<name>` file in the repo to `$HOME/.<name>`.
3. Symlinks every file in `oh-my-zsh-custom/` to `~/.oh-my-zsh/custom/`.
   Skipped (with a warning) if `~/.oh-my-zsh/custom/` does not exist.
4. Symlinks every file in `copilot/` to `~/.copilot/`.
   Skipped (with a warning) if `~/.copilot/` does not exist.
5. Existing destination files/links that don't match are renamed to
   `<name>.bak.YYYYMMDDHHMMSS` before linking.
6. Correct symlinks are left alone (no-op).

## Adding a new config
- New `~/.something` dotfile: drop `.something` at repo root, run `install.sh`.
- New oh-my-zsh customization: add a `*.zsh` file to `oh-my-zsh-custom/`,
  run `install.sh`. oh-my-zsh auto-loads files in alphabetical order.
- New Copilot CLI config: add a file to `copilot/`, run `install.sh`.
  Note: `mcp-config.json` is excluded (contains secrets) — manage it manually.
- Editing existing config: edit in this repo. Symlinks make changes live
  immediately on every machine.

## Sync workflow
```bash
# First time on a machine:
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
bash ~/Public/dot-configs/install.sh

# Pull updates:
cd ~/Public/dot-configs && git pull
# Re-run install.sh only if new files were added.
```

## Requirements (from configs)
- Apps: WezTerm. oh-my-zsh required only for the `oh-my-zsh-custom/` part.
- Fonts (auto-installed): Recursive (Rec Mono Baker), Recursive Mono Nerd Font,
  LXGW WenKai, Symbols Only Nerd Font, Noto Color Emoji.
- Optional brew formulae sourced if present: `autojump`,
  `zsh-fast-syntax-highlighting`, `zsh-completions`.

## Notes
- Safe to re-run `install.sh` anytime; existing correct links are skipped.
- Backups are created only when a non-matching file/link exists.
- `oh-my-zsh-custom/custom.zsh` shadows oh-my-zsh's default
  `custom/custom.zsh` (which is gitignored upstream and irrelevant here).
