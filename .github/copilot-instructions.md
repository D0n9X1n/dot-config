# Copilot Instructions

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

Read the matching Wiki page before an edit. Use `wiki/Development-and-Releases.md` for checks, Wiki publish, issues, tags, and releases.

Keep English and `-zh-CN` pages together. Keep the root README short.

Keep the status-line layout and cache aligned. Preserve the documented provider metrics and live-subagent differences. Keep Sonnet and Opus model families separate.

Launchd files under `config/launchd/` are templates. Run `install.sh` to render them.

Run:

```sh
scripts/check.sh all
```

For config changes, run `./install.sh` twice after checks pass.

This repo is public. Do not commit tokens, keys, auth files, logs, runtime state, SonicTerm save locks, or `.claude/worktrees/`.

Do not force-push. Do not use `--no-verify` unless the user asks.
