# QUICKREF

Condensed, machine-readable summary for agents and skim reading. See
`ReadMe.md` for full details.

## Purpose
Personal dotfiles repo. Single source of truth for shell, terminal, and editor
configuration; synced across machines via git + an idempotent installer that
creates symlinks into `$HOME` (and `~/.oh-my-zsh/custom/`).

## Layout
- `install.sh` — macOS entry point; idempotent; safe to re-run. Bootstraps
  Homebrew if missing, then installs Homebrew deps, npm CLIs, oh-my-zsh, and
  the copilot-relay launchd agent. Logs full install/update command output to
  `~/Library/Logs/dot-configs-install.log`.
- `.github/workflows/ci.yml` — push/PR. macOS smoke runs
  `scripts/check.sh smoke` (bash syntax, statuslines, install parse, zsh syntax,
  Copilot subagent statusline smoke). Ubuntu installs shellcheck and runs
  `scripts/check.sh shellcheck` with SC1090/1091/2148/2155 excluded.
- `.github/workflows/release.yml` — on tag `v*.*.*`, publishes a GitHub
  Release (`softprops/action-gh-release@v2`) whose body is generated from the
  commit-subject list between the current tag and the previous reachable
  `v*.*.*` tag. Flow: bump version, commit, create a new annotated tag, and
  push that tag explicitly; verify the workflow and live release body.
- `.github/workflows/publish-wiki.yml` — on `main` changes to `wiki/**` or the
  workflow, publishes the flat bilingual source to the separate GitHub Wiki
  repository. Renames `README.md` to `Home.md`, rewrites flat `.md` links,
  replaces source-managed pages wholesale, and pushes without force. The Wiki
  must be initialized once in GitHub first; browser edits are overwritten.
- Copilot CLI WakaTime upload is handled by the WakaTime-owned
  `wakatime/copilot-cli-wakatime` plugin, installed/updated by `install.sh`
  with `copilot plugin`. No repo-local hook JSON is tracked.
- `scripts/check.sh` — local/CI parity checks. Run `scripts/check.sh all`
  before pushing shell/statusline/install changes. `instructions` validates
  global Claude/Copilot instruction content, discovery, and backup/linking.
- `claude/CLAUDE.md` — user-global Claude Code guidance linked to
  `~/.claude/CLAUDE.md`; preserves Mermaid rules and teaches reusable Wiki and
  commit-derived release workflows.
- `copilot/AGENTS.md` — equivalent global Wiki/release guidance linked to
  `~/.copilot/AGENTS.md`. Copilot discovers it because `custom.zsh` appends
  `~/.copilot` to `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`; the native global entry
  point remains `copilot/copilot-instructions.md`.
- `mcp-shared.json` — secret-free MCP entries synced via git. install.sh
  merges into local Copilot mcp.json; the existing pipeline lifts the
  merged set into `~/.claude.json`. Secrets stay per-device.
- `launchd/com.d0n9x1n.copilot-relay.plist` — macOS launchd agent
  **template** (not symlinked; install.sh renders `__HOME__` -> `$HOME`
  into `~/Library/LaunchAgents/` then `bootout`+`bootstrap` into
  `gui/<uid>`). Starts `copilot-relay` on login, restarts on crash,
  logs to `~/Library/Logs/copilot-relay.{out,err}.log` and
  `~/.copilot-relay/logs/copilot-relay.log`. `install.sh` installs or
  updates the npm package first, links tracked `.copilot-relay/config.yaml`
  into `~/.copilot-relay/config.yaml`, unloads/removes legacy proxy launchd
  jobs, and restarts the relay agent so it runs the latest installed version.
- `launchd/com.d0n9x1n.copilot-relay-healthcheck.plist` +
  `launchd/copilot-relay-healthcheck.sh` — macOS launchd watchdog, **two tiers**.
  Runs at load and every 60s. **Tier 1 (every run, free):** `GET
  http://127.0.0.1:4142/healthz`; not-200 means the process is gone, so
  `launchctl kickstart -k` the relay. `/healthz` is a static handler that never
  contacts Copilot, so 200 proves only that a socket is listening. **Tier 2
  (time-gated, every 900s):** `copilot-relay status --deep` sends a real request
  through Copilot — the only check that catches a relay that is listening but
  whose token expired. Exit `1` (not running) and `2` (listening, cannot reach
  Copilot — usually expired auth, where the fix is `copilot-relay auth`, not a
  restart) are logged distinctly. Needs `copilot-relay >= 0.2.6`. Healthy is a
  no-op at both tiers. Tune with `COPILOT_RELAY_DEEP_INTERVAL` (0 disables) and
  `COPILOT_RELAY_DEEP_MAX_TIME`. Logs to
  `~/Library/Logs/copilot-relay-healthcheck.log`; deep-check timestamp in
  `~/Library/Caches/copilot-relay-healthcheck.deep`.
- `launchd/com.d0n9x1n.npm-cache-clean.plist` + `launchd/clean-npm-caches.sh`
  — macOS launchd agent **template** + its tracked script. install.sh renders
  `__HOME__` -> `$HOME` and `__SRC_DIR__` -> repo path into
  `~/Library/LaunchAgents/`, then `bootout`+`bootstrap` into `gui/<uid>`.
  Runs **weekly (Sun 03:17)**, not at load: `npm cache clean --force` (empties
  `~/.npm/_cacache`) + prunes `~/.npm/_npx` copies older than 14 days (by dir
  mtime — macOS has no atime). **Never touches** `~/Library/Caches/ms-playwright`
  (downloaded browser binaries). Logs to `~/Library/Logs/npm-cache-clean.log`
  (capped 500 lines) + `.{out,err}.log`. Run now:
  `launchctl kickstart -k gui/$(id -u)/com.d0n9x1n.npm-cache-clean`.
- `.claude/CLAUDE.md` — agent instructions for Claude Code working in
  this repo. Mirrors `.github/copilot-instructions.md`.
- `<repo>/.<name>` — root dotfiles linked to `$HOME/.<name>`. Active:
  - `.rmux.conf` — RMUX 0.10.x native config and primary multiplexer profile.
    RMUX is an independent Rust daemon/client, not a tmux wrapper or terminal
    emulator. Uses prefix `C-q`, mouse on with `prefix + T` toggle, top Gruvbox
    status bar, one-based/renumbered windows and panes, CWD-preserving `|`/`-`
    splits, vim navigation/resizing, explicit `Tab` last-window, vi copy mode
    with `pbcopy`, and trusted-pane OSC 52. Clears stale `TERMINFO`,
    `TERMINFO_DIRS`, and `TERMCAP` but preserves RMUX's `TERM_PROGRAM=rmux`.
    No TPM/plugin/run-shell bootstrap. The native file prevents fallback to the
    executable archived tmux config. Validate with `scripts/check.sh rmux`.
- `<repo>/archive/` — inert retired sources, never linked: former TPM-enabled
  `tmux/.tmux.conf` and former `wezterm/wezterm.lua`. `install.sh` installs
  neither app; SonicTerm is the managed outer terminal. Existing local tmux plugins and
  resurrect snapshots are preserved for rollback.
- `<repo>/wiki/` — flat English + Simplified Chinese GitHub Wiki source.
  English pages have `-zh-CN` pairs, `README.md` publishes as `Home.md`, and one
  bilingual `_Sidebar.md` links all pages. Validate with `scripts/check.sh wiki`.
- `<repo>/.sonicterm/` — SonicTerm terminal config, auto-linked by
  `install.sh` into `~/.sonicterm/`. This is **not** a whole-directory symlink:
  only `sonicterm.toml`, `keymaps/*.toml`, and `themes/*.toml` are linked so
  runtime `logs/` and backup files remain machine-local.
  Current config pins theme `wezterm`, keymap `sonicterm-macos`, Rec Mono
  St.Helens 14 / line-height 1.2, `TERM_PROGRAM=WezTerm`, 1000-line scrollback,
  no cursor blink, software render mode auto, Gruvbox/WezTerm-aligned theme
  colors, and WezTerm-compatible macOS/Linux/Windows keymaps.
- `<repo>/.copilot-relay/config.yaml` — secret-free relay config linked by
  `install.sh` to `~/.copilot-relay/config.yaml`. Pins `claudeSetup: false`,
  local server `127.0.0.1:4142`, `thinkEffort: max`, `gptModel: gpt-5.6-sol`,
  and `opusModel: claude-opus-5`. Do **not** commit
  `~/.copilot-relay/github_token`, `copilot_token.json`, or `logs/`.
- `<repo>/themes/apollo/` — **reference theme files; NOT auto-linked**.
  Apollo = Gruvbox hard + Material warm-beige ANSI 7 + `#141617` canvas.
  Ships matched colorschemes for WezTerm (`apollo.lua`), Vim
  (`apollo.vim`), Neovim (`apollo.nvim.lua`), VS Code
  (`apollo-color-theme.json`), and Windows Terminal
  (`apollo.terminal.json`). `PALETTE.md` is the single source of truth —
  when you change a color, update every file in this directory.
  See `themes/apollo/README.md` for per-editor install snippets.
- `<repo>/copilot/<file>` — files linked to `$HOME/.copilot/<file>`. Currently:
  - `settings.json` — Copilot CLI settings (model: `claude-opus-5`,
    `contextTier: long_context` = 1M context, effort `max`, theme `dark`,
    `keepAlive: busy`,
    `continueOnAutoMode: true`, custom footer/status line, and
    `subagentStart`/`subagentStop` hooks to maintain live subagent rows via
    `~/.copilot/subagent-state.sh`). The `statusLine` block only
    takes a single `padding` field — per-side spacing is done in
    `statusline.sh` (newlines for top, leading spaces for left). Note:
    Copilot itself injects/strips a `"staff": true` field at runtime based
    on org membership; keep that field out of the committed file to avoid
    spurious diffs.
  - `statusline.sh` — executable script printing the custom status line.
    A "full mirror" of `~/.claude/statusline.sh`: five-line default layout
    with per-segment Gruvbox accents and color-graded Context %. Renders
    `<icon> <Label> <value>` separated by `│`: L1 time/run/req/wakatime,
    L2 model/effort/context, L3 mcp/skills/agents/tasks/style, L4 cwd path,
    L5 repo/branch/diff/stash/worktree. Default icon accent colors are arranged
    so adjacent segments and same-column segments use different colors.
    Copilot-only segments (`wall`,
    `api`, `cache_pct`, `last_call`, `gh_account`, `ext_count`, `venv`)
    remain available via `COPILOT_STATUSLINE_SEGMENTS`. Env overrides:
    `COPILOT_STATUSLINE_NO_ICONS=1` drops icons (keeps text labels);
    `COPILOT_STATUSLINE_NO_COLOR=1` drops color (legacy
    `COPILOT_STATUSLINE_NO_DIM=1` is honored as an alias);
    `COPILOT_STATUSLINE_PAD_TOP=N` / `..._PAD_LEFT=N` / `..._PAD_RIGHT=N`
    override per-side padding (default top=0, left=0, right=0);
    `COPILOT_STATUSLINE_SEGMENTS="…"` overrides the segment list and order.
    The CLI's `statusLine.padding*` fields are silently ignored — only
    `padding` works there, so we emit our own spacing instead. Run
    `~/.copilot/statusline.sh --test` to verify each codepoint renders in
    your terminal (uses `fc-list` if installed). Parses Copilot's session
    JSON from stdin (single `jq` call), caches git state for 5s
    (`COPILOT_STATUSLINE_GIT_TTL=N`), and caches `gh auth status` for
    5 min. Bash 3.2-compatible. `install.sh` ensures the executable bit
    is set. v0.6.0: sibling `claude/statusline.sh` warm-cache 125ms→18ms
    via pure-bash JSON parsing (no jq dep), per-cwd git cache (5s TTL
    at `$TMPDIR/claude-statusline-cache-$USER/git-<hash>`), no awk
    forks (`cost`/`ctx`/`fmt_tokens` use bash printf/arith), and
    `printf -v __SEG` instead of per-segment subshells. v0.8.0: multi-line
    layout via literal `\n` token in `SEGMENTS`. v0.13.x: 5-line default —
    L1 time/run/req/wakatime · L2 model/effort/context ·
    L3 mcp/skills/agents/tasks/style · L4 cwd path (new `seg_path`, U+F07C,
    $HOME→~) · L5 repo/branch/diff/stash/worktree. `seg_agent` counts
    local custom agent profiles (`*.md` in `~/.copilot/agents/` +
    `<cwd>/.github/agents/`) and `seg_skills` counts skill bundles
    (`SKILL.md` under `~/.copilot/skills/`, `~/.agents/skills/`,
    `<cwd>/.github/skills/`, `<cwd>/.claude/skills/`, and
    `<cwd>/.agents/skills/`) — NOT live sub-agents. Both show `0`.
    `seg_subagents` shows the live running-subagent count. `seg_timer`
    formats as `Nh Mm` for sessions ≥ 1h (v0.13.2).
    Active subagent rows (below L5, after a `----------------------------------------`
    separator) use a terminal icon for `main` and a magic-wand icon (U+F0D0) for
    subagents, then show agent name, purpose, and running time from the hook-maintained
    `$TMPDIR/copilot-subagents-$USER/<session>.rows` file first, then a
    signature-cached `events.jsonl` fallback if hook rows are missing. Controlled by `COPILOT_STATUSLINE_MAX_SUBAGENTS=N`
    (default 8), `COPILOT_STATUSLINE_SUBAGENT_ROOT=0` to hide the root "main"
    row, and `COPILOT_STATUSLINE_SUBAGENT_STATE_DIR=dir` for tests/debugging.
  - `subagent-state.sh` — executable Copilot hook helper. `sessionStart` and
    `sessionEnd` reset the per-session rows file; `subagentStart` appends
    `toolCallId/name/purpose/started_at`; `subagentStop` removes by
    `toolCallId` first, then falls back to FIFO by agent name/display name.
  - `cleanup-legacy.sh` — executable cleanup hook for Copilot CLI upgrades.
    Keeps only the current `~/.copilot/pkg/<platform>/<version>` payload
    (detected from `copilot --version`), removes older package versions,
    empty pkg dirs, `.DS_Store`, `*.bak.*`, and all but the newest
    `logs/process-*.log`. `install.sh` runs it after linking Copilot files;
    `oh-my-zsh-custom/copilot.zsh` runs it after successful `copilot update`.
  - `copilot-instructions.md` — global agent instructions (autonomous mode).
- `<repo>/claude/<file>` — files linked to `$HOME/.claude/<file>`. Currently:
  - `settings.json` — Claude Code → Copilot bridge AND global default-pinning.
    Sets `ANTHROPIC_BASE_URL=http://127.0.0.1:4142`,
    `ANTHROPIC_AUTH_TOKEN=dummy` (Claude Code requires a token-shaped
    custom key; relay auth is handled by `npx copilot-relay auth`), and pins
    **Sonnet 5 @ max effort, 1M context** as Claude Code's global picker/default
    identity for every machine that runs `install.sh`:
    `ANTHROPIC_MODEL=claude-sonnet-5[1m]`; wrappers also inject
    `--model 'claude-sonnet-5[1m]' --effort max` because Claude Code can rewrite
    `settings.json` at runtime. `ANTHROPIC_DEFAULT_SONNET_MODEL` uses the same
    ID, while its `_NAME` and `_DESCRIPTION` companions render **Sonnet 5** in
    `/model` and disclose the relay mapping. The `[1m]` suffix keeps Claude
    Code's **1M-context accounting** instead of falling back to 200k.
    `copilot-relay` routes every model name that does not contain `opus` to
    `gptModel: gpt-5.6-sol`, so the actual upstream for this Sonnet-facing
    default is **gpt-5.6-sol**. Real Opus 5 remains reachable via `/model` or
    `--model 'claude-opus-5[1m]'`, which matches the `opus` lane and maps to
    `opusModel: claude-opus-5`. `effortLevel="max"` supplies the deepest
    client-side reasoning level, and `MODEL_REASONING_EFFORT=max` lets the
    statusline display it. Haiku/small-fast overrides remain pinned to
    `gpt-5.6-sol[1m]`, which reaches the same GPT lane with 1M accounting.
    Relay-side thinking is pinned by `~/.copilot-relay/config.yaml` as
    `thinkEffort: max`.
    Autonomous mode is enabled via
    `skipAutoPermissionPrompt=true` + `skipDangerousModePermissionPrompt=true` +
    `permissions.defaultMode="auto"`.
    Note: `defaultMode="bypassPermissions"` is silently rejected by the
    binary ("bypassPermissions mode is disabled by settings"); for full
    bypass see the wrapper functions in `oh-my-zsh-custom/claude.zsh` and
    `cc.zsh` which inject `--permission-mode bypassPermissions` per launch —
    the only path the binary honors.
    Also pins `statusLine.refreshInterval=100` for snappy redraws and
    `theme="dark-ansi"` so chrome inherits the terminal's ANSI palette.
    Requires local `copilot-relay` running. The launchd agent runs
    `copilot-relay start`; `install.sh` keeps the package updated, sets
    `claudeSetup: false` so the relay does not rewrite this repo's
    symlinked `settings.json`, and restarts the agent. On a fresh box,
    `install.sh` installs Claude Code via Homebrew cask + relay via npm;
    one-time remaining step is `npx copilot-relay auth` (browser device-code
    flow), then re-run `install.sh` so launchd starts the authenticated relay.
    Project-specific Claude config syncs only when committed in each project
    repo (`.claude/settings.json`, `.claude/CLAUDE.md`, `.mcp.json`);
    `~/.claude.json.projects` is machine-local/path-keyed and is not copied.
    `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=16` uses Claude Code's native
    concurrent-subagent admission limit (requires v2.1.217+). At 16 running
    subagents, another Claude-spawned `Agent` call fails until a slot reopens.
    Native exceptions are intentional: `/subtask` occupies a slot but is not
    blocked, resumes can exceed the configured count, ultracode is exempt, and
    workflow/agent-team workers use separate limits. `install.sh` verifies the
    active CLI first, uses the Homebrew cask only when needed, and removes the obsolete
    repo-managed counter symlink without touching user hooks. Claude's
    statusline **does not read or render** subagents — Claude Code ships its own
    native subagent UI, so it has neither the inline count nor a live-agent tree
    below L5 (intentional divergence from the Copilot sibling, which keeps both).
- `<repo>/oh-my-zsh-custom/<file>` — files linked to
  `$HOME/.oh-my-zsh/custom/<file>`. Currently:
  - `custom.zsh` — aliases, proxy helpers (`enable_proxy`/`disable_proxy`),
    Homebrew completions/syntax highlighting/autojump, compaudit permission
    repair before `compinit -i`, and `PATH` extras (`.NET`, Android SDK).
  - `copilot.zsh` — wraps all Copilot launches with process-scoped
    `TERM_PROGRAM=WezTerm`, `COLORTERM=truecolor`, and `FORCE_COLOR=3` so
    Copilot uses its supported true-color path inside RMUX without changing the
    pane's global `TERM_PROGRAM=rmux`; successful updates also run cleanup.
  - `gg.zsh` — defines `gg [title]`, emits OSC 1/2 for the SonicTerm title,
    and calls `rmux rename-window` inside RMUX. No tmux or WezTerm CLI fallback
    remains. The Copilot child receives the same process-scoped
    WezTerm/truecolor compatibility environment as `copilot.zsh`. Sets
    `DISABLE_AUTO_TITLE=true` so oh-my-zsh hooks do not overwrite the title.

## How install.sh works
`install.sh` writes timestamped output to
`~/Library/Logs/dot-configs-install.log` (override with
`DOT_CONFIGS_INSTALL_LOG=/path/to/log`).

1. macOS only: bootstraps Homebrew if missing, then installs deps via
   Homebrew (best-effort after brew exists, except the required Claude Code
   version). Set `SKIP_BREW=1` to skip
   (useful for CI / fake-`HOME` testing). Formulae: `autojump`, `eza`, `git`,
   `jq`, `neovim`, `node`, `rmux`, `zsh-completions`,
   `zsh-fast-syntax-highlighting`. Then removes old npm global
   `@anthropic-ai/claude-code` if present, ensures the active Claude Code is at
   least v2.1.217 (using the Homebrew cask only when needed), and installs font casks:
   `font-recursive`, `font-recursive-mono-nerd-font`,
   `font-symbols-only-nerd-font`, `font-noto-color-emoji`. It also downloads
   `RecMonoBaker-*.ttf` and `RecMonoSt.Helens-*.ttf` from the latest
   `MOSconfig/recursive-code-config` release into `~/Library/Fonts`.
2. Installs/updates npm global CLIs only when missing or already npm-managed:
   `@github/copilot` and `copilot-relay`.
   Existing non-npm binaries (for example cask-managed `copilot`) are left in
   place to avoid npm `EEXIST`. Set `SKIP_NPM_GLOBALS=1` to skip.
3. Installs oh-my-zsh unattended if missing (`RUNZSH=no`, `CHSH=no`) and fixes
   insecure zsh completion directory permissions; set `SKIP_OH_MY_ZSH=1` to skip
   installation.
4. Symlinks every non-ignored top-level `.<name>` file in the repo to
   `$HOME/.<name>` (including `.rmux.conf`; ignored generated files are
   skipped), then removes only the exact retired repo-owned `~/.tmux.conf` and
   `~/.wezterm.lua` links. User files and links to other targets survive.
5. Symlinks every file in `oh-my-zsh-custom/` to `~/.oh-my-zsh/custom/`.
6. Symlinks every file in `copilot/` to `~/.copilot/`, creating the
   destination directory if missing, then runs `cleanup-legacy.sh` to prune
   stale Copilot CLI package versions/logs.
7. Symlinks every top-level config file in `claude/` to `~/.claude/`.
   **Creates the destination directory if missing** (Claude Code only creates
   `~/.claude/` on first launch), and removes the obsolete repo-managed
   `~/.claude/hooks/subagent-counter.sh` symlink while preserving user hooks.
   Skills are one directory deeper (`claude/skills/<name>/SKILL.md`) and get a
   separate pass linking each skill's files into `~/.claude/skills/<name>/`
   — global, so they load in every project, not just this repo.
8. Does not install or configure WezTerm; the old profile is inert under
   `archive/wezterm/`. SonicTerm is the actively managed outer terminal.
9. Symlinks tracked `.sonicterm` TOML files into `~/.sonicterm/` while leaving
   logs/backups local.
10. Does not bootstrap TPM or install a global tmux shim. Existing tmux plugin
    and resurrect data remains local for rollback.
11. Links tracked `.copilot-relay/config.yaml`, then configures the
    `copilot-relay` launchd agent and its `/healthz` watchdog. If `/healthz`
    already returns 200, leaves the running relay untouched; otherwise starts or
    restarts the launchd agent. If unauthenticated, prints a red
    `ACTION REQUIRED` log telling the user to run `npx copilot-relay auth`
    first; after auth, re-run `install.sh` to start launchd.
12. Loads the `npm-cache-clean` launchd agent (macOS): renders the template +
    `bootout`/`bootstrap`. Runs weekly (Sun 03:17), no auth needed.
13. Existing destination files/links that don't match are renamed to
   `<name>.bak.YYYYMMDDHHMMSS` before linking; only the newest backup for each
   destination is kept.
14. Correct symlinks are left alone (no-op).

## Adding a new config
- New `~/.something` dotfile: drop `.something` at repo root, run `install.sh`.
- New oh-my-zsh customization: add a `*.zsh` file to `oh-my-zsh-custom/`,
  run `install.sh`. oh-my-zsh auto-loads files in alphabetical order.
- New Copilot CLI config: add a file to `copilot/`, run `install.sh`.
  Note: `mcp-config.json` is excluded (contains secrets) — manage it manually.
- New Claude Code config: add a file to `claude/`, run `install.sh`.
  The destination directory is created automatically.
- New Claude Code skill: add `claude/skills/<name>/SKILL.md` (frontmatter needs
  `name` + a `description` with explicit TRIGGER/SKIP wording), run
  `install.sh`. Supporting files in the same directory are linked too.
- New SonicTerm config: add TOML under `.sonicterm/`, `.sonicterm/keymaps/`,
  or `.sonicterm/themes/`, run `install.sh`. Do not commit `~/.sonicterm/logs/`
  or runtime backup files.
- copilot-relay config: edit `.copilot-relay/config.yaml`, run `install.sh` (or
  rely on the existing symlink). Secrets/tokens/logs under `~/.copilot-relay/`
  stay machine-local.
- New synced MCP server (secret-free): add to `mcp-shared.json`,
  run `install.sh`. Merged into the local Copilot mcp.json (shared
  wins on collision), then imported into `~/.claude.json` so both tools
  see it. Secret-bearing MCPs (PATs, API keys) go in the gitignored
  `~/.config/github-copilot/mcp.json` per device — install.sh's merge
  preserves them. **GitHub MCP**: needs Bearer-PAT in `headers`
  (no OAuth/DCR support in the hosted server) — see `_github_template`
  in mcp-shared.json.
- Editing active config: edit in this repo. `.rmux.conf` reloads with
  `prefix + r`; files under `archive/` are inert.
- Wiki changes: keep `wiki/` flat, add both English and `-zh-CN` pages, update
  `_Sidebar.md`, use source links ending in `.md`, and run `scripts/check.sh wiki`.

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
- Apps/CLIs: RMUX (multiplexer formula auto-installed), SonicTerm (outer
  terminal config linked to `~/.sonicterm/` when present), oh-my-zsh (unattended install),
  Copilot CLI (preserve existing or npm fallback), Claude Code CLI
  (Homebrew cask `claude-code`), `copilot-relay` (npm), and the
  `wakatime/copilot-cli-wakatime` Copilot plugin. `copilot-relay start` runs a
  local proxy on port 4142 that the symlinked `~/.claude/settings.json` points
  Claude Code at.
- Tools: Homebrew (bootstrapped if missing), node/npm, jq, git, and RMUX 0.10.x.
  The profile uses tmux-style config syntax, `pbcopy`, OSC 52, and RMUX's local
  daemon/socket model.
- Fonts (auto-installed): Recursive base/Nerd casks, Symbols Only Nerd Font,
  Noto Color Emoji, plus RecMonoBaker/RecMonoSt.Helens TTFs downloaded from
  `MOSconfig/recursive-code-config` releases into `~/Library/Fonts`.
- Copilot WakaTime upload is handled separately by the official
  `wakatime/copilot-cli-wakatime` Copilot plugin, initialized only after
  Copilot CLI and `~/.wakatime.cfg` are available. The installer removes the
  legacy vendored WakaTime MCP runtime/entries, the legacy Homebrew
  `wakatime-cli`, and the legacy npm `@geeknees/copilot-cli-wakatime` package
  if present; the plugin installs/updates its own `~/.wakatime/wakatime-cli` on
  Copilot session start.
- Shell helper formulae installed for `custom.zsh`: `eza`, `neovim`,
  `autojump`, `zsh-fast-syntax-highlighting`, `zsh-completions`.

## Notes
- Safe to re-run `install.sh` anytime; existing correct links are skipped.
- Backups are created only when a non-matching file/link exists.
- `oh-my-zsh-custom/custom.zsh` shadows oh-my-zsh's default
  `custom/custom.zsh` (which is gitignored upstream and irrelevant here).
- Validate RMUX without touching the live socket using `scripts/check.sh rmux`;
  the check creates a unique `-L` socket and traps `kill-server` on every exit.
- Validate bilingual Wiki pairing and transformed links with
  `scripts/check.sh wiki`. Live publication still requires an initialized Wiki
  repository and a merged `main` commit.
- The `copilot/settings.json` working-tree may show runtime-managed drift; keep
  the documented model/context/effort defaults aligned with smoke checks.
