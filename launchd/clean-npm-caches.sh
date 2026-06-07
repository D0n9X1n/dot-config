#!/usr/bin/env bash
set -euo pipefail

# Weekly cleaner for npm's ever-growing, never-auto-pruned caches.
#
# Consumed by the launchd agent com.d0n9x1n.npm-cache-clean (see the sibling
# com.d0n9x1n.npm-cache-clean.plist template), but also safe to run by hand:
#   bash launchd/clean-npm-caches.sh
#
# What it does:
#   1. `npm cache clean --force` — empties ~/.npm/_cacache (npm rebuilds it on
#      the next install; the content is a pure download cache).
#   2. Prunes stale ~/.npm/_npx/<hash> dirs. Each `npx pkg@latest` lays down an
#      independent copy keyed by resolved-deps hash and npm never removes them,
#      so they accumulate. We drop copies whose dir mtime is >14 days old.
#      CAVEAT: macOS usually mounts with `noatime`, so real last-USE time is
#      unavailable — we key off directory MTIME (created/last-modified) as a
#      proxy. Anything wrongly pruned is just re-fetched cheaply on next `npx`;
#      recently-used copies (incl. a version-pinned Playwright MCP) are kept.
#
# Never touches ~/Library/Caches/ms-playwright (the downloaded browser
# binaries) — those are large, persistent, and deliberately kept.

# launchd hands us a minimal environment; make sure npm/node/find resolve on
# both Apple Silicon (/opt/homebrew) and Intel (/usr/local) Homebrew prefixes.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

npm_root="${NPM_CACHE_CLEAN_NPM_ROOT:-${HOME}/.npm}"
npx_dir="${npm_root}/_npx"
max_age_days="${NPM_CACHE_CLEAN_MAX_AGE_DAYS:-14}"
log_file="${NPM_CACHE_CLEAN_LOG:-${HOME}/Library/Logs/npm-cache-clean.log}"
log_max_lines="${NPM_CACHE_CLEAN_LOG_MAX_LINES:-500}"

mkdir -p "$(dirname "$log_file")"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

dir_size() {
  # Human-readable size of $1, or "0B"/"-" if missing.
  if [ -d "$1" ]; then
    du -sh "$1" 2>/dev/null | cut -f1
  else
    printf '%s' "-"
  fi
}

{
  echo "[$(ts)] === npm-cache-clean start ==="

  if ! command -v npm >/dev/null 2>&1; then
    echo "[$(ts)] npm not on PATH ($PATH) — skipping"
    echo "[$(ts)] === npm-cache-clean done (skipped) ==="
  else
    echo "[$(ts)] ~/.npm before: $(dir_size "$npm_root")  (_npx: $(dir_size "$npx_dir"))"

    # 1) npm content cache — official command, safe, self-rebuilds.
    if npm cache clean --force >/dev/null 2>&1; then
      echo "[$(ts)] npm cache clean --force: ok"
    else
      echo "[$(ts)] npm cache clean --force: FAILED (continuing)"
    fi

    # 2) Prune _npx copies older than $max_age_days (by dir mtime).
    pruned=0
    if [ -d "$npx_dir" ]; then
      while IFS= read -r -d '' stale; do
        rm -rf "$stale" && pruned=$((pruned + 1))
      done < <(find "$npx_dir" -mindepth 1 -maxdepth 1 -type d -mtime "+${max_age_days}" -print0 2>/dev/null)
    fi
    echo "[$(ts)] pruned ${pruned} _npx copy(ies) older than ${max_age_days}d"

    echo "[$(ts)] ~/.npm after:  $(dir_size "$npm_root")  (_npx: $(dir_size "$npx_dir"))"
    echo "[$(ts)] === npm-cache-clean done ==="
  fi
} >>"$log_file" 2>&1

# 3) Cap the log so it can't itself become cruft.
if [ -f "$log_file" ]; then
  tail -n "$log_max_lines" "$log_file" >"${log_file}.tmp" 2>/dev/null \
    && mv "${log_file}.tmp" "$log_file" \
    || rm -f "${log_file}.tmp" 2>/dev/null || true
fi

exit 0
