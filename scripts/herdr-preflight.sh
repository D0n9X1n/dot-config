#!/usr/bin/env bash
# Owner-home preflight for install.sh. Usage: scripts/herdr-preflight.sh <journal-out>
# Lists every path install.sh may write, link, copy or delete (its footprint), writes those paths to
# <journal-out> (one per line, for live_journal), and exits 1 if any is unsafe. It changes nothing.
# Refused: an overlay (DOT_CONFIGS_LOCAL or local/), a .bak.<digits> backup at a destination, a link
# that resolves outside this repo's worktrees, a symlink at a merged or rendered destination, a file or
# folder at a link row that differs from its source (live Herdr settings/keys excepted: install keeps
# their values), and a folder at a copy destination.
root="$(cd "$(dirname "$0")/.." && pwd -P)"
journal="${1:?usage: scripts/herdr-preflight.sh <journal-out>}"
bad=0
: >"$journal"
DOT_CONFIGS_INSTALL_LIB_ONLY=1 source "$root/install.sh" >/dev/null 2>&1
set +e -u -o pipefail

no() { echo "REFUSE $1"; bad=1; }
[ -z "${DOT_CONFIGS_LOCAL:-}" ] || no "overlay: DOT_CONFIGS_LOCAL=$DOT_CONFIGS_LOCAL"
[ ! -e "$root/local" ] || no "overlay: $root/local exists"

roots="$(git -C "$root" worktree list --porcelain | sed -n 's/^worktree //p' |
  while IFS= read -r r; do (cd "$r" 2>/dev/null && pwd -P); done)"
inside() {
  local r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    case "$1" in "$r"/*) return 0 ;; esac
  done <<<"$roots"
  return 1
}
names() { sed -n "s/^  local $1=\"\\(.*\\)\"\$/\\1/p" "$root/install.sh"; }

targets() {
  awk -F'\t' -v h="$HOME" '$1 ~ /^(link|copy|merge|render)$/ { print $1 "\t" $2 "\t" h "/" $3 }' "$root/config/manifest.tsv"
  firefox_profiles 2>/dev/null | while IFS= read -r p; do
    awk -F'\t' -v p="$p" '$1 == "firefox" { print "firefox\t" $2 "\t" p "/" $3 }' "$root/config/manifest.tsv"
  done
  printf 'merge\t-\t%s\n' "$HOME/.claude.json" "$HOME/.wakatime.cfg"
  local n
  for n in $(names agents); do printf 'legacy\t-\t%s\n' "$HOME/.claude/agents/$n.md"; done
  for n in $(names skills); do printf 'legacy\t-\t%s\n' "$HOME/.claude/skills/$n"; done
  printf 'legacy\t-\t%s\n' "$HOME/.claude/feature-crew.sha256" "$HOME/.gitignore" "$HOME/.copilot/AGENTS.md" \
    "$HOME/.claude/hooks" "$HOME/.local/share/wakatime-mcp" \
    "$HOME"/Library/LaunchAgents/com.d0n9x1n.copilot-{api,bridge}.plist "$HOME"/.oh-my-zsh/custom/zzz-local-*.zsh \
    "$root"/config/herdr/user/{settings,keys}.json \
    "$HOME/.local/state/dot-configs/copy-manifest" "$HOME/.local/state/dot-configs"
  # Each mod folder a copy row fills; rollback removes one it created.
  awk -F'\t' -v h="$HOME" '$1 == "copy" { d = h "/" $3; sub(/\/[^\/]*$/, "", d); if (!seen[d]++) print "legacy\t-\t" d }' \
    "$root/config/manifest.tsv"
}

while IFS=$'\t' read -r type src t; do
  case "$t" in *'*'*) continue ;; esac
  printf '%s\n' "$t" >>"$journal"
  [ "$type" = legacy ] && continue
  if [ "$type" = copy ] && ! copy_dest_ok "$t"; then
    no "linked folder on the way to a copy destination: $t"
    continue
  fi
  for b in "$t".bak.[0-9]*; do
    if [ -e "$b" ] || [ -L "$b" ]; then no "backup: $b"; fi
  done
  if [ -L "$t" ]; then
    r="$(readlink -f "$t" 2>/dev/null || readlink "$t")"
    echo "link: $t -> $r"
    case "$type" in
      link|copy|firefox) inside "$r" || no "link resolves outside this repo: $t" ;;
      *) no "symlink at a written destination: $t" ;;
    esac
  elif [ -d "$t" ]; then
    case "$type" in
      copy) no "folder at a copy destination: $t" ;;
      link|firefox) no "differs: $t" ;;
      *) no "folder at a written destination: $t" ;;
    esac
  elif [ -e "$t" ]; then
    echo "replace ($type): $t"
    case "$type:$t" in link:*/.config/herdr-app/settings.json|link:*/.config/herdr-app/keys.json) continue ;; esac
    if [ "$type" = link ] || [ "$type" = firefox ]; then
      cmp -s "$t" "$root/$src" || no "differs: $t"
    fi
  else
    echo "create: $t"
  fi
done < <(targets)

# Not journaled: the Dock icon (a Finder custom icon on Apollo.app's bundle root), which install sets
# only when missing; scripts/set-app-icon.sh --remove takes it off.
if app="$(apollo_app_path 2>/dev/null)"; then echo "dock icon: may set the Apollo icon on $app (not journaled)"; fi
exit "$bad"
