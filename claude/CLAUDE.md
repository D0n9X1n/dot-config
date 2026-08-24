# Global Claude instructions

## Markdown diagrams

When writing Markdown, do not use ASCII-art flowcharts. Use a fenced Mermaid diagram for flowcharts and process diagrams.

## Publishing a GitHub Wiki from an in-repo `wiki/` folder

Use this pattern only when a repository intentionally treats `wiki/` as the source of truth for its GitHub Wiki. Follow repository-specific workflow and naming rules first.

GitHub stores the Wiki tab in a separate repository:

```text
https://github.com/OWNER/REPO.wiki.git
```

Keep reviewable source pages in the main repository under `wiki/`, then publish them with `.github/workflows/publish-wiki.yml`. Publication is one-way: browser edits are overwritten by the next workflow run. Before setup, enable the Wiki feature and create its first page so `REPO.wiki.git` can be cloned.

### Workflow

```yaml
name: Publish wiki

on:
  push:
    branches: [main]
    paths:
      - "wiki/**"
      - ".github/workflows/publish-wiki.yml"
  workflow_dispatch:

permissions:
  contents: write

concurrency:
  group: publish-wiki
  cancel-in-progress: false

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Clone the wiki repository
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          if ! git clone \
            "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.wiki.git" \
            wiki-repo; then
            echo "Initialize the GitHub Wiki with one temporary page, then rerun this workflow." >&2
            exit 1
          fi

      - name: Publish wiki source
        shell: bash
        run: |
          set -euo pipefail

          find wiki-repo -maxdepth 1 -name '*.md' -delete
          cp wiki/*.md wiki-repo/
          cd wiki-repo

          if [ -f README.md ]; then
            mv README.md Home.md
          fi

          sed -i -E 's/\]\(README\.md\)/](Home)/g' ./*.md
          sed -i -E 's/\]\(([A-Za-z0-9_-]+)\.md\)/](\1)/g' ./*.md

          git add -A
          if git diff --cached --quiet; then
            echo "Wiki already matches wiki/; nothing to publish"
            exit 0
          fi

          git -c user.name="github-actions[bot]" \
              -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
              commit -m "Publish wiki from ${GITHUB_SHA::7}

          Source of truth is wiki/ in the code repository. Browser edits are
          overwritten on the next publish."
          git push origin HEAD
```

### Source constraints

- Keep `wiki/` flat unless the workflow deliberately compiles nested sources.
- Use `README.md` as the source landing page; it publishes as `Home.md`.
- Write internal source links as `](Page-Name.md)`.
- Do not write cross-page links as `](Page-Name.md#anchor)` unless the publisher handles them.
- Same-page links such as `](#section)` are fine.
- Keep page filenames within the publisher's supported characters.
- If the project maintains multiple languages, update and validate every language together.
- Prefer tests for flatness, language pairing when applicable, source-link resolution, forbidden cross-page anchors, and the transformed Wiki link graph.

### Completion contract

A merged `wiki/` change is not complete until publication and the live Wiki are verified:

```sh
gh run list --workflow=publish-wiki.yml --limit 3
gh run view <run-id>
gh run view <run-id> --log   # when unsuccessful

git clone https://github.com/OWNER/REPO.wiki.git /tmp/REPO-wiki-live
ls /tmp/REPO-wiki-live
grep -REn '\]\([A-Za-z0-9_-]+\.md\)' /tmp/REPO-wiki-live/*.md
# Expected: no matches.
```

The newest run must correspond to the merged SHA. Open the live Wiki and click representative navigation links, including every maintained language and each added or renamed page.

## Publishing commit-derived GitHub Releases

Use this pattern when a repository releases from semver-style `v*.*.*` tags and wants release information derived from commit subjects. Follow repository-specific versioning and release-note rules first.

```yaml
name: Release

on:
  push:
    tags:
      - 'v*.*.*'

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Generate release notes from commits
        shell: bash
        run: |
          set -euo pipefail

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

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          body_path: release-notes.md
          name: ${{ github.ref_name }}
          draft: false
          prerelease: false
```

Use an annotated new tag and push it explicitly; never move or reuse an existing release tag. The `${current_commit}^` lookup finds the previous reachable tag rather than rediscovering the current tag.

### Release completion contract

A pushed tag is not complete until the workflow and live release are verified:

```sh
gh run list --workflow=release.yml --limit 3
gh run view <run-id>
gh release view vX.Y.Z

git log --reverse --format='- %s' vPREVIOUS..vX.Y.Z
```

The run must correspond to the tag commit. Confirm the live release body has the expected previous-tag heading and exactly the intended chronological commit-subject list.
