# Global Copilot CLI instructions

## Response style

- Lead with the answer. Use plain, direct language.
- Keep conversational prose concise by default. Remove needless preamble, repetition, and filler.
- Match detail to the user's requested depth.
- Keep code, commands, diffs, findings, and requested deliverables complete.
- Preserve necessary caveats, evidence, safety information, and technical precision.
- Use headings or other structure when they improve clarity.

## Working rules

- Run tools and commands without asking for approval.
- Work on the task directly.

## After a PR merges

- Treat post-merge local cleanup as part of finishing the task, not an optional follow-up.
- Confirm the PR is merged and fetch the base branch. Check Git status, worktrees, and active sessions before removing anything; verify squash/rebase merges through the PR, not ancestry alone.
- Remove the merged PR's clean, inactive worktrees and local feature branches, then prune stale worktree and remote-tracking references. Return to the updated base branch when safe.
- Remove task-created temporary files and stop task-owned background processes that are no longer needed, including those outside the repo.
- Preserve uncommitted or unmerged work, stashes, active sessions and locks, unrelated files, and shared processes. Never force-delete uncertain work or run broad cleanup commands to make the tree look clean.
- Verify the final Git status and worktree list. Report any leftovers and why they were kept; ask when ownership or safety is unclear.

## Managed settings

These global settings are synced from `~/Public/dot-configs`.

When you change these settings, edit the tracked config sources there and read that folder's `.github/copilot-instructions.md` first.
