# uu [install.sh options]
#
# Update this machine from dot-configs: fast-forward the checkout to its
# upstream branch, then run ./install.sh to apply the synced settings.
#
# Notes:
# - The checkout is found through this file's installed link, so a clone in
#   any folder works. DOT_CONFIGS_DIR overrides it.
# - A local overlay (DOT_CONFIGS_LOCAL, or local/ in the checkout) that is its
#   own Git repo is fast-forwarded too. See the Customization Wiki page.
# - Refuses a dirty tree, a detached HEAD, or a branch with no upstream, and
#   never merges or rebases: local work is left untouched.
# - Works the same on Apple silicon and Intel Macs; install.sh finds Homebrew
#   in /opt/homebrew or /usr/local.

# While a file is sourced, zsh sets $0 to its path; :A resolves the link.
typeset -g _DOT_CONFIGS_UU_ROOT="${0:A:h:h:h}"

unfunction _dot_configs_uu_ready _dot_configs_uu_pull 2>/dev/null

# Check that a checkout can fast-forward safely; print why not.
function _dot_configs_uu_ready {
  emulate -L zsh
  local repo="$1" branch
  if [[ -n "$(command git -C "$repo" status --porcelain --untracked-files=no)" ]]; then
    print -u2 "uu: $repo has uncommitted changes; commit or stash them first"
    return 1
  fi
  if ! branch="$(command git -C "$repo" symbolic-ref --quiet --short HEAD)"; then
    print -u2 "uu: $repo is on a detached HEAD; switch to a branch first"
    return 1
  fi
  if ! command git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    print -u2 "uu: branch $branch in $repo has no upstream; run git branch --set-upstream-to"
    return 1
  fi
}

function _dot_configs_uu_pull {
  emulate -L zsh
  local repo="$1" branch upstream before after
  branch="$(command git -C "$repo" symbolic-ref --quiet --short HEAD)"
  upstream="$(command git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')"
  before="$(command git -C "$repo" rev-parse --short HEAD)"
  print "uu: syncing $repo ($branch from $upstream)"
  command git -C "$repo" pull --ff-only --quiet || {
    print -u2 "uu: cannot fast-forward $branch to $upstream; resolve it in $repo"
    return 1
  }
  after="$(command git -C "$repo" rev-parse --short HEAD)"
  if [[ "$before" == "$after" ]]; then
    print "uu: already at $after"
  else
    print "uu: updated $before..$after"
    command git -C "$repo" --no-pager log --format='  %h %s' "$before..$after"
  fi
}

unalias uu 2>/dev/null
unfunction uu 2>/dev/null
function uu {
  emulate -L zsh
  local repo="${DOT_CONFIGS_DIR:-$_DOT_CONFIGS_UU_ROOT}"
  local overlay=""

  if [[ ! -x "$repo/install.sh" ]] || ! command git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    print -u2 "uu: no dot-configs checkout at $repo (set DOT_CONFIGS_DIR)"
    return 1
  fi
  # Only an overlay with its own .git is synced here; a fork's tracked local/
  # moves with the checkout itself.
  [[ -e "${DOT_CONFIGS_LOCAL:-$repo/local}/.git" ]] && overlay="${DOT_CONFIGS_LOCAL:-$repo/local}"

  _dot_configs_uu_ready "$repo" || return 1
  if [[ -n "$overlay" ]]; then
    _dot_configs_uu_ready "$overlay" || return 1
  fi
  _dot_configs_uu_pull "$repo" || return 1
  if [[ -n "$overlay" ]]; then
    _dot_configs_uu_pull "$overlay" || return 1
  fi

  (cd "$repo" && ./install.sh "$@") || {
    print -u2 'uu: install.sh failed; see ~/Library/Logs/dot-configs-install.log'
    return 1
  }
  print 'uu: done. Open a new terminal tab to load updated shell files.'
}
