# CLAUDE.md

> Agent-facing instructions for Claude Code (and similar Anthropic agents)
> working on this repository. Mirrors `.github/copilot-instructions.md`,
> with Claude-Code-specific guidance added.

## Read these first

1. **`QUICKREF.md`** — single source of truth for how this repo works.
   Update it when behavior changes.
2. **`ReadMe.md`** — human-facing README. Update separately when
   user-visible details change.
3. **`docs/WINDOWS.md`** — Windows runbook + the PowerShell port story.

## Repo summary

Personal dotfiles, synced across machines via git + symlinks. Two
installers — `install.sh` (macOS / Linux) and `install.ps1` (Windows
PowerShell 7+). Each skips the other platform's files.

```
.
├── install.sh / install.ps1     # idempotent linkers, platform-split
├── .tmux.conf                   # symlinked into $HOME on POSIX
├── oh-my-zsh-custom/            # zsh customs (POSIX only)
├── powershell-profile.ps1       # PowerShell equivalent (cc/gg/c/ll)
├── claude/                      # Claude Code config + statusline
│   ├── settings.json            # macOS/Linux
│   ├── settings-windows.json    # Windows variant (statusLine.command -> .ps1)
│   ├── statusline.sh + .ps1     # bash + PowerShell, parity-maintained
├── copilot/                     # Same shape for GitHub Copilot CLI
├── wezterm/wezterm.lua          # opt-in symlink
├── mcp-shared.json              # secret-free MCP entries (synced)
└── .github/, .claude/, docs/
```

## Architecture rules

- **install.sh and install.ps1 must stay in lockstep.** When you add a
  new linkable file, both installers must learn about it. The split
  rule: `.sh` files are linked only by install.sh; `.ps1` files only by
  install.ps1; `settings-windows.json` exists everywhere but only
  install.ps1 picks it (and lands it as the canonical `settings.json`).
- **`mcp-shared.json` is for non-secret MCP entries only.** Anything
  needing a token/key goes in the gitignored
  `~/.config/github-copilot/mcp.json` per device — install.sh's merge
  step preserves it.
- **statusline.sh and statusline.ps1 must stay functionally aligned.**
  Same segments, same output shape, same Gruvbox palette, same
  vim-airline mode badge, same per-cwd 5s git cache. When you change
  one, port the change to the other (and to the copilot/* siblings).

## Conventions

### Shell scripts (.sh)

- `set -euo pipefail` strict mode.
- Bash 3.2 compatible (macOS default). Avoid `${arr[@]}` quirks,
  `\u` escapes, associative arrays, `printf '%(...)T'`.
- POSIX-portable utilities: `awk`, `sed`, `grep`, `find -print0`,
  `stat -f %m || stat -c %Y` fallback (Darwin vs GNU).
- Statusline scripts use `printf -v __SEG` instead of `$(seg_$s)`
  capture — saves one fork per segment.

### PowerShell scripts (.ps1)

- PowerShell 7+ syntax (the cross-platform pwsh, not Windows
  PowerShell 5.1). The `?.` operator, modern `Get-Command -ErrorAction`
  patterns are fine.
- `$ErrorActionPreference = 'Stop'` at top.
- `$PSNativeCommandUseErrorActionPreference = $false` so a non-zero
  `git` exit doesn't blow up the whole script.
- Indent 4 spaces; helpers as `function Verb-Noun` (verb-noun convention).

### Config files

- Color scheme: **Gruvbox dark hard (base16)** in WezTerm; matching
  Gruvbox accents in tmux + statusline.
- Statusline label icons are **FontAwesome** glyphs (U+F0xx–F2xx),
  rendered via raw UTF-8 bytes in bash (since bash 3.2 doesn't support
  `\u`) and `\u{F0xx}` in PowerShell.
- Two-line layout: a literal `\n` token in `SEGMENTS` introduces a
  line break. Status segments line 1, repo + integrations line 2.

## When you make changes

- **Bump version + tag**. We use semver-ish tags (`v0.X.Y`); patch for
  bugfixes, minor for new features, major for breaking changes.
  Existing history: v0.1.0 → v0.9.1.
- **Update QUICKREF.md** when behavior changes — the agent-facing brief
  must stay accurate.
- **Update ReadMe.md** when user-visible details change.
- **Run smoke tests on macOS** (the supported target):

  ```bash
  bash -n install.sh
  echo '{"vim":{"mode":"INSERT"}}' | ~/.claude/statusline.sh
  echo '{"model":{"display_name":"Claude (xhigh)"}}' | ~/.copilot/statusline.sh
  ```

  All three should succeed silently / print colored output.

## Things that have bitten us

- `~/.claude/settings.json` and `~/.claude.json` are **different files**
  with different responsibilities. Settings: behavior. `.claude.json`
  (top level): MCP servers + state.
- `hideVimModeIndicator` and `refreshInterval` are **nested inside
  `statusLine`**, not top-level. Trust the binary's strings table over
  documentation.
- `permissions.defaultMode: "bypassPermissions"` is **silently rejected**
  by Claude Code's binary ("bypassPermissions mode is disabled by
  settings"). The CLI flag `--permission-mode bypassPermissions` IS
  honored. Wrap launchers (oh-my-zsh-custom/claude.zsh,
  oh-my-zsh-custom/cc.zsh, powershell-profile.ps1) to inject the flag.
- `skipDangerousModePermissionPrompt` is dead config (only meaningful
  when bypass mode is active, which is gated off in settings). Claude
  Code's runtime sometimes re-adds it on its own writes; treat as noise.
- WezTerm's `inactive_pane_hsb` defaults to `{1, 0.9, 0.8}` — that
  desaturates unfocused windows and makes side-by-side comparisons
  look mismatched. Set `{1, 1, 1}` to disable.
- tmux 3.2+ uses `terminal-features ... :RGB` to advertise truecolor;
  `terminal-overrides ... :RGB` alone leaves tmux quantizing into the
  256-color cube.
- GitHub's hosted MCP doesn't support OAuth Dynamic Client Registration
  with Anthropic's SDK. Use Bearer-PAT auth in HTTP headers (per
  github/github-mcp-server's official Claude Code guide).

## Model-routing convention (modelOverrides in claude/settings.json)

Sonnet and Opus are treated as **separate model families** by user
convention. Current routing:

- Opus 4-5 / 4-6 / 4-7 → `claude-opus-4.7-1m-internal`
- Sonnet 4-5 / 4-6 → `gpt-5.5`
- Haiku 4-5 → `claude-opus-4.7-1m-internal`
- gpt-5-mini → `gpt-5.5`

When asked to "use the same model for the family", apply within Opus or
within Sonnet — never both. When adding a new alias, default to the
family rule above.

## Don't do

- Don't commit secrets. The repo is public on github.com/D0n9X1n/dot-config.
- Don't add files outside `claude/`, `copilot/`, `oh-my-zsh-custom/`,
  `wezterm/` without updating both installers.
- Don't break Mac. macOS is the regression-tested target; Windows ports
  are 1:1 translations not run-tested by the maintainer.
- Don't `--no-verify` git commits unless the user explicitly asks.
