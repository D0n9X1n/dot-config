#!/usr/bin/env python3
"""Retained RMUX pairs and explicit, workspace-only restart."""
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


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'mux'))
from workspace import (PrivateState, StoreError, digest, flag, identifier, integer,
                       make_snapshot, parse_layout, require, structural, text,
                       validate_snapshot)


class Store(PrivateState):
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
