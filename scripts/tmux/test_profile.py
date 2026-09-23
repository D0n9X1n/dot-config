#!/usr/bin/env python3
"""Native tmux profile checks, using only owned sockets, PTYs and a temporary HOME."""
import base64
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import select
import shlex
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import termios
import time
import tty
import unittest

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / 'config/tmux/tmux.conf'
THEME = '''set-option -g status-style "bg=default,fg=default"
set-option -g status-left-style "bg=default,fg=default,bold"
set-option -g status-right-style "bg=default,fg=white"
set-window-option -g window-status-style "bg=black,fg=white"
set-window-option -g window-status-current-style "bg=blue,fg=black,bold"
set-window-option -g window-status-activity-style "bg=black,fg=red,bold"
set-window-option -g window-status-bell-style "bg=red,fg=black,bold"
set-option -g pane-border-style "fg=white"
set-option -g pane-active-border-style "fg=yellow"
set-option -g message-style "bg=yellow,fg=black,bold"
set-option -g message-command-style "bg=blue,fg=black,bold"
set-window-option -g mode-style "bg=yellow,fg=black,bold"
'''


def theme_text():
    source = os.environ.get('TMUX_APOLLO_THEME')
    if not source:
        return THEME
    data = Path(source).read_bytes()
    rows = (line.split('\t') for line in (ROOT / 'scripts/apollo-releases.tsv').read_text().splitlines())
    pin = next(row[5] for row in rows if row[0] == 'tmux')
    if hashlib.sha256(data).hexdigest() != pin:
        raise AssertionError('TMUX_APOLLO_THEME must match the pinned official asset')
    return data.decode()


def raw_reader(received, ready, mode):
    tty.setraw(0)
    if mode != '0':
        os.write(1, f'\x1b[>4;{mode}m'.encode())
    Path(ready).write_text(json.dumps({key: os.environ.get(key) for key in (
        'TERM', 'TERM_PROGRAM', 'COLORTERM', 'FORCE_COLOR', 'TERMINFO', 'TERMINFO_DIRS', 'TERMCAP')}))
    with open(received, 'ab', buffering=0) as output:
        while True:
            data = os.read(0, 4096)
            if not data:
                break
            output.write(data)


def terminal_session():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


class TerminalReplies:
    # Without DA replies native tmux waits five seconds before enabling keys.
    replies = {
        b'\x1b[c': b'\x1b[?1;2c',
        b'\x1b[>c': b'\x1b[>1;0;0c',
        b'\x1b[>q': b'\x1bP>|profile-test\x1b\\',
        b'\x1b[6n': b'\x1b[1;1R',
        b'\x1b[18t': b'\x1b[8;40;160t',
        b'\x1b[14t': b'\x1b[4;640;1280t',
        b'\x1b[?996n': b'\x1b[?997;1n',
        b'\x1b]10;?\x1b\\': b'\x1b]10;rgb:eeee/eeee/eeee\x1b\\',
        b'\x1b]11;?\x1b\\': b'\x1b]11;rgb:1111/1111/1111\x1b\\',
    }
    pattern = re.compile(b'|'.join(re.escape(query) for query in replies))
    retain = max(map(len, replies)) - 1

    def __init__(self):
        self.pending = b''

    def feed(self, data):
        stream = self.pending + data
        output, end = bytearray(), 0
        for match in self.pattern.finditer(stream):
            output.extend(self.replies[match.group()])
            end = match.end()
        self.pending = stream[end:][-self.retain:]
        return bytes(output)


class PrivateTmux:
    def __init__(self, shell='/bin/sh'):
        self.binary = shutil.which('tmux')
        if not self.binary:
            raise unittest.SkipTest('native tmux is not installed')
        self.temp = tempfile.TemporaryDirectory(prefix='tmux-profile-')
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.socket = self.root / 'private.sock'
        self.server = self.client = None
        self.master = None
        self.screen = bytearray()
        self.terminal = TerminalReplies()
        self.env = dict(PATH=os.environ.get('PATH', os.defpath), HOME=str(self.home),
                        XDG_CONFIG_HOME=str(self.home / '.config'), SHELL=shell,
                        TERM='xterm-256color', TERM_PROGRAM='SonicTerm', LANG='en_US.UTF-8',
                        TERMINFO='/deliberately-stale', TERMINFO_DIRS='/deliberately-stale',
                        TERMCAP='deliberately-stale')
        theme = self.home / '.config/tmux-apollo-theme/apollo.tmux'
        theme.parent.mkdir(parents=True)
        theme.write_text(theme_text())
        (self.home / '.tmux.conf').symlink_to(PROFILE)
        self.log = (self.root / 'server.log').open('wb')
        try:
            if not PROFILE.is_file():
                raise AssertionError(f'native profile is missing: {PROFILE}')
            self.server = subprocess.Popen(
                [self.binary, '-D', '-S', str(self.socket), '-f', str(PROFILE)],
                env=self.env, cwd=self.home, stdin=subprocess.DEVNULL,
                stdout=self.log, stderr=self.log, start_new_session=True)
            self.wait(lambda: self.socket.exists(), 'private server did not create its socket')
            info = self.socket.lstat()
            assert stat.S_ISSOCK(info.st_mode) and info.st_uid == os.getuid()
            self.command('new-session', '-d', '-s', 'profile', '-n', 'shell', '-x', '160', '-y', '40')
            assert int(self.command('display-message', '-p', '#{pid}')) == self.server.pid
            self.command('source-file', '-n', str(PROFILE))
            self.command('source-file', str(PROFILE))
            self.window = self.format('#{window_id}')
            self.pane = self.format('#{pane_id}')
        except BaseException:
            self.close()
            raise

    def command(self, *args):
        result = subprocess.run([self.binary, '-N', '-S', str(self.socket), *args],
                                env=self.env, cwd=self.home, capture_output=True, text=True, timeout=5)
        if result.returncode:
            raise AssertionError(f'tmux {args!r}: {result.stderr or result.stdout}')
        return result.stdout.rstrip('\n')

    def format(self, value, target=None):
        return self.command('display-message', '-p', '-t', target or 'profile', value)

    def option(self, name, scope='g', target=None):
        args = ['show-options', '-' + scope + 'v']
        if target:
            args.extend(['-t', target])
        return self.command(*args, name)

    def binding(self, table, key):
        rows = self.command('list-keys', '-T', table, '-F', '#{key_string}\t#{key_command}')
        return dict(row.split('\t', 1) for row in rows.splitlines())[key]

    def pump(self, seconds=0.03):
        if self.master is None:
            select.select([], [], [], seconds)
            return
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if not select.select([self.master], [], [], max(0, deadline - time.monotonic()))[0]:
                return
            try:
                data = os.read(self.master, 65536)
            except OSError as exc:
                if exc.errno == errno.EIO:
                    return
                raise
            if not data:
                return
            self.screen.extend(data)
            reply = self.terminal.feed(data)
            if reply:
                self.send(reply)

    def wait(self, predicate, message):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if predicate():
                return
            if self.server and self.server.poll() is not None:
                raise AssertionError(f'private server exited: {(self.root / "server.log").read_text()}')
            self.pump()
        raise AssertionError(message)

    def attach(self):
        self.master, slave = os.openpty()
        try:
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 160, 0, 0))
            self.client = subprocess.Popen(
                [self.binary, '-N', '-S', str(self.socket), 'attach-session', '-t', '=profile'],
                env=self.env, cwd=self.home, stdin=slave, stdout=slave, stderr=slave,
                preexec_fn=terminal_session)
        finally:
            os.close(slave)
        self.wait(lambda: str(self.client.pid) in self.command('list-clients', '-F', '#{client_pid}').splitlines(),
                  'owned client failed to attach')
        self.wait(lambda: b'\x1b[>4;2m' in self.screen, 'native tmux did not negotiate outer extended keys')
        self.pump(0.05)

    def send(self, data):
        view = memoryview(data)
        while view:
            count = os.write(self.master, view)
            view = view[count:]

    def prompt(self, key='n'):
        self.screen.clear()
        self.send(b'\x11' + key.encode())
        self.wait(lambda: b'(rename-window)' in self.screen, 'rename prompt did not open')

    def rename(self, name, key='n', target=None):
        self.prompt(key)
        self.send(b'\x15' + name.encode() + b'\r')
        self.wait(lambda: self.format('#{window_name}', target) == name.replace('\\', '\\\\'),
                  f'rename lost literal input: {name!r}')
        assert self.format('#{E:@tab-name}', target) == name

    def start_reader(self, mode):
        received, ready = self.root / 'received', self.root / 'ready'
        self.command('respawn-pane', '-k', '-t', self.pane, sys.executable, str(Path(__file__).resolve()),
                     '--reader', str(received), str(ready), str(mode))
        self.wait(ready.exists, 'owned raw reader did not start')
        self.wait(lambda: self.format('#{pane_key_mode}') == ('VT10x' if mode == 0 else f'Ext {mode}'),
                  'pane application keyboard request did not take effect')
        self.attach()
        return received, json.loads(ready.read_text())

    def close(self):
        try:
            if self.server and self.server.poll() is None and self.socket.exists():
                info = self.socket.lstat()
                if stat.S_ISSOCK(info.st_mode) and info.st_uid == os.getuid():
                    self.command('kill-server')
        finally:
            for process in (self.client, self.server):
                if process is None:
                    continue
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=3)
            if self.master is not None:
                os.close(self.master)
                self.master = None
            self.log.close()
            self.temp.cleanup()


class TerminalReplyTests(unittest.TestCase):
    def test_fragmented_terminal_queries(self):
        queries = [(b'\x1b[c', b'\x1b[?1;2c'), (b'\x1b[>c', b'\x1b[>1;0;0c'),
                   (b'\x1b[>q', b'\x1bP>|profile-test\x1b\\'),
                   (b'\x1b[6n', b'\x1b[1;1R'), (b'\x1b[18t', b'\x1b[8;40;160t'),
                   (b'\x1b[14t', b'\x1b[4;640;1280t'), (b'\x1b[?996n', b'\x1b[?997;1n'),
                   (b'\x1b]10;?\x1b\\', b'\x1b]10;rgb:eeee/eeee/eeee\x1b\\'),
                   (b'\x1b]11;?\x1b\\', b'\x1b]11;rgb:1111/1111/1111\x1b\\')]
        for query, reply in queries:
            for split in range(len(query) + 1):
                terminal = TerminalReplies()
                actual = terminal.feed(query[:split]) + terminal.feed(query[split:])
                self.assertEqual(actual, reply, (query, split))
                self.assertEqual(terminal.feed(b'plain output\x1b[>4;2m'), b'')
        terminal = TerminalReplies()
        stream = b'noise'.join(query for query, _ in queries)
        self.assertEqual(b''.join(terminal.feed(bytes([byte])) for byte in stream),
                         b''.join(reply for _, reply in queries))
        self.assertEqual(terminal.feed(b'\x1b[c\x1b[c'), b'\x1b[?1;2c\x1b[?1;2c')


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.tmux = PrivateTmux()
        self.addCleanup(self.tmux.close)

    def test_options_environment_and_bindings(self):
        tm = self.tmux
        for name, expected in {
            'prefix': 'C-q', 'mouse': 'on', 'history-limit': '100000', 'base-index': '1',
            'renumber-windows': 'on', 'set-titles': 'on', 'set-titles-string': '#S · #W',
            'status': 'on', 'status-position': 'bottom', 'status-interval': '5',
            'status-justify': 'left', 'status-left-length': '24', 'status-right-length': '24',
            'status-keys': 'vi', 'default-terminal': 'tmux-256color',
        }.items():
            self.assertEqual(tm.option(name), expected, name)
        for name, expected in {
            'pane-base-index': '1', 'automatic-rename': 'off', 'allow-rename': 'off',
            'automatic-rename-format': '#{pane_current_command}', 'mode-keys': 'vi',
            'monitor-activity': 'on', 'pane-border-status': 'off', 'window-status-separator': ' ',
        }.items():
            self.assertEqual(tm.option(name, 'gw'), expected, name)
        for name, expected in {'extended-keys': 'on', 'extended-keys-format': 'csi-u',
                               'escape-time': '0', 'focus-events': 'on', 'copy-command': 'pbcopy',
                               'set-clipboard': 'on'}.items():
            self.assertEqual(tm.option(name, 's'), expected, name)
        features = tm.command('show-options', '-sv', 'terminal-features')
        self.assertIn('xterm-256color:extkeys:RGB:osc7', features)
        self.assertIn('Smulx=', tm.option('terminal-overrides', 's'))
        source = PROFILE.read_text()
        self.assertNotRegex(source, r'(?m)^\s*(?:run(?:-shell)?\b|.*@plugin|set-environment.*TERM_PROGRAM)')
        root_keys = tm.command('list-keys', '-T', 'root')
        self.assertNotRegex(root_keys, r'-T root\s+(?:Enter|C-m|C-j|C-c|C-q)\s')
        for key, command in {'h': 'select-pane -L', 'j': 'select-pane -D', 'k': 'select-pane -U',
                             'l': 'select-pane -R', 'H': 'resize-pane -L 5', 'J': 'resize-pane -D 3',
                             'K': 'resize-pane -U 3', 'L': 'resize-pane -R 5', 'Tab': 'last-window',
                             'Left': 'previous-window', 'Right': 'next-window', 'C-q': 'send-prefix',
                             '|': 'split-window -h', '-': 'split-window -v', 'c': 'new-window'}.items():
            binding = tm.binding('prefix', key)
            self.assertIn(command, binding, key)
            if key in ('|', '-', 'c'):
                self.assertIn('#{pane_current_path}', binding)
        self.assertIn('select-window -t =', tm.binding('root', 'MouseDown1Status'))
        self.assertIn('select-pane -t =', tm.binding('root', 'MouseDown1Pane'))
        drag = tm.binding('root', 'MouseDrag1Pane')
        self.assertIn('#{||:#{pane_in_mode},#{mouse_any_flag}}', drag)
        self.assertIn('send-keys -M', drag)
        self.assertIn('copy-mode -M', drag)
        for key, action in {'v': 'begin-selection', 'V': 'select-line', 'C-v': 'rectangle-toggle',
                            'y': 'copy-pipe-and-cancel', 'C-c': 'copy-pipe-and-cancel',
                            'MouseDragEnd1Pane': 'copy-pipe-no-clear'}.items():
            self.assertIn(action, tm.binding('copy-mode-vi', key))
        _, environment = tm.start_reader(0)
        self.assertEqual(environment, dict(TERM='tmux-256color', TERM_PROGRAM='tmux', COLORTERM='truecolor',
                                           FORCE_COLOR='3', TERMINFO=None, TERMINFO_DIRS=None, TERMCAP=None))
        self.assertIn('osc7', tm.command('list-clients', '-F', '#{client_termfeatures}'))
        tm.send(b'\x11T')
        tm.wait(lambda: tm.option('mouse') == 'off', 'mouse toggle did not turn off')
        tm.send(b'\x11T')
        tm.wait(lambda: tm.option('mouse') == 'on', 'mouse toggle did not turn on')

    def test_status_matches_rmux_goldens(self):
        tm = self.tmux
        roles = {tokens[-2]: tokens[-1] for line in theme_text().splitlines()
                 if (tokens := shlex.split(line, comments=True))}
        bar = re.search(r'bg=([^,]+)', roles['status-style']).group(1)
        bell = roles['window-status-bell-style']
        red = re.search(r'bg=([^,]+)', bell).group(1)
        self.assertEqual(tm.option('status-style'), roles['status-style'])
        for name in ('pane-border-style', 'pane-active-border-style', 'message-style', 'message-command-style', 'mode-style'):
            expected = roles[name]
            if name in ('message-style', 'message-command-style'):
                expected += ',fill=' + re.search(r'bg=([^,]+)', roles[name]).group(1)
            self.assertEqual(tm.option(name), expected)
        cap = f'#[fg={red},bg={bar},nobold]'
        for session, shown in [('profile', 'profile'), ('abcdefghijklmnopqrstuvwxyz', 'abcdefghijklmnopqrs'),
                                ('界' * 12, '界' * 9)]:
            tm.command('rename-session', '-t', tm.format('#{session_id}', tm.pane), session)
            self.assertEqual(tm.format('#{E:status-left}', tm.pane), f'{cap}#[{bell}] {shown} {cap} ')
        tm.command('rename-session', '-t', tm.format('#{session_id}', tm.pane), 'profile')
        self.assertEqual(tm.option('status-right'), ' #{?client_prefix,PREFIX  ,}%H:%M ')
        self.assertRegex(tm.format('#{T:status-right}'), r'^ \d{2}:\d{2} $')
        current_cap = f'#[fg=#365b80,bg={bar},nobold]'
        current = f'{current_cap}#[bg=#365b80,fg=#ffffff,bold] 1: shell'
        self.assertEqual(tm.format('#{E:window-status-current-format}'), f'{current} {current_cap}')
        tm.command('split-window', '-d', '-t', tm.pane, '/bin/sh')
        tm.command('resize-pane', '-Z', '-t', tm.pane)
        self.assertEqual(tm.format('#{E:window-status-current-format}'), f'{current} ZOOM {current_cap}')
        tm.command('resize-pane', '-Z', '-t', tm.pane)
        inactive = tm.option('@tab-inactive-style')
        for has_bell, activity in ((0, 0), (0, 1), (1, 0), (1, 1)):
            tm.command('set-option', '-g', '@tab-inactive-style',
                       inactive.replace('window_bell_flag', f'#{{==:{has_bell},1}}')
                       .replace('window_activity_flag', f'#{{==:{activity},1}}'))
            style = roles['window-status-bell-style' if has_bell else
                          'window-status-activity-style' if activity else 'window-status-style']
            if not has_bell:
                style = re.sub(r'bg=[^,]+', f'bg={bar}', style)
            background = re.search(r'bg=([^,]+)', style).group(1)
            edge = f'#[fg={background},bg={bar},nobold]'
            self.assertEqual(tm.format('#{E:window-status-format}'), f'{edge}#[{style}] 1: shell {edge}')
        tm.command('set-option', '-g', '@tab-inactive-style', inactive)
        icon = tm.option('@tab-icon').replace('pane_current_command', '@test-command')
        for app, expected in [('claude', ''), ('copilot', ''), ('nvim', ''), ('vim', ''),
                               ('zsh', ''), ('unknown', '')]:
            tm.command('set-option', '-g', '@test-command', app)
            self.assertEqual(tm.format(icon), expected)
        for name in (' custom name', ' custom name', 'custom name'):
            tm.command('rename-window', '-t', tm.window, name)
            self.assertEqual(tm.format('#{E:@tab-name}'), 'custom name')
            self.assertIn(': custom name #[', tm.format('#{E:window-status-current-format}'))
        tm.attach()
        tm.send(b'\x11')
        tm.wait(lambda: 'PREFIX' in tm.command('display-message', '-p', '-c', str(tm.client.pid), '#{T:status-right}'),
                'PREFIX status indicator missing')
        tm.send(b'q')

    def test_literal_rename_and_cancel(self):
        tm = self.tmux
        tm.attach()
        marker = tm.root / 'injected'
        names = ['custom name', 'Unicode 界 é', '-leading', "quote ' and \" and semi ;", 'trailing\\',
                 r'back\\slash\"quote', '#{session_name}', f'#(touch {marker})', 'hash # ## #[fg=red] literal',
                 '%1 %% %%%', 'comma,second', 'x" ; set-option -g @rename-injected yes ; rename-window "owned']
        for key in ('n', ','):
            for name in names:
                with self.subTest(key=key, name=name):
                    tm.rename(name, key)
                    self.assertFalse(marker.exists(), 'submitted title executed a shell command')
                    for option in ('window-status-format', 'window-status-current-format'):
                        self.assertIn(': ' + name.replace('#', '##') + ' #[', tm.format('#{E:' + option + '}'))
                    self.assertEqual(tm.command('show-options', '-gqv', '@rename-injected'), '')
                    self.assertEqual(tm.command('show-options', '-wqv', '-t', tm.window, '@rename-input'), '')
                    self.assertEqual(tm.option('automatic-rename', 'w', tm.window), 'off')
                    tm.prompt(key)
                    tm.send(b'\r')
                    tm.pump(0.05)
                    self.assertEqual(tm.format('#{window_name}'), name.replace('\\', '\\\\'), 'initial title was reformatted')
                    self.assertFalse(marker.exists(), 'initial title executed a shell command')
            before = tm.format('#{window_name}')
            tm.prompt(key)
            tm.send(b'\x15discard\x07')
            tm.pump(0.08)
            self.assertEqual(tm.format('#{window_name}'), before)
            tm.rename('after C-g', key)
            tm.prompt(key)
            tm.send(b'\x15discard\x1b')
            tm.pump(0.05)
            tm.send(b'q')
            tm.pump(0.05)
            self.assertEqual(tm.format('#{window_name}'), 'after C-g')

    def test_prompt_fill_hides_status_after_editing(self):
        tm = self.tmux
        old_title = 'previous-window-title-' * 4
        tm.command('rename-window', '-t', tm.window, old_title)
        tm.command('set-option', '-g', 'status-right', 'OLD-STATUS-CLOCK')
        tm.attach()
        tm.prompt()
        for keys, expected in ((b'\x15', b'(rename-window)'),
                               (b'hello', b'(rename-window)hello'),
                               (b'\x17', b'(rename-window)'),
                               (b'world\x1b', b'(rename-window)world')):
            tm.screen.clear()
            tm.send(keys)
            tm.wait(lambda: expected in tm.screen, 'prompt edit was not redrawn')
            tm.pump(.05)
            visible = re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]|\x1b\([A-Z]', b'', bytes(tm.screen))
            self.assertNotIn(b'OLD-STATUS-CLOCK', visible, 'status clock leaked into prompt')
            self.assertNotIn(b'window-title', visible, 'old window title leaked into prompt')
            self.assertNotIn(''.encode(), visible, 'status tab slope leaked into prompt')
        tm.send(b'q')
        tm.wait(lambda: b'OLD-STATUS-CLOCK' in tm.screen, 'cancelling did not restore the status bar')
        self.assertEqual(tm.format('#{window_name}'), old_title)
        for option in ('message-style', 'message-command-style'):
            style = tm.option(option)
            background = re.search(r'(?:^|,)bg=([^,]+)', style).group(1)
            self.assertIn('fill=' + background, style)

    def test_rename_targets_and_empty_reset(self):
        tm = self.tmux
        other = tm.command('new-window', '-d', '-P', '-F', '#{window_id}', '-t', '=profile', '-n', 'other', '/bin/sh')
        separate = tm.command('new-session', '-d', '-P', '-F', '#{window_id}', '-s', 'separate', '-n', 'separate-name', '/bin/sh')
        tm.attach()
        tm.prompt()
        tm.command('select-window', '-t', other)
        tm.send(b'\x15original target\r')
        tm.wait(lambda: tm.format('#{window_name}', tm.window) == 'original target', 'prompt renamed the newly selected window')
        self.assertEqual(tm.format('#{window_name}', other), 'other')
        for target in (other, separate):
            tm.command('rename-window', '-t', target, '')
            tm.wait(lambda: tm.format('#{window_name}', target) == tm.format('#{pane_current_command}', target),
                    'empty CLI rename did not restore the target command name')
            self.assertEqual(tm.option('automatic-rename', 'w', target), 'on')
            self.assertEqual(tm.option('automatic-rename', 'w', tm.window), 'off')
            self.assertEqual(tm.format('#{window_name}', tm.window), 'original target')
            self.assertEqual(tm.option('automatic-rename', 'gw'), 'off')
        tm.command('select-window', '-t', tm.window)
        tm.prompt(',')
        tm.send(b'\x15\r')
        tm.wait(lambda: tm.format('#{window_name}') == tm.format('#{pane_current_command}'), 'empty prompt did not reset name')
        self.assertEqual(tm.option('automatic-rename', 'w', tm.window), 'on')
        tm.rename('custom again')
        self.assertEqual(tm.option('automatic-rename', 'w', tm.window), 'off')

    def test_prompt_input_protocols(self):
        tm = self.tmux
        tm.attach()
        for protocol in ('legacy', 'xterm', 'csi-u'):
            def encoded(char, modifier):
                if protocol == 'legacy':
                    return bytes([ord(char) - 96]) if modifier == 5 else char.encode()
                return (f'\x1b[27;{modifier};{ord(char)}~' if protocol == 'xterm'
                        else f'\x1b[{ord(char)};{modifier}u').encode()
            for text in ('FDAS', 'ABCD'):
                tm.prompt()
                tm.send(encoded('u', 5) + b''.join(encoded(char, 2) for char in text) + b'\r')
                tm.wait(lambda: tm.format('#{window_name}') == text, f'{protocol} uppercase prompt text corrupted')
            tm.command('rename-window', '-t', tm.window, 'one two')
            tm.prompt()
            tm.send(encoded('w', 5) + b'X\r')
            tm.wait(lambda: tm.format('#{window_name}') == 'one X', f'{protocol} Ctrl+W prompt editing failed')

    def test_native_shell_exit_detaches_without_ending_pane(self):
        tm = self.tmux
        zsh = shutil.which('zsh')
        if not zsh:
            self.skipTest('zsh is required for the managed shell helpers')
        installed = tm.home / '.local/bin/tmux-store'
        installed.parent.mkdir(parents=True)
        installed.symlink_to(ROOT / 'scripts/tmux/tmux-store')
        (tm.home / '.zshrc').write_text(
            'source ' + shlex.quote(str(ROOT / 'config/zsh/zz-rmux.zsh')) + '\n' +
            'source ' + shlex.quote(str(ROOT / 'config/zsh/zz-tmux.zsh')) + '\n' +
            "PROMPT='TMUX EXIT TEST> '\nRPROMPT=''\nprint -r -- EXIT_HELPER_READY\n")
        tm.command('respawn-pane', '-k', '-t', tm.pane, zsh, '-di')
        pane_pid = tm.format('#{pane_pid}')
        server_pid = tm.format('#{pid}')
        tm.attach()
        tm.wait(lambda: b'EXIT_HELPER_READY' in tm.screen, 'managed shell helpers did not load')
        tm.send(b'exit\r')
        tm.wait(lambda: tm.format('#{session_attached}') == '0', 'exit did not detach the native client')
        tm.client.wait(timeout=5)
        self.assertEqual(tm.format('#{pane_pid}'), pane_pid, 'exit replaced or ended the shell')
        self.assertEqual(tm.format('#{pid}'), server_pid, 'exit restarted the server')
        self.assertEqual(tm.format('#{pane_dead}'), '0')
        os.kill(int(pane_pid), 0)
        os.close(tm.master)
        tm.master = None
        tm.screen.clear()
        tm.attach()
        tm.send(b'print -r -- EXIT_PANE_SURVIVED\r')
        tm.wait(lambda: 'EXIT_PANE_SURVIVED' in tm.command('capture-pane', '-p', '-t', tm.pane),
                'original shell did not survive reattachment')
        self.assertEqual(tm.format('#{pane_pid}'), pane_pid)

    def test_keymap_docs_match_managed_bindings(self):
        tm = self.tmux
        for filename in ('Tmux-Keymap.md', 'Tmux-Keymap-zh-CN.md'):
            document = (ROOT / 'wiki' / filename).read_text()
            for key in ('C-q', 'r', 'n', ',', 'T', 'c', '-', 'h', 'j', 'k', 'l',
                        'H', 'J', 'K', 'L', 'Left', 'Right', 'Tab', 'v', 'z', 'd'):
                self.assertIn('`' + key + '`', document, (filename, key))
                self.assertTrue(tm.binding('prefix', key), key)
            for key in ('v', 'V', 'y', 'q'):
                self.assertTrue(tm.binding('copy-mode-vi', key), key)
            for helper in ('tt NAME', 'tr NAME', 'tl', 'td NAME', 'th', 'ts'):
                self.assertIn('`' + helper + '`', document, (filename, helper))

    def test_osc7_tracks_active_pane(self):
        tm = self.tmux
        ready = tm.root / 'cwd-ready'
        uri = 'file://localhost' + str(tm.home) + '/reported-directory'
        tm.command('respawn-pane', '-k', '-t', tm.pane, sys.executable, '-c',
                   'import os,time; from pathlib import Path; os.write(1, ' + repr(('\x1b]7;' + uri + '\x07').encode()) +
                   '); Path(' + repr(str(ready)) + ').touch(); time.sleep(30)')
        tm.wait(ready.exists, 'OSC7 test app did not start')
        tm.wait(lambda: tm.format('#{pane_path}') == uri, 'OSC7 directory was not recorded for the pane')
        tm.attach()
        tm.wait(lambda: uri.encode() in tm.screen, 'active-pane OSC7 directory did not reach the outer terminal')

    def test_mouse_input_and_osc_clipboard_ownership(self):
        tm = self.tmux
        received, ready = tm.root / 'mouse-input', tm.root / 'mouse-ready'
        reader = '''import os, sys, tty
from pathlib import Path
tty.setraw(0)
os.write(1, b"\\x1b[?1000h\\x1b[?1006h")
Path(sys.argv[2]).touch()
with open(sys.argv[1], 'ab', buffering=0) as output:
    while True:
        output.write(os.read(0, 4096))
'''
        tm.command('respawn-pane', '-k', '-t', tm.pane, sys.executable, '-c', reader, str(received), str(ready))
        tm.wait(ready.exists, 'owned mouse reader failed to start')
        tm.attach()
        mouse = b'\x1b[<0;5;5M\x1b[<0;5;5m'
        tm.send(mouse)
        tm.wait(lambda: received.exists() and mouse in received.read_bytes(), 'application mouse events not forwarded')
        self.assertEqual(tm.format('#{pane_in_mode}'), '0')

        tm.command('set-option', '-s', 'set-clipboard', 'on')
        clipboard = b'tmux-private-clipboard-test'
        payload = base64.b64encode(clipboard)
        tm.command('respawn-pane', '-k', '-t', tm.pane, sys.executable, '-c',
                   'import os,time; os.write(1, ' + repr(b'\x1b]52;c;' + payload + b'\x07') + '); time.sleep(30)')
        tm.wait(lambda: bool(tm.command('list-buffers', '-F', '#{buffer_name}')),
                'OSC52 did not populate the private tmux buffer')
        self.assertEqual(tm.command('save-buffer', '-'), clipboard.decode())
        tm.wait(lambda: payload in tm.screen, 'OSC52 did not reach the synthetic terminal')
        tm.command('set-option', '-s', 'set-clipboard', 'external')
        rejected = base64.b64encode(b'must-not-replace-private-buffer')
        output_ready = tm.root / 'clipboard-rejected'
        tm.command('respawn-pane', '-k', '-t', tm.pane, sys.executable, '-c',
                   'import os,time; from pathlib import Path; os.write(1, ' + repr(b'\x1b]52;c;' + rejected + b'\x07') +
                   '); Path(' + repr(str(output_ready)) + ').touch(); time.sleep(30)')
        tm.wait(output_ready.exists, 'clipboard boundary reader failed')
        tm.pump(.15)
        self.assertEqual(tm.command('save-buffer', '-'), clipboard.decode())

    def test_copy_pipe_does_not_clear_selection(self):
        tm = self.tmux
        copied, ready = tm.root / 'copied', tm.root / 'copy-ready'
        sink = tm.root / 'copy-sink.py'
        sink.write_text('import sys\nfrom pathlib import Path\nPath(sys.argv[1]).write_bytes(sys.stdin.buffer.read())\n')
        tm.command('set-option', '-s', 'copy-command', shlex.join([sys.executable, str(sink), str(copied)]))
        tm.command('respawn-pane', '-k', '-t', tm.pane, sys.executable, '-c',
                   'import os,time; from pathlib import Path; os.write(1,b"COPY-MARKER"); Path(' + repr(str(ready)) + ').touch(); time.sleep(30)')
        tm.wait(ready.exists, 'copy test app did not start')
        tm.attach()
        tm.send(b'\x11v')
        tm.wait(lambda: tm.format('#{pane_in_mode}') == '1', 'copy mode did not start')
        tm.command('send-keys', '-t', tm.pane, '-X', 'start-of-line')
        tm.send(b'v')
        tm.command('send-keys', '-t', tm.pane, '-X', 'end-of-line')
        tm.command('send-keys', '-t', tm.pane, '-X', 'copy-pipe-no-clear')
        tm.wait(copied.exists, 'copy pipe was not invoked')
        self.assertIn(b'COPY-MARKER', copied.read_bytes())
        self.assertEqual(tm.format('#{pane_in_mode}'), '1')
        self.assertEqual(tm.format('#{selection_present}'), '1')
        tm.send(b'q')
        tm.wait(lambda: tm.format('#{pane_in_mode}') == '0', 'copy mode did not exit')

    def test_cwd_splits_and_zsh_default(self):
        tm = self.tmux
        cwd = tm.root / 'working directory'
        cwd.mkdir()
        tm.command('respawn-pane', '-k', '-c', str(cwd), '-t', tm.pane, '/bin/sh')
        tm.wait(lambda: tm.format('#{pane_current_path}') == str(cwd.resolve()), 'owned shell cwd not detected')
        tm.attach()
        for key in ('|', '-'):
            before = tm.command('list-panes', '-t', tm.window, '-F', '#{pane_id}').splitlines()
            tm.send(b'\x11' + key.encode())
            tm.wait(lambda: len(tm.command('list-panes', '-t', tm.window, '-F', '#{pane_id}').splitlines()) == len(before) + 1,
                    'split binding did not make a pane')
            self.assertEqual(tm.format('#{pane_current_path}'), str(cwd.resolve()))
        tm.send(b'\x11c')
        tm.wait(lambda: tm.format('#{window_id}') != tm.window, 'new-window binding did not make a window')
        self.assertEqual(tm.format('#{pane_current_path}'), str(cwd.resolve()))
        zsh = shutil.which('zsh')
        if zsh:
            other = PrivateTmux(shell=zsh)
            self.addCleanup(other.close)
            self.assertEqual(other.option('default-shell'), zsh)
            other.wait(lambda: other.format('#{pane_current_command}') == 'zsh', 'native default shell is not zsh')
            self.assertEqual(other.format('#{E:@tab-icon}'), '')


class KeyboardTests(unittest.TestCase):
    def test_native_byte_paths(self):
        for mode in (0, 1, 2):
            with self.subTest(pane_key_mode=mode):
                tm = PrivateTmux()
                try:
                    received, _ = tm.start_reader(mode)
                    shifted = b'\x1b[13;2u' if mode else b'\n'
                    control = b'\x1b[99;5u' if mode == 2 else b'\x03'
                    alt = b'\x1b[97;3u' if mode == 2 else b'\x1ba'
                    backtab = b'\x1b[9;2u' if mode == 2 else b'\x1b[Z'
                    cases = [(b'\x1b[27;2;13~', shifted), (b'\x1b[13;2u', shifted),
                             (b'\r', b'\r'), (b'abc', b'abc'), (b'\x03', control),
                             (b'\x1b[27;5;99~', control), (b'\x1b[99;5u', control),
                             (b'\x1ba', alt), (b'\x1b[97;3u', alt), (b'\x1b[9;2u', backtab)]
                    expected = b''
                    for sent, forwarded in cases:
                        expected += forwarded
                        tm.send(sent)
                        tm.wait(lambda: received.exists() and len(received.read_bytes()) >= len(expected),
                                f'pane mode {mode}: timed out forwarding {sent.hex()}')
                        self.assertEqual(received.read_bytes(), expected, (mode, sent.hex()))
                    tm.command('bind-key', 'p', 'set-option', '-g', '@prefix-test', 'received')
                    for prefix in (b'\x11', b'\x1b[27;5;113~', b'\x1b[113;5u'):
                        tm.command('set-option', '-g', '@prefix-test', 'waiting')
                        tm.send(prefix + b'p')
                        tm.wait(lambda: tm.option('@prefix-test') == 'received', 'Ctrl+Q prefix was not recognized')
                        self.assertEqual(received.read_bytes(), expected, 'prefix leaked pane input')
                    tm.screen.clear()
                    tm.send(b'\x1b[113;5ud')
                    tm.wait(lambda: b'\x1b[>4m' in tm.screen or b'\x1b[>4;0m' in tm.screen,
                            'detach did not reset outer modified keys')
                    tm.client.wait(timeout=5)
                    self.assertEqual(received.read_bytes(), expected, 'detach leaked pane input')
                    self.assertEqual(tm.format('#{session_attached}'), '0')
                finally:
                    tm.close()


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--reader':
        raw_reader(*sys.argv[2:])
    else:
        unittest.main(verbosity=2)
