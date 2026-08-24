#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${1:-${repo_root}/wiki}"
output_dir="${2:-}"

if [ -z "$output_dir" ]; then
  echo "usage: $0 [source-dir] output-dir" >&2
  exit 2
fi

source_dir="$(cd "$source_dir" && pwd)"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

if [ "$source_dir" = "$output_dir" ]; then
  echo "source and output folders must be different" >&2
  exit 2
fi

[ -f "${source_dir}/README.md" ] || {
  echo "missing Wiki home page: ${source_dir}/README.md" >&2
  exit 1
}

find "$output_dir" -maxdepth 1 -type f -name '*.md' -delete
cp "$source_dir"/*.md "$output_dir/"
mv "${output_dir}/README.md" "${output_dir}/Home.md"

for page in "$output_dir"/*.md; do
  rendered="${page}.rendered"
  sed -E \
    -e 's/\]\(README\.md\)/](Home)/g' \
    -e 's/\]\(([A-Za-z0-9_-]+)\.md\)/](\1)/g' \
    "$page" >"$rendered"
  mv "$rendered" "$page"
done
