#!/usr/bin/env python3
"""Retained RMUX pairs and explicit, workspace-only restart."""
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import uuid


class StoreError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise StoreError(message)


def integer(value, minimum=0, maximum=1000000):
    require(type(value) is int and minimum <= value <= maximum, 'invalid workspace integer')
    return value


def text(value, name=False):
    require(isinstance(value, str) and value and len(value) <= 16384 and
            not any(ord(c) < 32 or ord(c) == 127 for c in value), 'invalid workspace text')
    if name:
        require(not value.startswith('-') and ':' not in value and '.' not in value,
                'session name cannot start with - or contain . or :')
    return value


def flag(value):
    require(type(value) is bool, 'invalid active flag')
    return value


def identifier(value, prefix):
    require(isinstance(value, str) and re.fullmatch(re.escape(prefix) + r'\d+', value), 'invalid runtime ID')
    return value


def parse_layout(value):
    require(isinstance(value, str) and len(value) <= 262144 and
            re.match(r'^[0-9a-fA-F]{4},', value), 'invalid layout')
    body = value[5:]
    checksum = 0
    for char in body:
        checksum = (((checksum >> 1) | ((checksum & 1) << 15)) + ord(char)) & 0xffff
    require(checksum == int(value[:4], 16), 'layout checksum mismatch')
    leaves = []

    def node(pos, depth=0):
        require(depth < 64, 'layout too deep')
        match = re.match(r'(\d+)x(\d+),(\d+),(\d+)', body[pos:])
        require(match is not None, 'malformed layout node')
        width, height, x, y = map(int, match.groups())
        integer(width, 1, 10000)
        integer(height, 1, 10000)
        integer(x, 0, 10000)
        integer(y, 0, 10000)
        rect = {'width': width, 'height': height, 'x': x, 'y': y}
        pos += match.end()
        require(pos < len(body), 'layout node has no content')
        if body[pos] == ',':
            match = re.match(r',(\d+)', body[pos:])
            require(match is not None, 'malformed layout leaf')
            leaf = dict(rect, id=int(match.group(1)))
            leaves.append(leaf)
            return rect, pos + match.end()
        opening = body[pos]
        require(opening in '{[', 'invalid layout split')
        closing = '}' if opening == '{' else ']'
        children = []
        pos += 1
        while True:
            child, pos = node(pos, depth + 1)
            children.append(child)
            require(pos < len(body), 'unclosed layout split')
            if body[pos] == closing:
                pos += 1
                break
            require(body[pos] == ',', 'invalid layout separator')
            pos += 1
        require(len(children) >= 2, 'layout split requires two children')
        cursor = x if opening == '{' else y
        for child in children:
            if opening == '{':
                require(child['x'] == cursor and child['y'] == y and child['height'] == height,
                        'inconsistent layout geometry')
                cursor += child['width'] + 1
            else:
                require(child['y'] == cursor and child['x'] == x and child['width'] == width,
                        'inconsistent layout geometry')
                cursor += child['height'] + 1
        require(cursor - 1 == (x + width if opening == '{' else y + height), 'inconsistent layout extent')
        return rect, pos

    root, end = node(0)
    require(end == len(body) and root['x'] == 0 and root['y'] == 0, 'invalid layout extent')
    require(len(leaves) <= 256 and len({p['id'] for p in leaves}) == len(leaves), 'duplicate or too many layout panes')
    return leaves


def make_snapshot(sessions, windows, panes):
    require(all(isinstance(rows, list) for rows in (sessions, windows, panes)), 'native JSON must contain arrays')
    require(len(sessions) <= 256 and len(windows) <= 2048 and len(panes) <= 8192, 'workspace exceeds restore limits')
    result = {'version': 1, 'sessions': []}
    session_names, window_ids, pane_ids = set(), set(), set()
    used_windows, used_panes = 0, 0
    try:
        for session in sorted(sessions, key=lambda s: s['session_name']):
            name = text(session['session_name'], name=True)
            identifier(session['session_id'], '$')
            require(name not in session_names and not session.get('session_grouped', False), 'duplicate or grouped session unsupported')
            session_names.add(name)
            ws = [w for w in windows if w['session_name'] == name]
            require(len(ws) == integer(session['session_windows'], 1), 'session window count changed')
            require(sum(flag(w['window_active']) for w in ws) == 1, 'invalid active window count')
            saved_session = {'name': name, 'windows': []}
            indices = set()
            for window in sorted(ws, key=lambda w: w['window_index']):
                wid = identifier(window['window_id'], '@')
                index = integer(window['window_index'])
                require(wid not in window_ids and index not in indices, 'linked or duplicate window unsupported')
                window_ids.add(wid)
                indices.add(index)
                leaves = parse_layout(window['window_layout'])
                width, height = integer(window['window_width'], 1, 10000), integer(window['window_height'], 1, 10000)
                require(window['window_layout'][5:].startswith(f'{width}x{height},0,0'), 'window and layout dimensions differ')
                ps = [p for p in panes if p['session_name'] == name and p['window_index'] == index]
                require(len(ps) == integer(window['window_panes'], 1, 256) == len(leaves), 'window pane count changed')
                require(sum(flag(p['pane_active']) for p in ps) == 1, 'invalid active pane count')
                by_id = {}
                for pane in ps:
                    pid = identifier(pane['pane_id'], '%')
                    require(pid not in pane_ids and not pane.get('pane_dead', False), 'duplicate or dead pane unsupported')
                    pane_ids.add(pid)
                    by_id[int(pid[1:])] = pane
                saved_window = {'index': index, 'name': text(window['window_name']), 'width': width,
                                'height': height, 'layout': window['window_layout'],
                                'active': flag(window['window_active']), 'panes': []}
                for leaf in leaves:
                    require(leaf['id'] in by_id, 'layout references missing pane')
                    pane = by_id[leaf['id']]
                    cwd = text(pane['pane_current_path'])
                    require(os.path.isabs(cwd), 'pane cwd must be absolute')
                    require(pane['pane_width'] == leaf['width'] and pane['pane_height'] == leaf['height'],
                            'pane geometry does not match layout (zoomed windows unsupported)')
                    saved_window['panes'].append({'index': integer(pane['pane_index']), 'width': leaf['width'],
                                                 'height': leaf['height'], 'cwd': cwd, 'active': flag(pane['pane_active'])})
                pane_indices = [p['index'] for p in saved_window['panes']]
                require(pane_indices == list(range(pane_indices[0], pane_indices[0] + len(ps))),
                        'pane indices must follow layout leaf order')
                used_panes += len(ps)
                saved_session['windows'].append(saved_window)
            used_windows += len(ws)
            result['sessions'].append(saved_session)
        require(used_windows == len(windows) and used_panes == len(panes), 'orphan workspace relationships')
    except (KeyError, TypeError, ValueError) as exc:
        raise StoreError('invalid native workspace JSON') from exc
    return result


def validate_snapshot(snapshot):
    require(isinstance(snapshot, dict) and set(snapshot) == {'version', 'sessions'} and snapshot['version'] == 1,
            'unsupported snapshot schema')
    require(isinstance(snapshot['sessions'], list), 'invalid snapshot sessions')
    sessions, windows, panes = [], [], []
    try:
        for si, session in enumerate(snapshot['sessions']):
            require(set(session) == {'name', 'windows'} and isinstance(session['windows'], list), 'invalid saved session fields')
            sessions.append({'session_name': session['name'], 'session_id': f'${si}', 'session_windows': len(session['windows'])})
            for window in session['windows']:
                require(set(window) == {'index', 'name', 'width', 'height', 'layout', 'active', 'panes'}, 'invalid saved window fields')
                leaves = parse_layout(window['layout'])
                require(len(leaves) == len(window['panes']), 'saved pane count mismatch')
                windows.append({'session_name': session['name'], 'window_id': f'@{len(windows)}',
                                'window_index': window['index'], 'window_name': window['name'], 'window_width': window['width'],
                                'window_height': window['height'], 'window_layout': window['layout'],
                                'window_active': window['active'], 'window_panes': len(leaves)})
                for leaf, pane in zip(leaves, window['panes']):
                    require(set(pane) == {'index', 'width', 'height', 'cwd', 'active'}, 'invalid saved pane fields')
                    panes.append({'session_name': session['name'], 'window_index': window['index'], 'pane_id': f"%{leaf['id']}",
                                  'pane_index': pane['index'], 'pane_width': pane['width'], 'pane_height': pane['height'],
                                  'pane_current_path': pane['cwd'], 'pane_active': pane['active']})
        require(make_snapshot(sessions, windows, panes) == snapshot, 'snapshot is not canonical')
    except (KeyError, TypeError, ValueError) as exc:
        raise StoreError('invalid saved workspace') from exc
    return snapshot


def structural(snapshot):
    result = json.loads(json.dumps(snapshot))
    for session in result['sessions']:
        for window in session['windows']:
            window['layout'] = re.sub(r'(\d+x\d+,\d+,\d+),\d+(?=[,}\]]|$)', r'\1,0', window['layout'][5:])
            for pane in window['panes']:
                pane['cwd'] = os.path.realpath(pane['cwd'])
    return result


def digest(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else hashlib.sha256(stream.read()).hexdigest()


class Store:
    def __init__(self, home=None, installed=None, socket=None, config=None):
        self.home = Path(home or Path.home()).resolve()
        self.state = self.home / '.local/state/rmux-store'
        self.runtimes = self.home / '.local/share/rmux-store/runtimes'
        self.installed = Path(installed) if installed else next((p for p in (Path('/opt/homebrew/bin/rmux'), Path('/usr/local/bin/rmux')) if p.is_file()), Path('/opt/homebrew/bin/rmux'))
        self.socket = str(socket) if socket else None
        self.config = str(config) if config else None
        self.private_dir(self.state)
        self.private_dir(self.runtimes.parent)
        self.private_dir(self.runtimes)

    def private_dir(self, path):
        relative = path.relative_to(self.home)
        current = self.home
        for component in relative.parts:
            current /= component
            if not current.exists() and not current.is_symlink():
                current.mkdir(mode=0o700)
            info = current.lstat()
            require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid(), f'unsafe directory: {current}')
            require(not info.st_mode & 0o022, f'writable-by-others directory: {current}')
        path.chmod(0o700)

    def safe_file(self, path):
        try:
            info = path.lstat()
        except FileNotFoundError:
            return False
        require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and info.st_nlink == 1 and
                not info.st_mode & 0o077, f'unsafe private file: {path}')
        return True

    def open_private(self, path, flags):
        self.safe_file(path)
        fd = os.open(path, flags | os.O_NOFOLLOW, 0o600)
        info = os.fstat(fd)
        if not (stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and info.st_nlink == 1 and not info.st_mode & 0o077):
            os.close(fd)
            raise StoreError(f'unsafe private file: {path}')
        return fd

    @contextlib.contextmanager
    def lock(self):
        fd = self.open_private(self.state / 'lock', os.O_CREAT | os.O_RDWR)
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc:
                raise StoreError('rmux-store busy; another operation holds the lock') from exc
            yield
        finally:
            os.close(fd)

    def read_json(self, name):
        path = self.state / name
        if not self.safe_file(path):
            return None
        with os.fdopen(self.open_private(path, os.O_RDONLY)) as stream:
            try:
                require(os.fstat(stream.fileno()).st_size <= 8 * 1024 * 1024, 'state file too large')
                return json.load(stream)
            except ValueError as exc:
                raise StoreError(f'invalid private JSON: {name}') from exc

    def write_json(self, name, value, previous=False):
        path = self.state / name
        exists = self.safe_file(path)
        if previous and exists:
            self.write_json(name + '.prev', self.read_json(name))
        fd, temporary = tempfile.mkstemp(prefix='.write-', dir=self.state)
        try:
            with os.fdopen(fd, 'w') as stream:
                json.dump(value, stream, ensure_ascii=True, sort_keys=True, separators=(',', ':'))
                stream.write('\n')
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, path)
            directory = os.open(self.state, os.O_RDONLY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    def check_dependencies(self, path):
        require(platform.system() == 'Darwin', 'runtime retention supports Darwin only')
        result = subprocess.run(['/usr/bin/otool', '-L', str(path)], capture_output=True, text=True, timeout=10)
        require(result.returncode == 0, f'cannot inspect runtime dependencies: {path}')
        lines = result.stdout.splitlines()[1:]
        require(lines, f'no runtime dependency evidence: {path}')
        for line in lines:
            dependency = line.strip().split(' (', 1)[0]
            require(dependency.startswith('/usr/lib/') or dependency.startswith('/System/Library/'),
                    f'unsupported non-system runtime dependency: {dependency}')

    def retain_installed(self):
        client = self.installed.resolve(strict=True)
        daemon = (self.installed.parent / 'rmux-daemon').resolve(strict=True)
        for path in (client, daemon):
            require(path.is_file() and os.access(path, os.X_OK), f'missing executable: {path}')
            self.check_dependencies(path)
        hashes = {'rmux': digest(client), 'rmux-daemon': digest(daemon)}
        key = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()
        target = self.runtimes / key
        if not target.exists():
            temporary = Path(tempfile.mkdtemp(prefix='.retain-', dir=self.runtimes))
            try:
                for path, name in ((client, 'rmux'), (daemon, 'rmux-daemon')):
                    shutil.copyfile(path, temporary / name)
                    (temporary / name).chmod(stat.S_IMODE(path.stat().st_mode) & 0o755)
                    require(digest(temporary / name) == hashes[name], 'installed runtime changed while copying; retry')
                os.rename(temporary, target)
            finally:
                if temporary.exists():
                    shutil.rmtree(temporary)
        runtime = {'hash': key, 'path': str(target), 'files': hashes}
        self.validate_runtime(runtime)
        return runtime

    def validate_runtime(self, runtime):
        require(isinstance(runtime, dict) and set(runtime) == {'hash', 'path', 'files'}, 'invalid runtime metadata')
        require(re.fullmatch(r'[0-9a-f]{64}', runtime['hash']) is not None, 'invalid runtime hash')
        path = self.runtimes / runtime['hash']
        require(str(path) == runtime['path'] and not path.is_symlink(), 'unsafe runtime location')
        require(path.stat().st_uid == os.getuid() and stat.S_IMODE(path.stat().st_mode) == 0o700, 'unsafe runtime permissions')
        require(set(runtime['files']) == {'rmux', 'rmux-daemon'}, 'runtime pair incomplete')
        require(hashlib.sha256(json.dumps(runtime['files'], sort_keys=True).encode()).hexdigest() == runtime['hash'], 'runtime pair hash mismatch')
        for name, expected in runtime['files'].items():
            executable = path / name
            info = executable.lstat()
            require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and not info.st_mode & 0o022 and
                    os.access(executable, os.X_OK) and digest(executable) == expected, 'retained runtime fingerprint mismatch')
        return runtime

    def environment(self):
        env = dict(os.environ)
        for key in ('RMUX', 'RMUX_PANE', 'TMUX', 'TMUX_PANE'):
            env.pop(key, None)
        env['RMUX_DISABLE_TMUX_FALLBACK'] = '1'
        return env

    def argv(self, runtime, args, no_start=True):
        command = [str(Path(runtime['path']) / 'rmux')]
        if self.socket:
            command += ['-S', self.socket]
        if self.config:
            command += ['-f', self.config]
        if no_start:
            command.append('-N')
        return command + list(args)

    def run(self, runtime, args, no_start=True):
        return subprocess.run(self.argv(runtime, args, no_start), env=self.environment(), capture_output=True, text=True, timeout=30)

    def command(self, runtime, args, no_start=True):
        result = self.run(runtime, args, no_start)
        require(result.returncode == 0, f"rmux {args[0]} failed: {result.stderr.strip() or result.stdout.strip()}")
        return result.stdout.strip()

    def json_command(self, runtime, args):
        try:
            result = json.loads(self.command(runtime, list(args) + ['--json']))
            require(isinstance(result, list), 'native JSON is not an array')
            return result
        except ValueError as exc:
            raise StoreError('native RMUX JSON is invalid') from exc

    def process_info(self, pid):
        integer(pid, 2, 2**31 - 1)
        result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'ppid=,lstart=,comm='], capture_output=True, text=True, timeout=10)
        match = re.match(r'\s*(\d+)\s+(\w+\s+\w+\s+\d+\s+\d+:\d+:\d+\s+\d+)\s+(.+)', result.stdout.strip())
        require(result.returncode == 0 and match is not None, 'cannot inspect daemon generation')
        return {'ppid': int(match.group(1)), 'start': ' '.join(match.group(2).split()), 'path': match.group(3)}

    def probe(self, runtime):
        result = self.run(runtime, ['display-message', '-p', '#{pid}|#{socket_path}'])
        if result.returncode:
            message = result.stderr.strip()
            if (re.fullmatch(r'error connecting to .+ \((?:No such file or directory|Connection refused)\)', message)
                    or re.fullmatch(r'no server running on /[^\n]+', message)):
                return None
            raise StoreError(f'cannot safely query RMUX: {message or result.stdout.strip()}')
        match = re.fullmatch(r'(\d+)\|([^\n]+)\n?', result.stdout)
        require(match is not None and os.path.isabs(match.group(2)), 'invalid daemon identity response')
        pid = int(match.group(1))
        return {'pid': pid, 'socket': match.group(2), 'start': self.process_info(pid)['start']}

    def verify_process(self, runtime, server):
        info = self.process_info(server['pid'])
        require(info['start'] == server['start'], 'daemon generation changed')
        active = self.read_json('active.json')
        # Homebrew may unlink a running executable after its fingerprint was verified.
        if active and active.get('server') == server and active.get('runtime') == runtime:
            return
        require(platform.system() == 'Darwin', 'daemon fingerprint verification supports Darwin only')
        result = subprocess.run(['/usr/sbin/lsof', '-a', '-p', str(server['pid']), '-d', 'txt', '-Ffin'],
                                capture_output=True, text=True, timeout=10)
        require(result.returncode == 0, 'cannot resolve daemon executable; refusing unknown server')
        candidates = []
        inode = None
        for line in result.stdout.splitlines():
            if line.startswith('f'):
                inode = None
            elif line.startswith('i'):
                inode = line[1:]
            elif line.startswith('n') and Path(line[1:]).name == 'rmux-daemon':
                candidates.append((Path(line[1:]), inode))
        require(len(candidates) == 1, 'cannot identify daemon executable; refusing unknown server')
        path, inode = candidates[0]
        require(path.is_file() and inode is not None and str(path.stat().st_ino) == inode and
                digest(path) == runtime['files']['rmux-daemon'], 'daemon fingerprint mismatch; refusing unknown server')
        require(self.process_info(server['pid'])['start'] == server['start'], 'daemon changed during fingerprint check')

    def record_active(self, runtime):
        server = self.probe(runtime)
        if server:
            self.verify_process(runtime, server)
        active = {'version': 1, 'runtime': runtime, 'server': server}
        self.write_json('active.json', active)
        return active

    def ensure_active(self):
        active = self.read_json('active.json')
        if active:
            require(isinstance(active, dict) and active.get('version') == 1, 'invalid active metadata')
            runtime = self.validate_runtime(active['runtime'])
            server = self.probe(runtime)
            if server:
                self.verify_process(runtime, server)
                active['server'] = server
                self.write_json('active.json', active)
                return active
        runtime = self.retain_installed()
        return self.record_active(runtime)

    def prepare(self):
        with self.lock():
            return self.ensure_active()

    def session_id(self, runtime, name):
        rows = self.json_command(runtime, ['list-sessions'])
        matches = [identifier(row['session_id'], '$') for row in rows if row['session_name'] == name]
        require(len(matches) <= 1, 'duplicate exact session name')
        return matches[0] if matches else None

    def bootstrap(self, runtime, name, width=80, height=24, cwd=None, window_name=None):
        args = ['new-session', '-d', '-P', '-F', '#{session_id}|#{window_id}|#{pane_id}', '-s', name,
                '-x', str(width), '-y', str(height)]
        if cwd:
            args += ['-c', cwd]
        if window_name:
            args += ['-n', window_name]
        output = self.command(runtime, args, no_start=False)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            server = self.probe(runtime)
            if server:
                self.verify_process(runtime, server)
                if self.process_info(server['pid'])['ppid'] == 1:
                    return output
            time.sleep(0.05)
        raise StoreError('new daemon did not become PPID 1; refusing attach')

    def rr(self, name):
        text(name, name=True)
        with self.lock():
            active = self.ensure_active()
            runtime = active['runtime']
            if active['server'] is None:
                self.bootstrap(runtime, name)
                self.record_active(runtime)
                sid = self.session_id(runtime, name)
            else:
                sid = self.session_id(runtime, name)
                if sid is None:
                    self.command(runtime, ['new-session', '-d', '-s', name])
                    sid = self.session_id(runtime, name)
            require(sid is not None, 'created session was not found')
        command = 'switch-client' if os.environ.get('RMUX') and not self.foreign([]) else 'attach-session'
        argv = self.argv(runtime, [command, '-t', sid])
        env = dict(os.environ) if command == 'switch-client' else self.environment()
        os.execve(argv[0], argv, env)

    def rl(self):
        with self.lock():
            active = self.ensure_active()
            if active['server'] is None:
                print('No RMUX server is running.')
                return
            print(self.command(active['runtime'], ['list-sessions']))

    def rd(self, name):
        text(name, name=True)
        with self.lock():
            active = self.ensure_active()
            require(active['server'] is not None, 'no RMUX server is running')
            sid = self.session_id(active['runtime'], name)
            require(sid is not None, f'no exact session named {name!r}')
            self.command(active['runtime'], ['kill-session', '-t', sid])

    def foreign(self, args):
        for arg in args:
            if arg.startswith('-L') or arg.startswith('-S'):
                return True
        nested = os.environ.get('RMUX')
        if not nested:
            return False
        active = self.read_json('active.json')
        server = active.get('server') if isinstance(active, dict) else None
        return not server or nested.rsplit(',', 2)[0] != server['socket']

    def client(self, args):
        if self.foreign(args):
            os.execv(str(self.installed), [str(self.installed)] + args)
        with self.lock():
            active = self.ensure_active()
            runtime = active['runtime']
        reads = {'list-sessions', 'ls', 'list-windows', 'lsw', 'list-panes', 'lsp', 'has-session', 'has',
                 'display-message', 'display', 'show-options', 'show', 'show-environment', 'showenv',
                 'list-clients', 'lsc', 'capture-pane', 'capturep'}
        no_start = active['server'] is not None or bool(args and args[0] in reads)
        argv = self.argv(runtime, args, no_start=no_start)
        env = dict(os.environ)
        env['RMUX_DISABLE_TMUX_FALLBACK'] = '1'
        os.execve(argv[0], argv, env)

    def capture(self, runtime):
        def once():
            return make_snapshot(self.json_command(runtime, ['list-sessions']),
                                 self.json_command(runtime, ['list-windows', '-a']),
                                 self.json_command(runtime, ['list-panes', '-a']))
        first = once()
        for attempt in range(5):
            time.sleep(0.05)
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
            time.sleep(0.05)
        raise StoreError('daemon did not stop; refusing to start another')

    def cwd(self, path):
        if os.path.isdir(path) and os.access(path, os.X_OK):
            return os.path.realpath(path)
        print(f'Warning: cwd {path!r} unavailable; using HOME.', flush=True)
        return str(self.home)

    def restore(self, runtime, snapshot):
        validate_snapshot(snapshot)
        expected = json.loads(json.dumps(snapshot))
        for session in expected['sessions']:
            for window in session['windows']:
                for pane in window['panes']:
                    pane['cwd'] = self.cwd(pane['cwd'])
        require(self.probe(runtime) is None, 'restore requires an absent daemon; no automatic repeat kill')
        first_server = True
        for session in expected['sessions']:
            sid = None
            selected_window = None
            for wi, window in enumerate(session['windows']):
                pane_base = window['panes'][0]['index']
                if wi == 0:
                    args = ['new-session', '-d', '-P', '-F', '#{session_id}|#{window_id}|#{pane_id}',
                            '-s', session['name'], '-n', window['name'], '-x', str(window['width']),
                            '-y', str(window['height']), '-c', window['panes'][0]['cwd']]
                    if first_server:
                        ids = self.bootstrap(runtime, session['name'], window['width'], window['height'],
                                             window['panes'][0]['cwd'], window['name'])
                        self.record_active(runtime)
                        first_server = False
                    else:
                        ids = self.command(runtime, args)
                    parts = ids.split('|')
                    require(len(parts) == 3, 'missing fresh session IDs')
                    sid, wid, pid = identifier(parts[0], '$'), identifier(parts[1], '@'), identifier(parts[2], '%')
                    self.command(runtime, ['set-option', '-t', sid, 'renumber-windows', 'off'])
                    current = self.json_command(runtime, ['list-windows', '-t', sid])
                    if current[0]['window_index'] != window['index']:
                        self.command(runtime, ['move-window', '-s', wid, '-t', f"{sid}:{window['index']}"])
                else:
                    ids = self.command(runtime, ['new-window', '-d', '-P', '-F', '#{window_id}|#{pane_id}',
                                                '-t', f"{sid}:{window['index']}", '-n', window['name'], '-c', window['panes'][0]['cwd']])
                    parts = ids.split('|')
                    require(len(parts) == 2, 'missing fresh window IDs')
                    wid, pid = identifier(parts[0], '@'), identifier(parts[1], '%')
                self.command(runtime, ['set-option', '-w', '-t', wid, 'pane-base-index', str(pane_base)])
                count = len(window['panes'])
                self.command(runtime, ['resize-window', '-t', wid, '-x', str(max(window['width'], count * 4)), '-y', str(max(window['height'], 4))])
                fresh_panes = [pid]
                for index, pane in enumerate(window['panes'][1:], 1):
                    remaining_width = max(window['width'], count * 4) - index * 3
                    pid = self.command(runtime, ['split-window', '-d', '-h', '-P', '-F', '#{pane_id}',
                                                 '-t', fresh_panes[-1], '-l', str(remaining_width), '-c', pane['cwd']])
                    fresh_panes.append(identifier(pid, '%'))
                self.command(runtime, ['resize-window', '-t', wid, '-x', str(window['width']), '-y', str(window['height'])])
                self.command(runtime, ['select-layout', '-t', wid, window['layout']])
                for pane, pid in zip(window['panes'], fresh_panes):
                    if pane['active']:
                        self.command(runtime, ['select-pane', '-t', pid])
                if window['active']:
                    selected_window = wid
            self.command(runtime, ['select-window', '-t', selected_window])
        actual = self.capture(runtime)
        require(structural(actual) == structural(expected), 'restored cwd, dimensions, layout, indices or active state differ; snapshot kept')
        self.record_active(runtime)

    def preflight(self, runtime, snapshot):
        validate_snapshot(snapshot)
        self.validate_runtime(runtime)
        for session in snapshot['sessions']:
            for window in session['windows']:
                for pane in window['panes']:
                    self.cwd(pane['cwd'])

    def restart(self):
        with self.lock():
            operation = self.read_json('operation.json')
            if operation and operation.get('phase') not in ('complete', 'cancelled'):
                return self.retry_restart(operation)
            active = self.ensure_active()
            if active['server'] is None:
                print('No sessions to restart.')
                return
            runtime = self.retain_installed()
            snapshot = self.capture(active['runtime'])
            if not snapshot['sessions']:
                print('No sessions to restart.')
                return
            self.preflight(runtime, snapshot)
            require(sys.stdin.isatty(), 'restart needs an interactive terminal; no server stopped')
            print('Restart ALL RMUX sessions, including detached sessions. ALL running programs will stop.\n'
                  'Only window/pane layout and working directories return; no running commands are replayed.', flush=True)
            if input('Type yes to continue: ').strip() != 'yes':
                print('Cancelled; no server stopped.')
                return
            require(self.probe(active['runtime']) == active['server'], 'daemon changed before restart')
            require(self.capture(active['runtime']) == snapshot, 'workspace changed while confirming; retry')
            self.write_json('snapshot.json', snapshot, previous=True)
            operation = {'version': 1, 'id': uuid.uuid4().hex, 'phase': 'prepared', 'old': active,
                         'runtime': runtime, 'snapshot_hash': hashlib.sha256(json.dumps(snapshot, sort_keys=True).encode()).hexdigest()}
            self.write_json('operation.json', operation)
            self.launch_worker(operation)

    def retry_restart(self, operation):
        require(operation.get('version') == 1, 'unfinished restart journal is invalid')
        runtime = self.validate_runtime(operation['runtime'])
        active = self.read_json('active.json')
        probe_runtime = self.validate_runtime(active['runtime']) if active else runtime
        require(self.probe(probe_runtime) is None, 'unfinished restart kept original snapshot; server still runs. Inspect restart.log; stop partial sessions explicitly before rs retry')
        snapshot = validate_snapshot(self.read_json('snapshot.json'))
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
        args = [sys.executable, '-B', str(Path(__file__).resolve()), '_worker', str(read_fd), operation['id']]
        try:
            subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=log_fd, stderr=log_fd,
                             start_new_session=True, pass_fds=(read_fd,), env=self.environment(), cwd=str(self.home))
            print(f'Restart queued. Reconnect with rr NAME. Diagnostics: {self.state / "restart.log"}', flush=True)
        finally:
            os.close(log_fd)
            os.close(read_fd)
        # EOF means the invoking process exited, not just that it released its lock.
        os.set_inheritable(write_fd, False)
        self.handshake_fd = write_fd

    def worker(self, operation_id):
        with self.lock():
            operation = self.read_json('operation.json')
            require(operation and operation.get('id') == operation_id and operation.get('phase') in ('prepared', 'retry-prepared'), 'restart journal changed; refusing worker')
            snapshot = validate_snapshot(self.read_json('snapshot.json'))
            require(hashlib.sha256(json.dumps(snapshot, sort_keys=True).encode()).hexdigest() == operation['snapshot_hash'], 'snapshot generation changed')
            runtime = self.validate_runtime(operation['runtime'])
            self.socket = operation['old']['server']['socket']
            self.preflight(runtime, snapshot)
            try:
                if operation['phase'] == 'prepared':
                    old = operation['old']
                    self.validate_runtime(old['runtime'])
                    require(self.probe(old['runtime']) == old['server'], 'server PID or start generation changed; not stopped')
                    self.verify_process(old['runtime'], old['server'])
                    require(self.capture(old['runtime']) == snapshot, 'workspace changed after confirmation; not stopped')
                    operation['phase'] = 'stopping'
                    self.write_json('operation.json', operation)
                    self.command(old['runtime'], ['kill-server'])
                    self.wait_absent(old['runtime'])
                else:
                    require(self.probe(runtime) is None, 'retry server appeared; not stopped')
                operation['phase'] = 'restoring'
                self.write_json('operation.json', operation)
                self.restore(runtime, snapshot)
                operation['phase'] = 'complete'
                self.write_json('operation.json', operation)
                print('Restart complete. Reconnect with rr NAME.', flush=True)
            except Exception as exc:
                if operation['phase'] == 'restoring':
                    try:
                        self.record_active(runtime)
                    except (StoreError, OSError, subprocess.SubprocessError):
                        pass
                stopped = operation['phase'] in ('stopping', 'restoring')
                operation['phase'] = 'failed' if stopped else 'cancelled'
                self.write_json('operation.json', operation)
                recovery = ('Original snapshot kept. Use rs to retry once the server is empty; no automatic repeat kill.'
                            if stopped else 'No server stopped. Run rs again to save a fresh workspace.')
                print(f'Restart failed: {exc}. {recovery}', flush=True)
                raise


HELP = '''RMUX helpers
  rr NAME       Resume the exact session, or create it detached then attach.
  rl            List sessions without starting a server.
  rd NAME       Permanently stop the exact named session and its programs.
  rs            Save and restart ALL sessions using the installed runtime.
  rh            Show helper usage, parent PID, and upgrade steps.

Upgrade: brew upgrade rmux
When ready to stop running programs: rs
Both executables are retained privately; a live server keeps its old client.
New servers started by rr use a short-lived bootstrap and are checked for PPID 1
before attach. The terminal owns the attached client, not the new daemon.
Existing servers are preserved, not retroactively reparented.
Quit SonicTerm without rs; use rr NAME to reconnect later.

rs asks before stopping ALL programs in ALL sessions, including detached ones.
It restores names, window/pane layout, dimensions, active choices and cwd only.
No command replay, environment, history, terminal contents, autosave or reboot
restore. Missing directories warn and use HOME. Linked/grouped windows/sessions,
zoomed or unstable/unrepresentable workspaces are refused before stopping.

Private state: ~/.local/state/rmux-store (snapshot.json, its .prev, operation.json,
restart.log). A failed restore keeps the original snapshot. Read restart.log;
rr/rl still use the runtime actually running. Stop partial sessions deliberately
before rs retry; retry never automatically kills a partial server.
'''


def main(args=None):
    args = sys.argv[1:] if args is None else args
    command = args[0] if args else 'help'
    arity = {'rr': 2, 'rl': 1, 'rd': 2, 'prepare': 1, 'restart': 1, 'help': 1}
    if command == 'help' and len(args) <= 1:
        print(HELP)
        return 0
    if command not in arity and command not in ('client', '_worker') or command in arity and len(args) != arity[command]:
        print('Usage: rmux-store {rr NAME|rl|rd NAME|client ARGS...|prepare|restart|help}', file=sys.stderr)
        return 2
    try:
        if command == '_worker':
            require(len(args) == 3 and args[1].isdigit() and re.fullmatch(r'[0-9a-f]{32}', args[2]), 'invalid worker request')
            signal.signal(signal.SIGHUP, signal.SIG_IGN)
            fd = int(args[1])
            while os.read(fd, 1):
                pass
            os.close(fd)
            if os.fork():
                return 0
            manager = Store()
            manager.worker(args[2])
            return 0
        manager = Store()
        if command == 'client':
            manager.client(args[1:])
        elif command in ('rr', 'rd'):
            getattr(manager, command)(args[1])
        else:
            getattr(manager, command)()
        return 0
    except (StoreError, OSError, subprocess.SubprocessError, EOFError, KeyboardInterrupt) as exc:
        print(f'rmux-store: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
