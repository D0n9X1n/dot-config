# Global GitHub publishing guidance

Repository-specific instructions and workflow conventions take precedence over this file.

## Publishing a GitHub Wiki from `wiki/`

Use an in-repository `wiki/` folder only when the project intentionally makes it the reviewable source of truth for the GitHub Wiki. GitHub stores the live Wiki in the separate `https://github.com/OWNER/REPO.wiki.git` repository, which must be enabled and initialized with a first page before CI can clone it.

The publisher should:

- trigger on `main` changes to `wiki/**` or its workflow, plus manual dispatch;
- use `permissions: contents: write`;
- serialize runs with a non-cancelling concurrency group;
- clone `${GITHUB_REPOSITORY}.wiki.git` with `GITHUB_TOKEN` and fail with an initialization hint when cloning is impossible;
- replace managed top-level Markdown pages while preserving `.git`;
- copy `wiki/*.md`, rename `README.md` to `Home.md`, rewrite `README.md` links to `Home` before removing `.md` from other flat links, and push normally without force;
- skip the commit when source and live Wiki already match.

Use this transform order:

```sh
if [ -f README.md ]; then
  mv README.md Home.md
fi
sed -i -E 's/\]\(README\.md\)/](Home)/g' ./*.md
sed -i -E 's/\]\(([A-Za-z0-9_-]+)\.md\)/](\1)/g' ./*.md
```

Source constraints:

- Keep `wiki/` flat unless the workflow deliberately compiles nested sources.
- Use `.md` in source links and omit it in the published Wiki.
- Reject cross-page `.md#anchor` links unless the workflow explicitly transforms them.
- Maintain every language together when the project is multilingual.
- Test source-link resolution and the transformed publication graph.
- Treat browser edits as disposable because the next source publication overwrites them.

A merged Wiki change is not complete until the `publish-wiki.yml` run matches the merged SHA, the live `.wiki.git` has the expected flat pages and no source-style `.md` links, and representative browser navigation works.

```sh
gh run list --workflow=publish-wiki.yml --limit 3
gh run view <run-id>
git clone https://github.com/OWNER/REPO.wiki.git /tmp/REPO-wiki-live
grep -REn '\]\([A-Za-z0-9_-]+\.md\)' /tmp/REPO-wiki-live/*.md
```

## Publishing commit-derived GitHub Releases

Use this pattern when a repository publishes from semver-style `v*.*.*` tags. Follow repository-specific version and release-note rules first.

The release workflow should:

- trigger on pushed `v*.*.*` tags and grant `contents: write`;
- checkout with `fetch-depth: 0` so prior reachable tags and commits exist;
- resolve `current_commit` from the tag;
- find the previous reachable semver tag from `${current_commit}^` so the current tag is excluded;
- generate chronological `git log --reverse --format='- %s'` bullets, with a first-release fallback;
- publish `release-notes.md` using `softprops/action-gh-release@v2`.

Core note generation:

```sh
current_tag="${GITHUB_REF_NAME}"
current_commit="$(git rev-list -n 1 "$current_tag")"
previous_tag="$(git describe --tags --abbrev=0 --match 'v*.*.*' "${current_commit}^" 2>/dev/null || true)"

if [ -n "$previous_tag" ]; then
  range="${previous_tag}..${current_tag}"
  heading="Changes since ${previous_tag}"
else
  range="$current_tag"
  heading="Changes"
fi

commit_list="$(git log --reverse --format='- %s' "$range")"
{
  printf '## %s\n\n' "$heading"
  if [ -n "$commit_list" ]; then
    printf '%s\n' "$commit_list"
  else
    printf '%s\n' '- No commits.'
  fi
} > release-notes.md
```

Create a new annotated tag and push that tag explicitly; never move or reuse an existing release tag. A release is not complete until the workflow run corresponds to the tag commit and the live release body has the expected previous-tag heading and chronological commit subjects.

```sh
gh run list --workflow=release.yml --limit 3
gh run view <run-id>
gh release view vX.Y.Z
git log --reverse --format='- %s' vPREVIOUS..vX.Y.Z
```
