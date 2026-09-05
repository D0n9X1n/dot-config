# Copilot Instructions

Read `wiki/README.md` first.

The Wiki is the full source of truth for this repo. Do not copy its full help into this file.

## Repo map

- `config/` has config used now.
- `archive/` has old files. Never link it.
- `scripts/` has code that runs and external release pins.
- `wiki/` has all full help.
- `install.sh` stays at the root.

`config/manifest.tsv` is the install list. A new managed file needs a manifest row.

Tool-required files stay at fixed paths: `.claude/CLAUDE.md`, `.github/copilot-instructions.md`, `.github/workflows/*.yml`, `.gitignore`.

## Instruction scope

`config/` holds the globally synced config for every project. Globals keep reusable behavior plus one conditional pointer back here. Anything repo-only stays in this file.

## Model policy

Keep native client names. Claude Code uses `claude-sonnet-5[1m]` and `claude-haiku-4-5-20251001`.

The relay maps every non-Opus route through `gptModel` to `gpt-6-astra`. Opus stays separate as `claude-opus-5`.

Do not replace a client identity with GPT. Never put a GPT id or a display override name back into Claude settings. Keep Sonnet and Opus model families separate.

Copilot CLI keeps its own `gpt-6-astra` settings. Do not align it with the Claude client ids.

## Before an edit

Read the matching Wiki page. Use `wiki/Development-and-Releases.md` for checks, Wiki publish, issues, tags, and releases.

Keep English and `-zh-CN` pages together. Keep the root README short.

Keep the status-line layout and cache aligned. Preserve the documented provider metrics and live-subagent differences.

Launchd files under `config/launchd/` are templates. Run `install.sh` to render them.

## Check

```sh
scripts/check.sh all
```

For config changes, run `./install.sh` twice after checks pass.

## Safety

This repo is public. Do not commit tokens, keys, auth files, logs, runtime state, SonicTerm save locks, or `.claude/worktrees/`.

Do not force-push. Do not use `--no-verify` unless the user asks.
