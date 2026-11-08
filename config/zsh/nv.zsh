# nv: open files in one Neovide window. Accepts FILE:LINE[:COL].
nv() {
  local sock="${NV_SOCKET:-${TMPDIR:-/tmp}/neovide-nv.sock}"
  local arg file line="" cmd="" lit q="'" tries=0
  local -a files

  for arg in "$@"; do
    if [[ ! -e "$arg" && "$arg" =~ ^(.+):[0-9]+:[0-9]+$ ]]; then
      arg="${arg%:*}"
    fi
    if [[ ! -e "$arg" && "$arg" =~ ^(.+):([0-9]+)$ ]]; then
      line="${arg##*:}"
      arg="${arg%:*}"
    fi
    files+=("${arg:a}")
  done

  # --remote-send works even while Neovim waits at a prompt; --remote-expr blocks there.
  if ! { [ -S "$sock" ] && command nvim --clean --headless --server "$sock" \
      --remote-send '<Ignore>' >/dev/null 2>&1; }; then
    # Start empty, then send the files: Neovim startup plugins can replace file arguments.
    rm -f "$sock"
    open -n -a Neovide --args --chdir "$PWD" -- --listen "$sock"
    until [ -S "$sock" ] && command nvim --clean --headless --server "$sock" \
        --remote-send '<Ignore>' >/dev/null 2>&1; do
      (( ++tries > 50 )) && { print -u2 "nv: Neovide did not start"; return 1; }
      sleep 0.2
    done
  fi

  for file in "${files[@]}"; do
    lit="${file//$q/$q$q}"
    lit="${lit//</<lt>}"
    cmd+="execute 'drop ' . fnameescape('${lit}') | "
  done
  [ -n "$line" ] && cmd+="${line} | "
  if [ -n "$cmd" ]; then
    command nvim --clean --headless --server "$sock" \
      --remote-send "<C-\\><C-N>:${cmd% | }<CR>"
  fi
  open -a Neovide
}
