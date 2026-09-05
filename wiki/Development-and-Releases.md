# Development and releases

English | [简体中文](Development-and-Releases-zh-CN.md)

This page is the source of truth for checks, Wiki publishing, issues, tags, and releases.

## Before a change

Read the Wiki page for the tool you will change. Edit the source under `config/` or `scripts/`, not the installed link in `$HOME`.

Keep the change small. Do not add new behavior that the task does not need.

## Shell rules

Shell scripts use:

```sh
#!/usr/bin/env bash
set -euo pipefail
```

Keep Bash 3.2 support for macOS:

- no associative arrays;
- no `printf '%(...)T'`;
- no Bash `\u` escapes;
- use portable `awk`, `sed`, `grep`, and `find` forms;
- use `stat -f %m` with a `stat -c %Y` fallback when needed.

Status line functions use `printf -v` instead of command substitution when possible.

## Coupled files

When one status line changes, update both:

```text
config/claude/statusline.sh
config/copilot/statusline.sh
```

Keep the same five-line shape, palette, and per-directory Git cache. Keep the provider fields different: Claude shows cost; Copilot shows premium requests and custom live-subagent rows.

Keep these model families separate:

- Sonnet-facing defaults route through `gptModel`.
- Opus names route through `opusModel`.

Do not change both families when the task names only one.

For any user-visible or behavior change, update the matching English and Chinese Wiki pages in the same change. Keep the root README short.

## Local checks

Run everything:

```sh
scripts/check.sh all
```

Focused checks:

```sh
scripts/check.sh smoke
scripts/check.sh apollo
scripts/check.sh apollo-online
scripts/check.sh shellcheck
scripts/check.sh instructions
scripts/check.sh models
scripts/check.sh mcp
scripts/check.sh wiki
scripts/check.sh rmux
```

`models` asserts the tracked model selectors: native client ids in Claude settings and launcher wrappers, Copilot's own GPT-6 Astra settings, and the relay's separate Opus route. `mcp` covers the installer's read-only GitHub MCP override warning.

The status-line layout, cache, and generated palette are shared by both providers, so a change to either script or to the generator is checked by `apollo` and `smoke` together. Provider-specific emphasis still differs: Copilot uses the bright foreground role and keeps the live-subagent rows, Claude does neither. Keep Claude's output unchanged when editing the shared generator.

CI uses the same script:

- macOS runs smoke checks and installs RMUX;
- Ubuntu installs ShellCheck and runs the ShellCheck target.

Ordinary checks do not access the network. `apollo-online` is a maintainer-only check that downloads every pinned upstream file and verifies its SHA-256. Run it whenever `scripts/apollo-releases.tsv` changes.

Do not push while checks are red.

## Wiki source rules

The source lives in the flat `wiki/` folder.

Rules:

- `README.md` is the English home source.
- It publishes as `Home.md`.
- Every English page has one `-zh-CN.md` page.
- Each pair links to each other.
- `_Sidebar.md` links every page once in each language.
- Source links use `Page-Name.md`.
- Do not use cross-page `Page-Name.md#anchor` links.
- Same-page `#anchor` links are fine.

Run:

```sh
scripts/check.sh wiki
```

## Wiki scripts

`scripts/wiki-render.sh` copies source pages to a clean output folder, renames `README.md` to `Home.md`, and removes `.md` from flat internal links.

`scripts/wiki-publish.sh` clones or uses the live Wiki repo, calls the render script, replaces managed Markdown pages, commits only when content changed, and pushes without force.

The workflow is small. It only checks out the repo and calls the publish script.

Browser edits are not a source. The next publish replaces them.

## Wiki completion

A merged Wiki change is not done until the run and live pages are checked:

```sh
gh run list --workflow=publish-wiki.yml --limit 3
gh run view <run-id>
git clone https://github.com/OWNER/REPO.wiki.git /tmp/REPO-wiki-live
grep -REn '\]\([A-Za-z0-9_-]+\.md\)' /tmp/REPO-wiki-live/*.md
```

The newest run must match the merge commit. The grep should find nothing. Open the live Wiki and click new or changed links in both languages.

## Issues and milestones

Every work item needs a GitHub issue. Put the issue in the release milestone. Use closing words in the commit or close the issue after the change reaches `main`.

Before a release:

1. Check that all work-item issues are closed.
2. Check that they belong to the release milestone.
3. Close the milestone when the work is complete.

## Required post-merge cleanup

A merged PR is not complete until its inactive feature branches and temporary
worktrees are cleaned up, or preserved exceptions are explicitly reported.

1. Confirm the PR is merged and fetch the current base branch. Check
   `git status --short`, `git worktree list --porcelain`, and branch ancestry;
   a branch's age or name does not prove its work was merged.
2. Check which sessions own the worktrees and locks. Never remove an active
   worktree or clear another session's lock merely to make cleanup succeed.
3. Switch away from the merged feature branch only in a checkout you own.
   Remove clean, inactive worktrees before deleting their local branches with
   `git branch -d`. Use ordinary `git worktree remove`, not forced removal.
4. Delete the confirmed merged remote branch if it remains, then run
   `git fetch --prune origin`. Keep `main` and genuinely active branches.
5. Report the final working-tree status, remaining branches/worktrees, and any
   preserved exceptions. Remove only disposable build outputs, never credentials,
   runtime state, or another session's files.

Uncommitted changes or unique commits block ordinary deletion. Preserve them in
place, or create and verify a private recovery archive before an explicitly
agreed stale-work cleanup. Do not use forced deletion to bypass these checks.

`git branch -d` relies on ancestry and can refuse a squash/rebase-merged branch.
For that case only, `git branch -D` is permitted after confirming all of these:

- The PR is merged and its merge result is reachable from the current base.
- The local branch tip exactly matches the PR's head commit recorded at merge,
  not the resulting squash/rebase commit. Extra or rewritten local commits mean
  preserve the branch, even when the original PR diff landed.
- All changes from that recorded PR head landed. `git cherry -v main <branch>`
  with no `+` entries confirms per-commit patch equivalence; a multi-commit squash
  may still show `+`, so compare the complete PR diff with its squash commit.

Recheck each branch tip immediately before deletion, including the remote tip;
if it changed or the recorded PR head/equivalence cannot be verified, preserve it.
Never infer safety from a PR being closed, or use this exception to force-remove
a dirty or active worktree.

## Versions

Tags use `vX.Y.Z`:

- patch for a fix;
- minor for a new feature;
- major for a breaking change.

Create a new annotated tag. Never move or reuse a release tag.

```sh
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

## Release notes

`scripts/release-notes.sh` builds notes from commit subjects.

It:

1. resolves the current tag commit;
2. finds the previous reachable `v*.*.*` tag from `${current_commit}^`;
3. uses `git log --reverse --format='- %s'` for oldest-to-newest bullets;
4. writes a first-release fallback when no older tag exists.

The release workflow checks out full history, calls the script, and gives `release-notes.md` to `softprops/action-gh-release@v2`.

## Release completion

A pushed tag is not done until the workflow and live release are checked:

```sh
gh run list --workflow=release.yml --limit 3
gh run view <run-id>
gh release view vX.Y.Z
git log --reverse --format='- %s' vPREVIOUS..vX.Y.Z
```

The run must point at the tag commit. The live body must have the right previous-tag heading and the exact commit subjects in order.

## Safe Git work

- Never commit secrets or runtime files.
- Do not use `--no-verify` unless the user asks.
- Do not force-push.
- Review staged files before a commit.
- Keep unrelated local changes out of the commit.
- Run `git status` before an action that could lose work.

See [Repository operations](Repository-Operations.md) for installed files and local-state boundaries.
