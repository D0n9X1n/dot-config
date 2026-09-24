# Cmd+Backspace edits the ZLE line without remapping keys sent to terminal applications.
bindkey -M emacs '^[[127;9u' backward-kill-line
bindkey -M viins '^[[127;9u' backward-kill-line
