# CLAUDE.md

> Agent-facing instructions for Claude Code (and similar Anthropic agents)
> working on this repository. Mirrors `.github/copilot-instructions.md`,
> with Claude-Code-specific guidance added.

## Read these first

1. **`QUICKREF.md`** — single source of truth for how this repo works.
   Update it when behavior changes.
2. **`ReadMe.md`** — human-facing README. Update separately when
   user-visible details change.

## Repo summary

Personal dotfiles, synced across machines via git + symlinks. macOS-only;
`install.sh` is the single installer.

```
.
├── install.sh                   # idempotent linker (macOS only)
├── .tmux.conf                   # symlinked into $HOME
├── oh-my-zsh-custom/            # zsh customs
├── claude/                      # Claude Code config + statusline
│   ├── settings.json
│   └── statusline.sh
├── copilot/                     # Same shape for GitHub Copilot CLI
├── wezterm/wezterm.lua          # symlinked to ~/.wezterm.lua
├── launchd/                     # macOS launchd agent templates (rendered by install.sh)
├── mcp-shared.json              # secret-free MCP entries (synced)
└── .github/, .claude/
```

## Architecture rules

- **`mcp-shared.json` is for non-secret MCP entries only.** Anything
  needing a token/key goes in the gitignored
  `~/.config/github-copilot/mcp.json` per device — install.sh's merge
  step preserves it.
- **`claude/statusline.sh` and `copilot/statusline.sh` must stay
  functionally aligned.** Same segments, same output shape, same Gruvbox
  palette, same per-cwd 5s git cache. When you change one, port the
  change to the sibling.
- **launchd plists in `launchd/` are templates, not symlinks.**
  install.sh substitutes `__HOME__` -> `$HOME` (launchd doesn't expand
  `$HOME` at runtime) and `__SRC_DIR__` -> this repo's absolute path (for
  agents that exec a tracked script, e.g. `clean-npm-caches.sh`), writes the
  rendered file to `~/Library/LaunchAgents/`, then `bootout`+`bootstrap` into
  `gui/<uid>`. macOS-only; install.sh skips this step on other OSes.
  Current agents: `com.d0n9x1n.copilot-relay` (relay proxy, on login) and
  `com.d0n9x1n.npm-cache-clean` (weekly npm/npx cache prune, Sun 03:17).
- **install.sh bootstraps a brand-new Mac.** It installs Homebrew if missing,
  Homebrew formulae/casks (including Claude Code via `claude-code`), npm globals
  for Copilot CLI + `copilot-relay`, oh-my-zsh, custom RecMono fonts from
  `MOSconfig/recursive-code-config`, then links configs.

## Conventions

### Shell scripts (.sh)

- `set -euo pipefail` strict mode.
- Bash 3.2 compatible (macOS default). Avoid `${arr[@]}` quirks,
  `\u` escapes, associative arrays, `printf '%(...)T'`.
- POSIX-portable utilities: `awk`, `sed`, `grep`, `find -print0`,
  `stat -f %m || stat -c %Y` fallback (Darwin vs GNU).
- Statusline scripts use `printf -v __SEG` instead of `$(seg_$s)`
  capture — saves one fork per segment.

### Config files

- Color scheme: **Gruvbox dark hard (base16)** in WezTerm; matching
  Gruvbox accents in tmux + statusline.
- Statusline label icons are **FontAwesome** glyphs (U+F0xx–F2xx),
  rendered via raw UTF-8 bytes in bash (since bash 3.2 doesn't support
  `\u`).
- Five-line layout: literal `\n` tokens in `SEGMENTS` introduce line
  breaks. L1 time/run/api/cost · L2 model/effort/context ·
  L3 mcp/skills/agents/style · L4 cwd path · L5 repo/branch/diff/stash/worktree.

## When you make changes

- **Bump version + tag**. We use semver-ish tags (`v0.X.Y`); patch for
  bugfixes, minor for new features, major for breaking changes.
  Existing history: v0.1.0 → v0.17.0. Pushing a `v*.*.*` tag triggers
  `.github/workflows/release.yml`, which publishes a GitHub Release
  with auto-generated notes.
- **Update QUICKREF.md** when behavior changes — the agent-facing brief
  must stay accurate.
- **Update ReadMe.md** when user-visible details change.
- **Run smoke tests on macOS** (the supported target):

  ```bash
  bash -n install.sh
  echo '{}' | ~/.claude/statusline.sh
  echo '{"model":{"display_name":"Claude (xhigh)"}}' | ~/.copilot/statusline.sh
  ```

  All three should succeed silently / print colored output. CI
  (`.github/workflows/ci.yml`) runs the same checks on macOS plus
  `shellcheck -S error` on Ubuntu for every push/PR.

## Things that have bitten us

- `~/.claude/settings.json` and `~/.claude.json` are **different files**
  with different responsibilities. Settings: behavior. `.claude.json`
  (top level): MCP servers + state.
- `refreshInterval` is **nested inside `statusLine`**, not top-level.
  Trust the binary's strings table over documentation.
- `permissions.defaultMode: "bypassPermissions"` is **silently rejected**
  by Claude Code's binary ("bypassPermissions mode is disabled by
  settings"). The CLI flag `--permission-mode bypassPermissions` IS
  honored. Wrap launchers (oh-my-zsh-custom/claude.zsh,
  oh-my-zsh-custom/cc.zsh) to inject the flag.
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

## Model-routing convention (claude/settings.json)

Sonnet and Opus are treated as **separate model families** by user
convention. Current routing:

- Opus 4-5 / 4-6 / 4-7 / 4-8 → top-level `model` plus zsh wrappers
  (`claude-opus-4-8[1m]`; the `[1m]` suffix is the explicit 1M opt-in in
  Claude Code; relay matches the `opus` substring and maps it to upstream
  `claude-opus-4.8`, ignoring the suffix; do not use `default` with
  copilot-relay because it routes to `gpt-5.5`)
- Sonnet 4-5 / 4-6 → Claude-facing `gpt-5.5[1m]` (relay upstream `gpt-5.5`)
- Haiku 4-5 → `gpt-5.5[1m]`
- gpt-5-mini → `gpt-5.5[1m]`

When asked to "use the same model for the family", apply within Opus or
within Sonnet — never both. When adding a new alias, default to the
family rule above.

## Don't do

- Don't commit secrets. The repo is public on github.com/D0n9X1n/dot-config.
- Don't add files outside `claude/`, `copilot/`, `oh-my-zsh-custom/`,
  `wezterm/` without updating install.sh.
- macOS-only. The repo is not regression-tested on other platforms.
- Don't `--no-verify` git commits unless the user explicitly asks.
