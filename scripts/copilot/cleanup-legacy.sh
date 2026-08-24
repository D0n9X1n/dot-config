#!/usr/bin/env bash
set -euo pipefail

copilot_home="${COPILOT_HOME:-${HOME}/.copilot}"
pkg_dir="${copilot_home}/pkg"
logs_dir="${copilot_home}/logs"

detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    *) os="$(printf '%s' "$os" | tr '[:upper:]' '[:lower:]')" ;;
  esac

  case "$arch" in
    arm64 | aarch64) arch="arm64" ;;
    x86_64 | amd64) arch="x64" ;;
  esac

  printf '%s-%s' "$os" "$arch"
}

detect_version() {
  local output version
  output="$(copilot --version 2>/dev/null || true)"
  version="$(printf '%s\n' "$output" | sed -nE 's/.*Copilot CLI ([0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?).*/\1/p' | head -1)"
  [ -n "$version" ] && printf '%s' "$version"
}

current_platform="${COPILOT_CLEANUP_PLATFORM:-$(detect_platform)}"
current_version="${COPILOT_CLEANUP_VERSION:-$(detect_version)}"
current_pkg=""

if [ -n "$current_version" ] && [ -d "${pkg_dir}/${current_platform}/${current_version}" ]; then
  current_pkg="${pkg_dir}/${current_platform}/${current_version}"
fi

removed_pkg=0
removed_logs=0

if [ -n "$current_pkg" ] && [ -d "$pkg_dir" ]; then
  while IFS= read -r -d '' version_dir; do
    [ "$version_dir" = "$current_pkg" ] && continue
    case "$(basename "$version_dir")" in
      [0-9]*.[0-9]*.[0-9]* | [0-9]*.[0-9]*.[0-9]*-*) ;;
      *) continue ;;
    esac
    rm -rf "$version_dir"
    removed_pkg=$((removed_pkg + 1))
  done < <(find "$pkg_dir" -mindepth 2 -maxdepth 2 -type d -print0 2>/dev/null)

  find "$pkg_dir" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null || true
  rm -rf "${pkg_dir}/tmp" 2>/dev/null || true
else
  echo "copilot cleanup: current package not found; skipped package pruning" >&2
fi

find "$copilot_home" -name ".DS_Store" -type f -delete 2>/dev/null || true
rm -f "${copilot_home}"/*.bak.* 2>/dev/null || true

if [ -d "$logs_dir" ]; then
  latest_log="$(find "$logs_dir" -type f -name 'process-*.log' -print 2>/dev/null | sort | tail -1 || true)"
  if [ -n "$latest_log" ]; then
    while IFS= read -r -d '' log_file; do
      [ "$log_file" = "$latest_log" ] && continue
      rm -f "$log_file"
      removed_logs=$((removed_logs + 1))
    done < <(find "$logs_dir" -type f -name 'process-*.log' -print0 2>/dev/null)
  fi
fi

if [ -n "$current_pkg" ]; then
  echo "copilot cleanup: kept ${current_pkg#${HOME}/}; removed ${removed_pkg} legacy package(s), ${removed_logs} old log(s)"
fi

exit 0
