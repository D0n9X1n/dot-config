#!/usr/bin/env python3
import errno
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "config/zsh/terminal-keys.zsh"
ZSH = shutil.which("zsh")

SCRIPT = r'''
setopt multibyte
unset HISTFILE
if [[ "$PROBE_KEYMAP" == viins ]]; then bindkey -v; else bindkey -e; fi
source "$PROBE_SOURCE" || exit
source "$PROBE_SOURCE" || exit
_probe_init() {
  BUFFER="$PROBE_BUFFER"
  CURSOR="$PROBE_CURSOR"
  print -r -- '__TERMINAL_KEYS_READY__'
}
_probe_finish() {
  print -rn -- "$BUFFER" > "$PROBE_RESULT"
  print -r -- "$CURSOR" > "$PROBE_POSITION"
  BUFFER=''
  zle .accept-line
}
zle -N _probe_init
zle -N _probe_finish
bindkey -M emacs '^]' _probe_finish
bindkey -M viins '^]' _probe_finish
bindkey -M vicmd '^]' _probe_finish
result=''
vared -M "$PROBE_KEYMAP" -i _probe_init result
'''


class TerminalKeysTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if ZSH is None:
            raise RuntimeError("zsh is required to verify terminal key bindings")

    def edit_buffer(self, keymap, text, cursor, keys=b"\x1b[127;9u"):
        # A private vared editor captures BUFFER without ever evaluating the test text as a command.
        with tempfile.TemporaryDirectory(prefix="zsh-terminal-keys-") as temporary:
            root = Path(temporary)
            environment = dict(os.environ)
            environment.update({
                "TERM": "xterm-256color",
                "LC_ALL": "en_US.UTF-8" if os.uname().sysname == "Darwin" else "C.UTF-8",
                "PROBE_SOURCE": str(SOURCE),
                "PROBE_KEYMAP": keymap,
                "PROBE_BUFFER": text,
                "PROBE_CURSOR": str(cursor),
                "PROBE_RESULT": str(root / "buffer"),
                "PROBE_POSITION": str(root / "cursor"),
            })
            pid, master = pty.fork()
            if pid == 0:
                os.execve(ZSH, [ZSH, "-dfc", SCRIPT], environment)
            output = bytearray()
            sent = False
            reaped = False
            eof = False
            try:
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline:
                    readable, _, _ = select.select([] if eof else [master], [], [], 0.1)
                    if readable:
                        try:
                            data = os.read(master, 4096)
                        except OSError as error:
                            if error.errno != errno.EIO:
                                raise
                            data = b""
                        output.extend(data)
                        if not sent and b"__TERMINAL_KEYS_READY__" in output:
                            os.write(master, keys + b"\x1d")
                            sent = True
                        if not data:
                            eof = True
                    finished, status = os.waitpid(pid, os.WNOHANG)
                    if finished:
                        reaped = True
                        self.assertEqual(os.waitstatus_to_exitcode(status), 0, output.decode(errors="replace"))
                        break
                if not reaped:
                    finished, status = os.waitpid(pid, os.WNOHANG)
                    if finished:
                        reaped = True
                        self.assertEqual(os.waitstatus_to_exitcode(status), 0, output.decode(errors="replace"))
                self.assertTrue(reaped, "isolated ZLE did not exit within its deadline")
                self.assertTrue(sent, output.decode(errors="replace"))
                return (root / "buffer").read_text(), int((root / "cursor").read_text())
            finally:
                if not reaped:
                    try:
                        os.killpg(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    os.waitpid(pid, 0)
                os.close(master)

    def test_deletes_before_cursor_without_suffix_loss(self):
        for keymap in ("emacs", "viins"):
            with self.subTest(keymap=keymap):
                self.assertEqual(self.edit_buffer(keymap, "alpha beta tail", 10), (" tail", 0))

    def test_empty_start_end_unicode_and_logical_line_boundaries(self):
        cases = [
            ("", 0, "", 0),
            ("keep tail", 0, "keep tail", 0),
            ("alpha beta", 10, "", 0),
            ("你好 café 尾巴", len("你好 café"), " 尾巴", 0),
            ("first line\nsecond tail", len("first line\nsecond"), "first line\n tail", len("first line\n")),
        ]
        for keymap in ("emacs", "viins"):
            for text, cursor, expected, position in cases:
                with self.subTest(keymap=keymap, text=text, cursor=cursor):
                    self.assertEqual(self.edit_buffer(keymap, text, cursor), (expected, position))

    def test_source_preserves_mode_and_existing_control_keys(self):
        # Repeated sourcing must not switch vi/emacs mode or repurpose existing shell editing keys.
        script = r'''
if [[ "$1" == viins ]]; then bindkey -v; else bindkey -e; fi
before=$(bindkey -lL main)
controls=$(bindkey -M "$1" '^U'; bindkey -M "$1" '^[^?'; bindkey -M "$1" '^H'; bindkey -M vicmd '^?')
source "$2" || exit
source "$2" || exit
[[ "$(bindkey -lL main)" == "$before" ]] || exit 1
[[ "$(bindkey -M "$1" '^U'; bindkey -M "$1" '^[^?'; bindkey -M "$1" '^H'; bindkey -M vicmd '^?')" == "$controls" ]] || exit 2
[[ "$(bindkey -M "$1" $'\e[127;9u')" == *' backward-kill-line' ]] || exit 3
'''
        for keymap in ("emacs", "viins"):
            with self.subTest(keymap=keymap):
                result = subprocess.run([ZSH, "-dfc", script, "probe", keymap, str(SOURCE)], capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
