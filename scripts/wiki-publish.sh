#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${1:-${repo_root}/wiki}"
wiki_repo="${2:-${repo_root}/wiki-repo}"
remote_url="${WIKI_REMOTE_URL:-}"
source_sha="${GITHUB_SHA:-}"

if [ -z "$remote_url" ]; then
  [ -n "${GH_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] || {
    echo "GH_TOKEN and GITHUB_REPOSITORY are required" >&2
    exit 2
  }
  remote_url="https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.wiki.git"
fi

if [ -e "$wiki_repo" ]; then
  [ -d "${wiki_repo}/.git" ] || {
    echo "Wiki checkout is not a Git repository: $wiki_repo" >&2
    exit 2
  }
  if ! git -C "$wiki_repo" diff --quiet || ! git -C "$wiki_repo" diff --cached --quiet; then
    echo "Wiki checkout has tracked local changes: $wiki_repo" >&2
    exit 1
  fi
  git -C "$wiki_repo" pull --ff-only
else
  if ! git clone "$remote_url" "$wiki_repo"; then
    echo "Open the GitHub Wiki once, then run the job again." >&2
    exit 1
  fi
fi

if [ -z "$source_sha" ]; then
  source_sha="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf 'local')"
fi
short_sha="$(printf '%s' "$source_sha" | cut -c1-7)"
rendered="$(mktemp -d)"
trap 'rm -rf "$rendered"' EXIT INT TERM

"${repo_root}/scripts/wiki-render.sh" "$source_dir" "$rendered"
find "$wiki_repo" -maxdepth 1 -type f -name '*.md' -delete
cp "$rendered"/*.md "$wiki_repo/"

git -C "$wiki_repo" add -A -- '*.md'
if git -C "$wiki_repo" diff --cached --quiet -- '*.md'; then
  echo "Wiki already matches wiki/; nothing to publish"
  exit 0
fi

git -C "$wiki_repo" \
  -c user.name="github-actions[bot]" \
  -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -m "Publish wiki from ${short_sha}

Source of truth is wiki/ in the code repository. Browser edits are
overwritten on the next publish."
git -C "$wiki_repo" push origin HEAD
