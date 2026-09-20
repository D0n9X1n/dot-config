#!/usr/bin/env python3
import fcntl
import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time


def check_mode(request_extended):
    rmux = shutil.which('rmux')
    if not rmux:
        raise SystemExit('rmux is required for keyboard tests')
    root = Path(__file__).resolve().parents[2]
    env = {k: v for k, v in os.environ.items() if k not in ('RMUX', 'RMUX_PANE', 'TMUX', 'TMUX_PANE')}
    env.update(TERM='xterm-256color', TERM_PROGRAM='SonicTerm', COLORTERM='truecolor')
    socket = f'terminal-input-{os.getpid()}'

    def command(*args):
        return subprocess.check_output([rmux, '-L', socket, *args], env=env, text=True).rstrip('\n')

    with tempfile.TemporaryDirectory(prefix='rmux-keyboard-') as tmp:
        tmp = Path(tmp)
        received = tmp / 'received'
        ready = tmp / 'ready'
        reader = '''import os, sys, tty
from pathlib import Path
tty.setraw(0)
if sys.argv[3] == '1':
    os.write(1, b"\\x1b[>4;2m")
Path(sys.argv[2]).touch()
with open(sys.argv[1], 'ab', buffering=0) as output:
    while True:
        output.write(os.read(0, 1024))
'''
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 32, 160, 0, 0))
        client = None
        screen = bytearray()

        def pump():
            if select.select([master], [], [], 0.05)[0]:
                data = os.read(master, 65536)
                screen.extend(data)
                if b'\x1b[6n' in data:
                    os.write(master, b'\x1b[1;1R')

        def wait_for(predicate, description):
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                if predicate():
                    return
                pump()
            raise AssertionError(description)

        try:
            invocation = shlex.join([sys.executable, '-c', reader, str(received), str(ready), str(int(request_extended))])
            command('-f', str(root / 'config/rmux/rmux.conf'), 'new-session', '-d', '-s', 'keyboard', invocation)
            client = subprocess.Popen([rmux, '-L', socket, 'attach-session', '-t', 'keyboard'],
                                      stdin=slave, stdout=slave, stderr=slave, env=env)
            os.close(slave)
            slave = None
            wait_for(ready.exists, 'raw reader failed to start')
            wait_for(lambda: b'\x1b[>4;2m' in screen, 'RMUX did not enable modified keys in the outer terminal')
            expected = b''
            shifted_enter = b'\x1b[13;2u' if request_extended else b'\n'
            for sent, forwarded in ((b'\x1b[27;2;13~', shifted_enter),
                                    (b'\x1b[13;2u', shifted_enter),
                                    (b'\r', b'\r'), (b'abc', b'abc')):
                expected += forwarded
                os.write(master, sent)
                wait_for(lambda: received.exists() and len(received.read_bytes()) >= len(expected), 'pane input timed out')
                actual = received.read_bytes()
                assert actual == expected, (sent.hex(), actual.hex(), expected.hex())
            print(f'RMUX keyboard PTY ok: app_extended={request_extended}, Shift+Enter={shifted_enter.hex()}, Enter=0d')
        finally:
            subprocess.run([rmux, '-L', socket, 'kill-server'], env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if client:
                try:
                    client.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    client.terminate()
                    client.wait(timeout=5)
            os.close(master)
            if slave is not None:
                os.close(slave)


if __name__ == '__main__':
    check_mode(False)
    check_mode(True)
