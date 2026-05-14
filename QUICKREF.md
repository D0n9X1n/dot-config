# QUICKREF

Condensed, machine-readable summary for agents and skim reading. See
`ReadMe.md` for full details.

## Purpose
Personal dotfiles repo. Single source of truth for shell, terminal, and editor
configuration; synced across machines via git + an idempotent installer that
creates symlinks into `$HOME` (and `~/.oh-my-zsh/custom/`).

## Layout
- `install.sh` — macOS entry point; idempotent; safe to re-run.
- `mcp-shared.json` — secret-free MCP entries synced via git. install.sh
  merges into local Copilot mcp.json; the existing pipeline lifts the
  merged set into `~/.claude.json`. Secrets stay per-device.
- `launchd/com.d0n9x1n.copilot-bridge.plist` — macOS launchd agent
  **template** (not symlinked; install.sh renders `__HOME__` -> `$HOME`
  into `~/Library/LaunchAgents/` then `bootout`+`bootstrap` into
  `gui/<uid>`). Starts copilot-bridge proxy on login, restarts on crash,
  logs to `~/Library/Logs/copilot-bridge.{out,err}.log`.
- `.claude/CLAUDE.md` — agent instructions for Claude Code working in
  this repo. Mirrors `.github/copilot-instructions.md`.
- `<repo>/.<name>` — root dotfiles linked to `$HOME/.<name>`. Currently:
  - `.tmux.conf` — primary tab/split/session manager (Gruvbox Dark Hard
    palette, prefix `C-q` (chosen over default C-b for ergonomics — far
    from C-c/d/z, doesn't clash with readline, and modern macOS disables
    the legacy C-q XON flow control), mouse on, top status bar, vim-style
    splits (`prefix + |` / `prefix + -`), 1-indexed windows, OSC 52
    clipboard, TPM + tmux-sensible/yank/resurrect/continuum (continuum
    auto-save every 5 min)). Declares `terminal-features … :RGB` so
    tmux 3.2+ advertises truecolor instead of downsampling to the
    256-color cube. Also
    **scrubs stale terminal-identity env** at server start
    (`set-environment -gu TERMINFO TERMINFO_DIRS TERMCAP TERM_PROGRAM
    TERM_PROGRAM_VERSION` + `set -g COLORTERM truecolor`) so a long-lived
    tmux server that was once started from an uninstalled terminal
    (e.g., Ghostty pointed `$TERMINFO` at its bundle dir) doesn't keep
    failing the `default-terminal "tmux-256color"` lookup forever and
    silently degrade to `xterm-color` (which makes Copilot CLI lose its
    truecolor input panel). **Recovery for an already-poisoned server**:
    close work + save state via `prefix + Ctrl-s`, then `tmux kill-server`
    from a non-tmux shell — next launch picks up the clean env. Bootstrap
    of TPM and plugins is automatic on first tmux start (cloned by the
    `if test ! -d tpm` block, then plugin install runs after the `run
    '~/.tmux/plugins/tpm/tpm'` init line because that line is what sets
    `TMUX_PLUGIN_MANAGER_PATH` in tmux's env). `install.sh` ALSO bootstraps
    TPM + plugins for the install-script path. Validate locally with
    `tmux -f .tmux.conf -L _v new-session -d -s _v ; tmux -L _v kill-server`.
- `<repo>/wezterm/<file>` — **terminal config; NOT auto-linked**. Manually
  opt in with `ln -sfn "$(pwd)/wezterm/wezterm.lua" ~/.wezterm.lua` (the
  `-fn` flags safely overwrite any stale symlink). The `wezterm` cask is
  auto-installed by `install.sh` so the terminal is one symlink away.
  Config uses `color_scheme = "Gruvbox dark, hard (base16)"`,
  `inactive_pane_hsb = {1,1,1}` (no inactive-pane dimming), and the
  custom tab-bar `BAR_BG` is derived from the active scheme so swapping
  schemes auto-aligns the tab strip.
- `<repo>/copilot/<file>` — files linked to `$HOME/.copilot/<file>`. Currently:
  - `settings.json` — Copilot CLI settings (model: `claude-opus-4.7-1m-internal`,
    theme `dark`, `keepAlive: busy`, `continueOnAutoMode: true`, custom
    footer (now hides `showModelEffort` / `showBranch` / `showContextWindow`
    because `statusline.sh` renders them — keeps `showDirectory` and
    `showAgent`), custom status line). The `statusLine` block only
    takes a single `padding` field — per-side spacing is done in
    `statusline.sh` (newlines for top, leading spaces for left). Note:
    Copilot itself injects/strips a `"staff": true` field at runtime based
    on org membership; keep that field out of the committed file to avoid
    spurious diffs.
  - `statusline.sh` — executable script printing the custom status line.
    A "full mirror" of `~/.claude/statusline.sh`: per-segment Gruvbox
    color accents, color-graded Cache % and Context %, and every Claude
    segment reproduced (segments whose data Copilot's statusLine JSON
    doesn't expose silently no-op, so `agent`/`style` cost nothing
    until a future CLI version starts emitting them). Renders these
    segments in order, `<icon> <Label> <value>` separated by `│`:
    Time, Model, Effort (parsed from `model.display_name` `(xhigh)` etc),
    Run, API, Req, Cache, Last, Ctx, Worktree, Repo (clean/dirty
    + ↑↓), Branch, Stash, Venv, GH, Ext, MCP, Diff (enabled by default,
    icon U+F121 angle-brackets). Env overrides:
    `COPILOT_STATUSLINE_NO_ICONS=1` drops icons (keeps text labels);
    `COPILOT_STATUSLINE_NO_COLOR=1` drops color (legacy
    `COPILOT_STATUSLINE_NO_DIM=1` is honored as an alias);
    `COPILOT_STATUSLINE_PAD_TOP=N` / `..._PAD_LEFT=N` / `..._PAD_RIGHT=N`
    override per-side padding (default top=8, left=1, right=0);
    `COPILOT_STATUSLINE_SEGMENTS="…"` overrides the segment list and order.
    The CLI's `statusLine.padding*` fields are silently ignored — only
    `padding` works there, so we emit our own spacing instead. Run
    `~/.copilot/statusline.sh --test` to verify each codepoint renders in
    your terminal (uses `fc-list` if installed). Parses Copilot's session
    JSON from stdin (single `jq` call) and caches `gh auth status` for
    5 min. Bash 3.2-compatible. `install.sh` ensures the executable bit
    is set. v0.6.0: sibling `claude/statusline.sh` warm-cache 125ms→18ms
    via pure-bash JSON parsing (no jq dep), per-cwd git cache (5s TTL
    at `$TMPDIR/claude-statusline-cache-$USER/git-<hash>`), no awk
    forks (`cost`/`ctx`/`fmt_tokens` use bash printf/arith), and
    `printf -v __SEG` instead of per-segment subshells. v0.8.0: multi-line
    layout via literal `\n` token in `SEGMENTS`. v0.13.x: 5-line default —
    L1 time/run/api/cost · L2 model/effort/context · L3 mcp/skills/agents/style ·
    L4 cwd path (new `seg_path`, U+F07C, $HOME→~) · L5 repo/branch/diff/stash/worktree.
    `seg_agent` counts available agent definitions (`*.md` in `~/.claude/agents/`
    + `<cwd>/.claude/agents/`) — NOT live sub-agents (statusline JSON doesn't
    expose runtime sub-agent state). `seg_timer` formats as `Nh Mm` for
    sessions ≥ 1h (v0.13.2). v0.13.3 drops `wall` from the default list.
  - `copilot-instructions.md` — global agent instructions (autonomous mode).
- `<repo>/claude/<file>` — files linked to `$HOME/.claude/<file>`. Currently:
  - `settings.json` — Claude Code → Copilot bridge AND global default-pinning.
    Sets `ANTHROPIC_BASE_URL=http://127.0.0.1:4142`,
    `ANTHROPIC_AUTH_TOKEN=dummy` (copilot-bridge expects the token form,
    not `ANTHROPIC_API_KEY`), and pins **Opus 4.7 1M @ xhigh effort** as the
    global default for every machine that runs `install.sh`:
    `ANTHROPIC_MODEL=claude-opus-4.7-[1m]` AND top-level
    `model=claude-opus-4.7-[1m]` (both required so Claude Code uses it
    on launch with no `/model` toggle; the bracket form is Claude Code's
    UI-friendly alias that copilot-bridge maps to `claude-opus-4.7-1m`
    upstream), `effortLevel="xhigh"` (deepest reasoning client-side, no
    `/effort` needed) plus `MODEL_REASONING_EFFORT=xhigh` (read by
    copilot-bridge per-request and forwarded to Copilot). **Family-aware
    routing** is now done via two env vars instead of the old
    `modelOverrides` map (Sonnet and Opus are still treated as separate
    families per personal convention):
    `ANTHROPIC_DEFAULT_SONNET_MODEL=gpt-5.5` (every Sonnet alias —
    4-5 / 4-6 / Sonnet-1M — routes to `gpt-5.5`, the mid-tier Copilot
    model), `ANTHROPIC_DEFAULT_HAIKU_MODEL=gpt-5.5` (read by current
    Claude Code; covers `Agent({model:"haiku"})` sub-agents and
    every Haiku-tier side-task), and `ANTHROPIC_SMALL_FAST_MODEL=gpt-5.5`
    (legacy alias for the same Haiku/small-fast tier, kept for older
    Claude Code versions that don't yet read `*_DEFAULT_HAIKU_MODEL`).
    Opus aliases just inherit the top-level `model` value.
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
    Requires a local [`betahi-copilot-bridge`](https://www.npmjs.com/package/betahi-copilot-bridge)
    proxy running. The launchd agent runs it as
    `copilot-bridge start --no-claude-setup --no-codex-setup` — those flags
    matter: without them the bridge would rewrite our committed
    `settings.json` (and Codex `config.toml`) on every restart. One-time
    bootstrap on a fresh box: `npm i -g @anthropic-ai/claude-code
    betahi-copilot-bridge && copilot-bridge auth` (browser device-code flow).
    After auth, leave `copilot-bridge start --no-claude-setup --no-codex-setup`
    running and launch `claude` in another shell.
- `<repo>/oh-my-zsh-custom/<file>` — files linked to
  `$HOME/.oh-my-zsh/custom/<file>`. Currently:
  - `custom.zsh` — aliases, proxy helpers (`enable_proxy`/`disable_proxy`),
    brew completions, `PATH` extras (`.NET`, Android SDK).
  - `gg.zsh` — defines `gg <title>` which sets the active terminal's tab +
    window title via OSC 1/2 escapes (works bare in WezTerm, iTerm2, …)
    AND, when `$TMUX` is set, calls `tmux rename-window` so tmux's
    status-bar window name is updated (the OSC 2 escape doesn't
    propagate through tmux because `.tmux.conf` keeps `allow-rename off`
    / `automatic-rename off`; tmux's `set-titles on` then bubbles
    `#S · #W` up to the outer terminal). For WezTerm specifically, also
    calls `wezterm cli set-tab-title` / `set-window-title` (guarded by
    `$WEZTERM_PANE` so it's a no-op when wezterm is on PATH but not the
    active terminal). Sets `DISABLE_AUTO_TITLE=true` so oh-my-zsh hooks
    don't overwrite the title during the session.

## How install.sh works
1. macOS only (auto-installs Homebrew apps and fonts; failures are warnings,
   never fatal — handles deprecated taps and conflicting casks gracefully).
   Set `SKIP_BREW=1` to skip the Homebrew step entirely (useful for CI /
   fake-`HOME` testing). Apps: `wezterm`. Fonts: `font-recursive`,
   `font-recursive-mono-nerd-font`, `font-symbols-only-nerd-font`,
   `font-noto-color-emoji`. Formulae: `tmux`.
2. Symlinks every top-level `.<name>` file in the repo to `$HOME/.<name>`
   (currently `.tmux.conf`; also passes through `.gitignore` and a stray
   `.DS_Store` — both pre-existing, harmless on macOS).
3. Symlinks every file in `oh-my-zsh-custom/` to `~/.oh-my-zsh/custom/`.
   Skipped (with a warning) if `~/.oh-my-zsh/custom/` does not exist.
4. Symlinks every file in `copilot/` to `~/.copilot/`.
   Skipped (with a warning) if `~/.copilot/` does not exist.
5. Symlinks every file in `claude/` to `~/.claude/`. **Creates the
   destination directory if missing** (Claude Code only creates `~/.claude/`
   on first launch).
6. Bootstraps TPM (Tmux Plugin Manager) if `tmux` is on PATH and `~/.tmux.conf`
   is present: clones `~/.tmux/plugins/tpm` if missing, then runs
   `tpm/bin/install_plugins` which spins up the default tmux server, loads
   `.tmux.conf` (which exports `TMUX_PLUGIN_MANAGER_PATH` via the tpm init
   line), and clones the plugins listed in `.tmux.conf`. Idempotent.
7. Existing destination files/links that don't match are renamed to
   `<name>.bak.YYYYMMDDHHMMSS` before linking.
8. Correct symlinks are left alone (no-op).

## Adding a new config
- New `~/.something` dotfile: drop `.something` at repo root, run `install.sh`.
- New oh-my-zsh customization: add a `*.zsh` file to `oh-my-zsh-custom/`,
  run `install.sh`. oh-my-zsh auto-loads files in alphabetical order.
- New Copilot CLI config: add a file to `copilot/`, run `install.sh`.
  Note: `mcp-config.json` is excluded (contains secrets) — manage it manually.
- New Claude Code config: add a file to `claude/`, run `install.sh`.
  The destination directory is created automatically.
- New synced MCP server (secret-free): add to `mcp-shared.json`,
  run `install.sh`. Merged into the local Copilot mcp.json (shared
  wins on collision), then imported into `~/.claude.json` so both tools
  see it. Secret-bearing MCPs (PATs, API keys) go in the gitignored
  `~/.config/github-copilot/mcp.json` per device — install.sh's merge
  preserves them. **GitHub MCP**: needs Bearer-PAT in `headers`
  (no OAuth/DCR support in the hosted server) — see `_github_template`
  in mcp-shared.json.
- Editing existing config: edit in this repo. Symlinks make changes live
  immediately on every machine (tmux: `prefix + r`; wezterm: auto-reloads).

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
- Apps: WezTerm (terminal — cask auto-installed; config opt-in via symlink).
  oh-my-zsh required only for the `oh-my-zsh-custom/` part; Copilot CLI
  required only for the `copilot/` part. Claude Code CLI + `copilot-bridge`
  (npm globals) required only for the `claude/` part — `copilot-bridge start
  --claude-code` runs a local proxy on port 4142 that the symlinked
  `~/.claude/settings.json` points Claude Code at.
- Tools: tmux ≥ 3.3 (3.6a tested) for the `.tmux.conf` features (TPM,
  OSC-52 set-clipboard, status-format extensions). git for TPM clone.
- Fonts (auto-installed): Recursive (Rec Mono St.Helens — part of the Rec
  Mono variable family), Recursive Mono Nerd Font, Symbols Only Nerd Font,
  Noto Color Emoji.
- Optional brew formulae sourced if present: `autojump`,
  `zsh-fast-syntax-highlighting`, `zsh-completions`.

## Notes
- Safe to re-run `install.sh` anytime; existing correct links are skipped.
- Backups are created only when a non-matching file/link exists.
- `oh-my-zsh-custom/custom.zsh` shadows oh-my-zsh's default
  `custom/custom.zsh` (which is gitignored upstream and irrelevant here).
- Validate the tmux config without polluting your live tmux state:
  `tmux -f .tmux.conf -L _v new-session -d -s _v -x 200 -y 50 ; tmux -L _v kill-server`.
- The `copilot/settings.json` working-tree may show a tiny diff
  (`"padding": 0`) introduced by the Copilot CLI runtime — known noise; do
  not commit it as a real change.
- TPM plugin install: if the auto-bootstrap fails on a fresh box, run
  `prefix + I` inside tmux to retry, or `~/.tmux/plugins/tpm/bin/install_plugins`
  from any shell where tmux can start its default server.
