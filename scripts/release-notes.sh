#!/usr/bin/env bash
set -euo pipefail

repo_root="${RELEASE_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
current_tag="${1:-${GITHUB_REF_NAME:-}}"
output="${2:-release-notes.md}"

if [ -z "$current_tag" ]; then
  echo "usage: $0 tag [output-file]" >&2
  exit 2
fi

git -C "$repo_root" rev-parse -q --verify "refs/tags/${current_tag}" >/dev/null || {
  echo "tag not found: $current_tag" >&2
  exit 1
}

current_commit="$(git -C "$repo_root" rev-list -n 1 "$current_tag")"
previous_tag="$(git -C "$repo_root" describe --tags --abbrev=0 --match 'v*.*.*' "${current_commit}^" 2>/dev/null || true)"

if [ -n "$previous_tag" ]; then
  range="${previous_tag}..${current_tag}"
  heading="Changes since ${previous_tag}"
else
  range="$current_tag"
  heading="Changes"
fi

commit_list="$(git -C "$repo_root" log --reverse --format='- %s' "$range")"
{
  printf '## %s\n\n' "$heading"
  if [ -n "$commit_list" ]; then
    printf '%s\n' "$commit_list"
  else
    printf '%s\n' '- No commits.'
  fi
} >"$output"
