#!/usr/bin/env python3
"""Native tmux: exact sessions and explicit workspace-only restart per socket."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import pwd
import signal
import stat
import subprocess
import sys
import time
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'mux'))
from workspace import (PrivateState, StoreError, digest, identifier, integer,
                       make_snapshot, parse_layout, require, structural, text,
                       validate_snapshot)

SESSION = {'session_name': 'text', 'session_id': '$', 'session_windows': 'int', 'session_grouped': 'flag'}
WINDOW = {'session_name': 'text', 'window_id': '@', 'window_index': 'int', 'window_name': 'text',
          'window_width': 'int', 'window_height': 'int', 'window_layout': 'layout',
          'window_panes': 'int', 'window_active': 'flag', 'window_zoomed_flag': 'flag'}
PANE = {'session_name': 'text', 'window_index': 'int', 'pane_id': '%', 'pane_index': 'int',
        'pane_width': 'int', 'pane_height': 'int', 'pane_current_path': 'text',
        'pane_active': 'flag', 'pane_dead': 'flag'}
SERVER = {'pid': 'int', 'socket_path': 'text', 'start_time': 'int', 'version': 'text'}


def record_format(schema):
    return 'TMS1:' + ''.join('#{n:' + field + '}:#{' + field + '}' for field in schema)


def decode_rows(output, schema):
    data = output.encode('utf-8')
    require(len(data) <= 8 * 1024 * 1024, 'native format response too large')
    rows, pos = [], 0
    while pos < len(data):
        require(data[pos:pos + 5] == b'TMS1:', 'invalid native record framing')
        pos += 5
        row = {}
        for field, kind in schema.items():
            end = data.find(b':', pos, pos + 9)
            require(end > pos and data[pos:end].isdigit(), 'invalid native field length')
            size = int(data[pos:end])
            require(size <= 262144 and end + 1 + size <= len(data), 'invalid native field extent')
            pos = end + 1
            try:
                value = data[pos:pos + size].decode('utf-8')
            except UnicodeError as exc:
                raise StoreError('invalid native UTF-8 field') from exc
            pos += size
            if kind == 'int':
                require(re.fullmatch(r'[0-9]{1,12}', value) is not None, 'invalid native integer')
                value = integer(int(value), 0, 2**63 - 1)
            elif kind == 'flag':
                require(value in ('0', '1'), 'invalid native flag')
                value = value == '1'
            elif kind in ('$', '@', '%'):
                identifier(value, kind)
            elif kind == 'layout':
                parse_layout(value)
            else:
                text(value)
            row[field] = value
        require(data[pos:pos + 1] == b'\n', 'invalid native record terminator')
        pos += 1
        rows.append(row)
        require(len(rows) <= 8192, 'too many native records')
    return rows


def literal(value):
    text(value)
    value = value.replace('#', '##')
    return value[:-1] + '\\;' if value.endswith(';') else value


def saved_name(value):
    text(value)
    require(re.search(r'(?<!\\)(?:\\\\)*\\(?!\\)', value) is None,
            'unrepresentable native name escaping')
    return literal(value.replace('\\\\', '\\'))


def remap_layout(value, panes):
    leaves = parse_layout(value)
    require(len(leaves) == len(panes), 'layout remap count mismatch')
    ids = iter(identifier(pane, '%')[1:] for pane in panes)
    body = re.sub(r'(\d+x\d+,\d+,\d+),\d+(?=[,}\]]|$)',
                  lambda match: match.group(1) + ',' + next(ids), value[5:])
    checksum = 0
    for char in body:
        checksum = (((checksum >> 1) | ((checksum & 1) << 15)) + ord(char)) & 0xffff
    result = f'{checksum:04x},{body}'
    parse_layout(result)
    return result


def snapshot_hash(snapshot):
    return hashlib.sha256(json.dumps(snapshot, sort_keys=True).encode()).hexdigest()


def validate_active_record(active):
    require(isinstance(active, dict) and set(active) == {'version', 'runtime', 'server'} and
            active['version'] == 1, 'invalid native active metadata')
    require(isinstance(active['runtime'], dict) and set(active['runtime']) == {'path', 'hash', 'version'},
            'invalid native runtime metadata')
    server = active['server']
    if server is not None:
        require(isinstance(server, dict) and set(server) == {'pid', 'socket', 'start', 'started', 'version'},
                'invalid native server metadata')
        integer(server['pid'], 2, 2**31 - 1)
        integer(server['started'], 0, 2**63 - 1)
        for field in ('socket', 'start', 'version'):
            text(server[field])
        require(os.path.isabs(server['socket']), 'invalid native server socket')
    return active


def validate_operation_record(operation):
    require(isinstance(operation, dict) and set(operation) ==
            {'version', 'id', 'phase', 'old', 'runtime', 'snapshot_hash'} and operation['version'] == 1,
            'invalid native restart journal')
    require(isinstance(operation['id'], str) and re.fullmatch(r'[0-9a-f]{32}', operation['id']) and
            isinstance(operation['snapshot_hash'], str) and re.fullmatch(r'[0-9a-f]{64}', operation['snapshot_hash']),
            'invalid native restart generation')
    require(operation['phase'] in ('prepared', 'stopping', 'restoring', 'complete', 'cancelled', 'failed', 'retry-prepared'),
            'invalid native restart phase')
    require(isinstance(operation['runtime'], dict) and set(operation['runtime']) == {'path', 'hash', 'version'},
            'invalid native restart runtime')
    require(validate_active_record(operation['old'])['server'] is not None, 'restart journal has no original server')
    return operation


def canonical_socket(value):
    text(value)
    require(os.path.isabs(value), 'tmux socket must be absolute')
    path = Path(value).resolve()
    require(len(os.fsencode(path)) < 104, 'tmux socket path is too long')
    if path.exists():
        info = path.stat()
        require(stat.S_ISSOCK(info.st_mode) and info.st_uid == os.getuid(), 'unsafe tmux socket')
    parent = path.parent
    if parent.exists():
        info = parent.stat()
        require(info.st_uid in (0, os.getuid()) and
                (not info.st_mode & 0o022 or info.st_mode & stat.S_ISVTX), 'unsafe tmux socket directory')
    return str(path)


def native_context():
    if os.environ.get('RMUX') or not os.environ.get('TMUX'):
        return None
    parts = os.environ['TMUX'].rsplit(',', 2)
    require(len(parts) == 3 and re.fullmatch(r'[0-9]+', parts[1]) and
            re.fullmatch(r'[0-9]+', parts[2]), 'invalid native TMUX context')
    return {'socket': canonical_socket(parts[0]), 'pid': integer(int(parts[1]), 2, 2**31 - 1)}


class Store(PrivateState):
    lock_label = 'tmux-store'

    def __init__(self, home=None, installed=None, socket=None, config=None):
        self.home = Path(home or Path.home()).resolve()
        self.installed = Path(installed) if installed else next(
            (path for path in (Path('/opt/homebrew/bin/tmux'), Path('/usr/local/bin/tmux')) if path.is_file()),
            Path('/opt/homebrew/bin/tmux'))
        context = native_context() if socket is None else None
        default = Path(os.environ.get('TMUX_TMPDIR') or '/tmp') / f'tmux-{os.getuid()}' / 'default'
        self.socket = canonical_socket(str(socket) if socket is not None else context['socket'] if context else str(default))
        self.config = str(config) if config is not None else None
        key = hashlib.sha256(os.fsencode(self.socket)).hexdigest()
        self.state = self.home / '.local/state/tmux-store' / key
        self.private_dir(self.state)

    def environment(self):
        env = dict(os.environ)
        for key in ('RMUX', 'RMUX_PANE', 'TMUX', 'TMUX_PANE'):
            env.pop(key, None)
        env['HOME'] = str(self.home)
        return env

    def runtime_at(self, path):
        try:
            path = Path(path).resolve(strict=True)
        except OSError as exc:
            raise StoreError('native runtime missing; keep the matching Homebrew Cellar version installed') from exc
        info = path.stat()
        require(stat.S_ISREG(info.st_mode) and info.st_uid in (0, os.getuid()) and
                not info.st_mode & 0o022 and os.access(path, os.X_OK), 'unsafe native runtime executable')
        fingerprint = digest(path)
        result = subprocess.run([str(path), '-V'], env=self.environment(), capture_output=True,
                                encoding='utf-8', errors='strict', timeout=10)
        match = re.fullmatch(r'tmux ([0-9]+\.[0-9]+[a-z]?(?:-next)?)\n?', result.stdout)
        require(result.returncode == 0 and match is not None,
                f'native runtime cannot run (missing dependencies or unsupported version): {result.stderr.strip()}')
        require(digest(path) == fingerprint, 'native runtime changed during preflight')
        return {'path': str(path), 'hash': fingerprint, 'version': match.group(1)}

    def installed_runtime(self):
        return self.runtime_at(self.installed)

    def validate_runtime(self, runtime):
        require(isinstance(runtime, dict) and set(runtime) == {'path', 'hash', 'version'}, 'invalid native runtime metadata')
        require(isinstance(runtime['path'], str) and os.path.isabs(runtime['path']) and
                isinstance(runtime['hash'], str) and re.fullmatch(r'[0-9a-f]{64}', runtime['hash']), 'invalid native runtime fingerprint')
        require(self.runtime_at(runtime['path']) == runtime,
                'native runtime fingerprint changed; refusing unknown or replaced executable')
        return runtime

    def argv(self, runtime, args, no_start=True):
        command = [runtime['path'], '-S', self.socket]
        if self.config is not None:
            command += ['-f', self.config]
        if no_start:
            command.append('-N')
        return command + list(args)

    def run(self, runtime, args, no_start=True):
        return subprocess.run(self.argv(runtime, args, no_start), env=self.environment(), capture_output=True,
                              encoding='utf-8', errors='strict', timeout=30)

    def command(self, runtime, args, no_start=True):
        result = self.run(runtime, args, no_start)
        require(result.returncode == 0, f"tmux {args[0]} failed: {result.stderr.strip() or result.stdout.strip()}")
        return result.stdout.removesuffix('\n')

    def query(self, runtime, args, schema):
        result = self.run(runtime, list(args) + ['-F', record_format(schema)])
        require(result.returncode == 0, f"tmux {args[0]} failed: {result.stderr.strip()}")
        return decode_rows(result.stdout, schema)

    def process_info(self, pid):
        integer(pid, 2, 2**31 - 1)
        require(sys.platform == 'darwin', 'native server verification requires Darwin process information')

        class BSDInfo(ctypes.Structure):
            _fields_ = [(name, ctypes.c_uint32) for name in
                        ('flags', 'status', 'xstatus', 'pid', 'ppid', 'uid', 'gid', 'ruid', 'rgid', 'svuid', 'svgid', 'reserved')]
            _fields_ += [('comm', ctypes.c_char * 16), ('name', ctypes.c_char * 32)]
            _fields_ += [(name, ctypes.c_uint32) for name in ('nfiles', 'pgid', 'jobc', 'tdev', 'tpgid', 'nice')]
            _fields_ += [('sec', ctypes.c_uint64), ('usec', ctypes.c_uint64)]

        lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
        info, path = BSDInfo(), ctypes.create_string_buffer(4096)
        require(lib.proc_pidinfo(pid, 3, 0, ctypes.byref(info), ctypes.sizeof(info)) == ctypes.sizeof(info)
                and lib.proc_pidpath(pid, path, len(path)) > 0, 'cannot inspect native server generation')
        require(info.pid == pid and info.uid == os.getuid(), 'native server is not owned by this user')
        return {'ppid': info.ppid, 'start': f'{info.sec}.{info.usec:06d}', 'path': os.fsdecode(path.value)}

    def probe(self, runtime):
        result = self.run(runtime, ['display-message', '-p', record_format(SERVER)])
        if result.returncode:
            message = result.stderr.strip()
            if message in (f'error connecting to {self.socket} (No such file or directory)',
                           f'error connecting to {self.socket} (Connection refused)',
                           f'no server running on {self.socket}'):
                return None
            raise StoreError(f'cannot safely query native tmux: {message or result.stdout.strip()}')
        rows = decode_rows(result.stdout, SERVER)
        require(len(rows) == 1, 'invalid native server identity response')
        row = rows[0]
        require(canonical_socket(row['socket_path']) == self.socket, 'native server socket mismatch')
        require(row['version'] == runtime['version'], 'native server/client version mismatch; refusing unknown server')
        process = self.process_info(row['pid'])
        return {'pid': row['pid'], 'socket': self.socket, 'start': process['start'],
                'started': row['start_time'], 'version': row['version']}

    def verify_process(self, runtime, server):
        self.validate_runtime(runtime)
        info = self.process_info(server['pid'])
        require(info['start'] == server['start'] and Path(info['path']).resolve() == Path(runtime['path']) and
                server['socket'] == self.socket and server['version'] == runtime['version'],
                'native executable or server generation changed; refusing unknown server')
        require(self.process_info(server['pid'])['start'] == server['start'], 'native generation changed during verification')

    def record_active(self, runtime):
        server = self.probe(runtime)
        if server:
            self.verify_process(runtime, server)
        active = {'version': 1, 'runtime': runtime, 'server': server}
        self.write_json('active.json', active)
        return active

    def ensure_active(self):
        active = self.read_json('active.json')
        if active is not None:
            validate_active_record(active)
            runtime = self.validate_runtime(active['runtime'])
            if self.probe(runtime) is not None:
                return self.record_active(runtime)
        return self.record_active(self.installed_runtime())

    def prepare(self):
        with self.lock():
            return self.ensure_active()

    def session_id(self, runtime, name):
        text(name, name=True)
        rows = self.query(runtime, ['list-sessions'], SESSION)
        matches = [row['session_id'] for row in rows if row['session_name'] == name.replace('\\', '\\\\')]
        require(len(matches) <= 1, 'duplicate exact session name')
        return matches[0] if matches else None

    def bootstrap(self, runtime, name, width=80, height=24, cwd=None, window_name=None):
        self.validate_runtime(runtime)
        require(self.probe(runtime) is None, 'new-server bootstrap requires an absent socket')
        socket_parent = Path(self.socket).parent
        if not socket_parent.exists():
            socket_parent.mkdir(mode=0o700, exist_ok=True)
        canonical_socket(self.socket)
        args = self.new_session(name, width, height, cwd, window_name)
        output = self.command(runtime, args, no_start=False)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            server = self.probe(runtime)
            if server:
                self.verify_process(runtime, server)
                if self.process_info(server['pid'])['ppid'] == 1:
                    return output
            time.sleep(.05)
        raise StoreError('new tmux server did not become PPID 1; refusing attach')

    def fresh_shell(self):
        shell = pwd.getpwuid(os.getuid()).pw_shell or '/bin/sh'
        text(shell)
        require(os.path.isabs(shell) and Path(shell).is_file() and os.access(shell, os.X_OK),
                'login shell is not an available executable')
        return [shell, '-l']

    def new_session(self, name, width=80, height=24, cwd=None, window_name=None):
        text(name, name=True)
        args = ['new-session', '-d', '-P', '-F', '#{session_id}|#{window_id}|#{pane_id}',
                '-s', literal(name), '-x', str(integer(width, 1, 10000)), '-y', str(integer(height, 1, 10000))]
        if cwd:
            args += ['-c', literal(cwd)]
        if window_name:
            args += ['-n', literal(window_name)]
        return args + self.fresh_shell()

    def current_pane(self, active):
        context = native_context()
        require(context and context['socket'] == self.socket and active['server'] and
                context['pid'] == active['server']['pid'], 'not inside the selected native tmux server')
        return identifier(os.environ.get('TMUX_PANE'), '%')

    def calling_client(self, active):
        pane = self.current_pane(active)
        sid = self.command(active['runtime'], ['display-message', '-p', '-t', pane, '#{session_id}'])
        identifier(sid, '$')
        rows = self.query(active['runtime'], ['list-clients', '-t', sid], {'client_name': 'text', 'session_id': '$'})
        require(len(rows) == 1 and rows[0]['session_id'] == sid,
                'native client is absent or ambiguous; use prefix+d or detach other clients first')
        return rows[0]['client_name']

    def attach(self, name):
        text(name, name=True)
        require(not os.environ.get('RMUX'), 'cannot attach native tmux inside RMUX; detach first')
        with self.lock():
            active = self.ensure_active()
            runtime = active['runtime']
            sid = self.session_id(runtime, name) if active['server'] else None
            client = self.calling_client(active) if native_context() else None
            if sid is None:
                if active['server'] is None:
                    self.bootstrap(runtime, name)
                    self.record_active(runtime)
                else:
                    self.command(runtime, self.new_session(name))
                sid = self.session_id(runtime, name)
            require(sid is not None, 'created exact session was not found')
        args = ['switch-client', '-c', client, '-t', sid] if client else ['attach-session', '-t', sid]
        argv = self.argv(runtime, args)
        os.execve(argv[0], argv, self.environment())

    def list_sessions(self):
        with self.lock():
            active = self.ensure_active()
            if active['server'] is None:
                print('No tmux server is running.')
                return
            for row in self.query(active['runtime'], ['list-sessions'], SESSION):
                name = row['session_name'].replace('\\\\', '\\')
                print(f"{name}: {row['session_windows']} windows ({row['session_id']})")

    def delete(self, name):
        text(name, name=True)
        with self.lock():
            active = self.ensure_active()
            require(active['server'] is not None, 'no native tmux server is running')
            sid = self.session_id(active['runtime'], name)
            require(sid is not None, f'no exact session named {name!r}')
            self.command(active['runtime'], ['kill-session', '-t', sid])

    def rename(self, title):
        require(not os.environ.get('RMUX'), 'cannot rename native tmux from RMUX; detach first')
        text(title)
        with self.lock():
            active = self.ensure_active()
            pane = self.current_pane(active)
            self.command(active['runtime'], ['rename-window', '-t', pane, '--', literal(title)])

    def client(self, args):
        require(args and not args[0].startswith('-'), 'client requires a command on the selected socket; no endpoint overrides')
        require(not os.environ.get('RMUX'), 'cannot dispatch native tmux from RMUX; detach first')
        if args[0] in ('rename-window', 'renamew') and len(args) == 2:
            return self.rename(args[1])
        with self.lock():
            active = self.ensure_active()
            require(active['server'] is not None, 'no native tmux server is running')
            if args[0] in ('detach-client', 'detach') and len(args) == 1:
                args = [args[0], '-t', self.calling_client(active)]
            argv = self.argv(active['runtime'], args)
        os.execve(argv[0], argv, self.environment())

    def capture(self, runtime):
        def once():
            sessions = self.query(runtime, ['list-sessions'], SESSION)
            windows = self.query(runtime, ['list-windows', '-a'], WINDOW)
            require(not any(window['window_zoomed_flag'] for window in windows), 'zoomed windows unsupported')
            panes = self.query(runtime, ['list-panes', '-a'], PANE)
            return make_snapshot(sessions, windows, panes)
        first = once()
        for _ in range(5):
            time.sleep(.05)
            second = once()
            if first == second:
                return validate_snapshot(second)
            first = second
        raise StoreError('workspace changed during capture; retry when stable')

    def wait_absent(self, runtime):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if self.probe(runtime) is None:
                return
            time.sleep(.05)
        raise StoreError('tmux server did not stop; refusing to start another')

    def cwd(self, path):
        if os.path.isdir(path) and os.access(path, os.X_OK):
            return os.path.realpath(path)
        print(f'Warning: cwd {path!r} unavailable; using HOME.', flush=True)
        return str(self.home)

    def preflight(self, runtime, snapshot):
        validate_snapshot(snapshot)
        self.validate_runtime(runtime)
        self.fresh_shell()
        for session in snapshot['sessions']:
            saved_name(session['name'])
            for window in session['windows']:
                saved_name(window['name'])
                for pane in window['panes']:
                    self.cwd(pane['cwd'])

    def restore(self, runtime, snapshot):
        self.preflight(runtime, snapshot)
        expected = json.loads(json.dumps(snapshot))
        for session in expected['sessions']:
            for window in session['windows']:
                for pane in window['panes']:
                    pane['cwd'] = self.cwd(pane['cwd'])
        require(self.probe(runtime) is None, 'restore requires an absent server; no automatic repeat kill')
        first_server = True
        for session in expected['sessions']:
            selected = None
            for wi, window in enumerate(session['windows']):
                if wi == 0:
                    name = session['name'].replace('\\\\', '\\')
                    title = window['name'].replace('\\\\', '\\')
                    if first_server:
                        ids = self.bootstrap(runtime, name, window['width'], window['height'], window['panes'][0]['cwd'], title)
                        self.record_active(runtime)
                        first_server = False
                    else:
                        ids = self.command(runtime, self.new_session(name, window['width'], window['height'], window['panes'][0]['cwd'], title))
                    parts = ids.split('|')
                    require(len(parts) == 3, 'missing fresh session IDs')
                    sid, wid, pid = identifier(parts[0], '$'), identifier(parts[1], '@'), identifier(parts[2], '%')
                    self.command(runtime, ['set-option', '-t', sid, 'renumber-windows', 'off'])
                    index = self.command(runtime, ['display-message', '-p', '-t', wid, '#{window_index}'])
                    if index != str(window['index']):
                        self.command(runtime, ['move-window', '-s', wid, '-t', f"{sid}:{window['index']}"])
                else:
                    ids = self.command(runtime, ['new-window', '-d', '-P', '-F', '#{window_id}|#{pane_id}',
                                                '-t', f"{sid}:{window['index']}", '-n', saved_name(window['name']),
                                                '-c', literal(window['panes'][0]['cwd'])] + self.fresh_shell())
                    parts = ids.split('|')
                    require(len(parts) == 2, 'missing fresh window IDs')
                    wid, pid = identifier(parts[0], '@'), identifier(parts[1], '%')
                self.command(runtime, ['set-option', '-w', '-t', wid, 'automatic-rename', 'off'])
                self.command(runtime, ['set-option', '-w', '-t', wid, 'pane-base-index', str(window['panes'][0]['index'])])
                count = len(window['panes'])
                width = max(window['width'], count * 4)
                self.command(runtime, ['resize-window', '-t', wid, '-x', str(width), '-y', str(max(window['height'], 4))])
                fresh = [pid]
                for index, pane in enumerate(window['panes'][1:], 1):
                    pid = self.command(runtime, ['split-window', '-d', '-h', '-P', '-F', '#{pane_id}',
                                                '-t', fresh[-1], '-l', str(width - index * 3), '-c', literal(pane['cwd'])] + self.fresh_shell())
                    fresh.append(identifier(pid, '%'))
                self.command(runtime, ['resize-window', '-t', wid, '-x', str(window['width']), '-y', str(window['height'])])
                self.command(runtime, ['select-layout', '-t', wid, remap_layout(window['layout'], fresh)])
                self.command(runtime, ['set-option', '-w', '-u', '-t', wid, 'window-size'])
                for pane, pid in zip(window['panes'], fresh):
                    if pane['active']:
                        self.command(runtime, ['select-pane', '-t', pid])
                if window['active']:
                    selected = wid
            self.command(runtime, ['select-window', '-t', selected])
            self.command(runtime, ['set-option', '-u', '-t', sid, 'renumber-windows'])
        require(structural(self.capture(runtime)) == structural(expected),
                'restored cwd, dimensions, layout, indices or active state differ; snapshot kept')
        self.record_active(runtime)

    def restart(self):
        with self.lock():
            operation = self.read_json('operation.json')
            if operation is not None:
                validate_operation_record(operation)
                if operation['phase'] not in ('complete', 'cancelled'):
                    return self.retry_restart(operation)
            runtime = self.installed_runtime()
            active = self.ensure_active()
            if active['server'] is None:
                print('No sessions to restart.')
                return
            snapshot = self.capture(active['runtime'])
            self.preflight(runtime, snapshot)
            require(sys.stdin.isatty(), 'restart needs an interactive terminal; no server stopped')
            print('Restart ALL native tmux sessions on this socket, including detached sessions. ALL running programs will stop.\n'
                  'Only names, layout, dimensions, active choices and cwd return as fresh shells; no command replay.', flush=True)
            if input('Type yes to continue: ').strip() != 'yes':
                print('Cancelled; no server stopped.')
                return
            require(self.probe(active['runtime']) == active['server'], 'server generation changed before restart')
            self.verify_process(active['runtime'], active['server'])
            require(self.capture(active['runtime']) == snapshot, 'workspace changed while confirming; retry')
            self.write_json('snapshot.json', snapshot, previous=True)
            operation = {'version': 1, 'id': uuid.uuid4().hex, 'phase': 'prepared', 'old': active,
                         'runtime': runtime, 'snapshot_hash': snapshot_hash(snapshot)}
            self.write_json('operation.json', operation)
            self.launch_worker(operation)

    def retry_restart(self, operation):
        validate_operation_record(operation)
        runtime = self.validate_runtime(operation['runtime'])
        active = self.read_json('active.json')
        if active is not None:
            validate_active_record(active)
        probe_runtime = self.validate_runtime(active['runtime']) if active is not None else runtime
        require(self.probe(probe_runtime) is None,
                'unfinished restart kept original snapshot; server still runs. Inspect restart.log; stop partial sessions explicitly before ts retry')
        snapshot = validate_snapshot(self.read_json('snapshot.json'))
        require(snapshot_hash(snapshot) == operation['snapshot_hash'], 'snapshot generation changed')
        self.preflight(runtime, snapshot)
        require(sys.stdin.isatty(), 'restart retry needs an interactive terminal')
        if input('Restore saved workspace into an empty server? Type yes: ').strip() != 'yes':
            print('Cancelled.')
            return
        operation['phase'] = 'retry-prepared'
        self.write_json('operation.json', operation)
        self.launch_worker(operation)

    def launch_worker(self, operation):
        read_fd, write_fd = os.pipe()
        log_fd = self.open_private(self.state / 'restart.log', os.O_WRONLY | os.O_APPEND | os.O_CREAT)
        args = [sys.executable, '-B', str(Path(__file__).resolve()), '_worker', str(read_fd), operation['id'],
                str(self.home), self.socket, str(self.installed), self.config or '']
        try:
            subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=log_fd, stderr=log_fd, start_new_session=True,
                             pass_fds=(read_fd,), env=self.environment(), cwd=str(self.home))
            print(f'Restart queued. Reconnect with tt NAME. Diagnostics: {self.state / "restart.log"}', flush=True)
        except Exception:
            os.close(write_fd)
            raise
        finally:
            os.close(log_fd)
            os.close(read_fd)
        os.set_inheritable(write_fd, False)
        self.handshake_fd = write_fd

    def worker(self, operation_id):
        with self.lock():
            operation = validate_operation_record(self.read_json('operation.json'))
            require(operation['id'] == operation_id and operation['phase'] in ('prepared', 'retry-prepared'),
                    'restart journal changed; refusing worker')
            snapshot = validate_snapshot(self.read_json('snapshot.json'))
            require(snapshot_hash(snapshot) == operation['snapshot_hash'], 'snapshot generation changed')
            runtime = self.validate_runtime(operation['runtime'])
            self.preflight(runtime, snapshot)
            stopped = False
            try:
                if operation['phase'] == 'prepared':
                    old = operation['old']
                    self.validate_runtime(old['runtime'])
                    require(self.probe(old['runtime']) == old['server'], 'server PID or start generation changed; not stopped')
                    self.verify_process(old['runtime'], old['server'])
                    require(self.capture(old['runtime']) == snapshot, 'workspace changed after confirmation; not stopped')
                    operation['phase'] = 'stopping'
                    self.write_json('operation.json', operation)
                    require(self.probe(old['runtime']) == old['server'], 'server generation changed immediately before kill; not stopped')
                    self.verify_process(old['runtime'], old['server'])
                    stopped = True
                    self.command(old['runtime'], ['kill-server'])
                    self.wait_absent(old['runtime'])
                else:
                    require(self.probe(runtime) is None, 'retry server appeared; not stopped')
                operation['phase'] = 'restoring'
                self.write_json('operation.json', operation)
                self.restore(runtime, snapshot)
                operation['phase'] = 'complete'
                self.write_json('operation.json', operation)
                print('Restart complete. Reconnect with tt NAME.', flush=True)
            except Exception as exc:
                if operation['phase'] == 'restoring':
                    try:
                        self.record_active(runtime)
                    except (StoreError, OSError, subprocess.SubprocessError):
                        pass
                operation['phase'] = 'failed' if stopped or operation['phase'] == 'restoring' else 'cancelled'
                self.write_json('operation.json', operation)
                print(f'Restart failed: {exc}. Original snapshot kept; retry only with an absent server. No automatic repeat kill.', flush=True)
                raise


HELP = '''Native tmux helpers
  tt NAME / tr NAME  Resume the exact session, or create detached then attach.
  tl                List sessions without starting a server.
  td NAME           Permanently stop the exact named session and its programs.
  ts                Confirm, save and restart ALL sessions on the selected socket.
  th                Show helper usage and upgrade steps.

Upgrade: brew upgrade tmux; then run ts when ready to stop running programs.
The matching Homebrew Cellar executable is reused, NOT copied or retained.
Keep its executable and dylibs installed until restart. Missing dependencies,
unknown versions, protocol errors and missing runtimes fail without stopping.
New servers must have OS parent PID (PPID) 1 before attach. Existing servers
are reused unchanged. Quit SonicTerm without ts; reconnect later with tt NAME.
Attach from RMUX is refused: detach first. Native panes select their own socket;
outside native tmux, use TMUX_TMPDIR or /tmp/tmux-UID/default. No socket scan.

Restart restores fresh shells, names, window indices, layout, size, cwd and active
choices only. No commands, environment, scrollback, processes or unsaved work are
saved or replayed. Missing cwd uses HOME. Linked/grouped, dead, zoomed, unstable
or unrepresentable workspaces are refused before stop. No autosave/reboot restore.
Private state: ~/.local/state/tmux-store/<socket-hash>/{snapshot.json,
snapshot.json.prev,operation.json,restart.log}. Failed restore keeps the original
snapshot; inspect restart.log and explicitly stop partial sessions before retry.
'''


def main(args=None):
    args = sys.argv[1:] if args is None else args
    command = args[0] if args else 'help'
    arity = {'attach': 2, 'delete': 2, 'rename': 2, 'list': 1, 'restart': 1, 'help': 1}
    if command == 'help' and len(args) <= 1:
        print(HELP)
        return 0
    if (command not in arity and command not in ('client', '_worker') or
            command in arity and len(args) != arity[command]):
        print('Usage: tmux-store {attach NAME|list|delete NAME|restart|help|rename TITLE|client ARGS...}', file=sys.stderr)
        return 2
    try:
        if command == '_worker':
            require(len(args) == 7 and args[1].isdigit() and re.fullmatch(r'[0-9a-f]{32}', args[2]), 'invalid worker request')
            signal.signal(signal.SIGHUP, signal.SIG_IGN)
            fd = int(args[1])
            while os.read(fd, 1):
                pass
            os.close(fd)
            if os.fork():
                return 0
            Store(home=args[3], socket=args[4], installed=args[5], config=args[6] or None).worker(args[2])
            return 0
        manager = Store()
        if command == 'client':
            manager.client(args[1:])
        elif command == 'list':
            manager.list_sessions()
        elif command in ('attach', 'delete', 'rename'):
            getattr(manager, command)(args[1])
        else:
            getattr(manager, command)()
        return 0
    except (StoreError, OSError, subprocess.SubprocessError, UnicodeError, EOFError, KeyboardInterrupt) as exc:
        print(f'tmux-store: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
