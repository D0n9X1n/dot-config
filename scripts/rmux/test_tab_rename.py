#!/usr/bin/env python3
import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import struct
import subprocess
import tempfile
import termios
import time


def main():
    rmux = shutil.which('rmux')
    if not rmux:
        raise SystemExit('rmux is required for tab rename tests')
    root = Path(__file__).resolve().parents[2]
    env = {k: v for k, v in os.environ.items() if k not in ('RMUX', 'RMUX_PANE', 'TMUX', 'TMUX_PANE')}
    env['TERM'] = 'xterm-256color'
    socket = f'tab-rename-{os.getpid()}'

    def command(*args):
        return subprocess.check_output([rmux, '-L', socket, *args], env=env, text=True).rstrip('\n')

    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 32, 160, 0, 0))
    client = None

    def pump(seconds=0.15):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if select.select([master], [], [], min(0.05, max(0, deadline - time.monotonic())))[0]:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if b'\x1b[6n' in data:
                    os.write(master, b'\x1b[1;1R')

    def wait_for(predicate):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if predicate():
                return
            pump()
        raise AssertionError('terminal state timed out')

    def window_name():
        return command('display-message', '-p', '-t', 'rename', '-F', '#W')

    def open_prompt(key='n'):
        os.write(master, b'\x11' + key.encode())
        pump(0.25)

    try:
        with tempfile.TemporaryDirectory(prefix='rmux-tab-rename-') as tmp:
            marker = Path(tmp) / 'injected'
            command('-f', str(root / 'config/rmux/rmux.conf'), 'new-session', '-d', '-s', 'rename', '/bin/sh')
            client = subprocess.Popen([rmux, '-L', socket, 'attach-session', '-t', 'rename'], stdin=slave, stdout=slave, stderr=slave, env=env)
            os.close(slave)
            slave = None
            wait_for(lambda: command('display-message', '-p', '-t', 'rename', '-F', '#{session_attached}') == '1')
            pump(0.3)
            for key in ('n', ','):
                for initial in (' old name', ' old name', 'plain'):
                    command('rename-window', '-t', 'rename', '--', initial)
                    expected_initial = initial[2:] if initial.startswith((' ', ' ')) else initial
                    assert command('display-message', '-p', '-t', 'rename', '-F', '#{E:@tab-name}') == expected_initial
                    for name in ('custom name', 'next name', 'Unicode 界', '-leading', 'quote " and semi ;', '#{session_name}', f'#(touch {marker})', 'trailing\\'):
                        open_prompt(key)
                        os.write(master, b'\x15' + name.encode() + b'\r')
                        expected = name.replace('\\', '\\\\')
                        try:
                            wait_for(lambda: window_name() == expected)
                        except AssertionError as exc:
                            raise AssertionError(f'{key}: expected {expected!r}, got {window_name()!r}') from exc
                        assert not marker.exists(), 'name executed a shell command'
                        for option in ('window-status-current-format', 'window-status-format'):
                            tab = command('display-message', '-p', '-t', 'rename', '-F', '#{E:' + option + '}')
                            assert f': {expected} #[' in tab, tab
                    command('rename-window', '-t', 'rename', '--', f'#(touch {marker})')
                    open_prompt(key)
                    os.write(master, b'\x1b')
                    pump(0.3)
                    assert window_name() == f'#(touch {marker})'
                    assert not marker.exists(), 'initial name executed a shell command'
                command('rename-window', '-t', 'rename', '--', 'original')
                open_prompt(key)
                os.write(master, b'\x15x" ; set-option -g @rename-injected yes ; rename-window "owned\r')
                expected = 'x" ; set-option -g @rename-injected yes ; rename-window "owned'
                wait_for(lambda: window_name() == expected)
                assert command('show-options', '-gqv', '@rename-injected') == ''
                open_prompt(key)
                os.write(master, b'\x15\r')
                wait_for(lambda: command('display-message', '-p', '-t', 'rename', '-F', '#{==:#{window_name},#{pane_current_command}}') == '1')
                assert window_name()
                assert command('show-window-options', '-t', 'rename', '-v', 'automatic-rename') == 'on'
                open_prompt(key)
                os.write(master, b'\x15custom again\r')
                wait_for(lambda: window_name() == 'custom again')
                assert command('show-window-options', '-t', 'rename', '-v', 'automatic-rename') == 'off'
            other = command('new-window', '-d', '-P', '-F', '#{window_id}', '-t', 'rename', '-n', 'other', '/bin/sh')
            command('rename-window', '-t', other, '--', '')
            wait_for(lambda: command('display-message', '-p', '-t', other, '-F', '#{==:#{window_name},#{pane_current_command}}') == '1')
            assert command('display-message', '-p', '-t', other, '-F', '#W')
            assert command('show-window-options', '-t', other, '-v', 'automatic-rename') == 'on'
            assert window_name() == 'custom again'
            assert command('show-window-options', '-t', 'rename', '-v', 'automatic-rename') == 'off'
            command('new-session', '-d', '-s', 'separate', '-n', 'separate-name', '/bin/sh')
            command('rename-window', '-t', 'separate', '--', '')
            wait_for(lambda: command('display-message', '-p', '-t', 'separate', '-F', '#{==:#{window_name},#{pane_current_command}}') == '1')
            assert command('display-message', '-p', '-t', 'separate', '-F', '#W')
            assert window_name() == 'custom again'
            assert command('show-window-options', '-t', 'rename', '-v', 'automatic-rename') == 'off'
            print('RMUX rename PTY ok: icons, spacing, literal names, cancel, empty-name defaults, and target isolation')
    finally:
        subprocess.run([rmux, '-L', socket, 'kill-server'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
    main()
