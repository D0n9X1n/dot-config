# CLAUDE.md

Read `wiki/README.md` first.

The Wiki is the full source of truth for this repo. Do not copy its full help into this file.

## Repo map

- `config/` has config used now.
- `archive/` has old files. Never link it.
- `scripts/` has code that runs.
- `themes/` has color files.
- `wiki/` has all full help.
- `install.sh` stays at the root.

`config/manifest.tsv` is the install list. A new managed file needs a manifest row.

Tool-required files stay at their fixed paths:

- `.claude/CLAUDE.md`
- `.github/copilot-instructions.md`
- `.github/workflows/*.yml`
- `.gitignore`

## Before an edit

Read the matching Wiki page:

- config and links: `wiki/Repository-Operations.md`
- Claude: `wiki/Claude-Code.md`
- Copilot: `wiki/Copilot-CLI.md`
- RMUX: `wiki/RMUX.md`
- terminal and zsh: `wiki/SonicTerm-and-Shell.md`
- services: `wiki/Services-and-Automation.md`
- checks and release: `wiki/Development-and-Releases.md`

Keep English and `-zh-CN` Wiki pages together.

Keep the status-line layout and cache aligned. Preserve the documented provider metrics and live-subagent differences.

Keep Sonnet and Opus model families separate.

Launchd files under `config/launchd/` are templates. Run `install.sh` to render them.

## Check

```sh
scripts/check.sh all
```

For a config change, run `./install.sh` twice after checks pass. Then verify the links and launchd jobs named in the Wiki.

## Safety

This repo is public.

Do not commit tokens, keys, auth files, logs, runtime state, SonicTerm save locks, or `.claude/worktrees/`.

Do not force-push. Do not use `--no-verify` unless the user asks.
