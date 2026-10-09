#!/usr/bin/env python3
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().with_name('store.py')
spec = importlib.util.spec_from_file_location('native_tmux_store', MODULE)
store = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = store
spec.loader.exec_module(store)


def layout(body):
    checksum = 0
    for char in body:
        checksum = (((checksum >> 1) | ((checksum & 1) << 15)) + ord(char)) & 0xffff
    return f'{checksum:04x},{body}'


def snapshot():
    return {'version': 1, 'sessions': [{'name': 'work', 'windows': [
        {'index': 2, 'name': '雪 #{literal};', 'width': 80, 'height': 24,
         'layout': layout('80x24,0,0{39x24,0,0,7,40x24,40,0,2}'), 'active': True,
         'panes': [{'index': 1, 'width': 39, 'height': 24, 'cwd': '/tmp', 'active': False},
                   {'index': 2, 'width': 40, 'height': 24, 'cwd': '/tmp', 'active': True}]}]}]}


def framed(values):
    return 'TMS1:' + ''.join(str(len(value.encode('utf-8'))) + ':' + value for value in values) + '\n'


class FormatTests(unittest.TestCase):
    def test_unicode_whitespace_and_format_text_are_literal(self):
        schema = {'session_name': 'text', 'session_id': '$'}
        names = ['work', 'workshop', '雪 work #{pid} #(no execution);', '  both spaces  ']
        rows = store.decode_rows(''.join(framed([name, '$' + str(i)]) for i, name in enumerate(names)), schema)
        self.assertEqual([row['session_name'] for row in rows], names)

    def test_reject_malformed_framing_controls_and_types(self):
        for output in ['work\t$1\n', 'TMS1:4:work2:$1', 'TMS1:9:short\n',
                       framed(['bad\nname', '$1']), framed(['ok', '$bad']),
                       framed(['ok', '$1']) + 'garbage\n']:
            with self.subTest(output=output), self.assertRaises(store.StoreError):
                store.decode_rows(output, {'session_name': 'text', 'session_id': '$'})
        for value in ['-1', '1x', '', 'true', '2']:
            with self.subTest(value=value), self.assertRaises(store.StoreError):
                store.decode_rows(framed([value]), {'active': 'flag'})

    def test_tmux38_json_layout_reads_as_legacy_layout(self):
        pane = lambda w, h, x, y, pid: {'t': 'p', 'w': w, 'h': h, 'x': x, 'y': y, 'i': 0, 'I': f'%{pid}'}
        value = json.dumps({'V': 2, 'L': {'t': 'h', 'w': 80, 'h': 24, 'x': 0, 'y': 0, 'c': [
            dict(pane(40, 24, 0, 0, 0), l=0),
            {'t': 'v', 'w': 39, 'h': 24, 'x': 41, 'y': 0, 'c': [
                dict(pane(39, 12, 41, 0, 1), a=True), pane(39, 11, 41, 13, 2)]}]}}, separators=(',', ':'))
        rows = store.decode_rows(framed([value]), {'window_layout': 'layout'})
        self.assertEqual(rows, [{'window_layout': layout('80x24,0,0{40x24,0,0,0,39x24,41,0[39x12,41,0,1,39x11,41,13,2]}')}])
        root = {'t': 'p', 'w': 80, 'h': 24, 'x': 0, 'y': 0, 'I': '%3'}
        self.assertEqual(store.decode_rows(framed([json.dumps({'V': 2, 'L': root})]), {'window_layout': 'layout'}),
                         [{'window_layout': layout('80x24,0,0,3')}])
        for bad in ['{', json.dumps({'V': 1, 'L': root}), json.dumps({'V': 2, 'L': dict(root, t='x')}),
                    json.dumps({'V': 2, 'L': dict(root, I='3')}), json.dumps({'V': 2, 'L': dict(root, t='h', c=[])}),
                    json.dumps({'V': 2, 'L': dict(root, w=True)}), json.dumps([2])]:
            with self.subTest(bad=bad), self.assertRaises(store.StoreError):
                store.decode_rows(framed([bad]), {'window_layout': 'layout'})

    def test_snapshot_whitelist_and_layout_remapping(self):
        saved = store.validate_snapshot(snapshot())
        value = store.remap_layout(saved['sessions'][0]['windows'][0]['layout'], ['%100', '%200'])
        self.assertEqual([leaf['id'] for leaf in store.parse_layout(value)], [100, 200])
        after = json.loads(json.dumps(saved))
        after['sessions'][0]['windows'][0]['layout'] = value
        self.assertEqual(store.structural(after), store.structural(saved))
        after['sessions'][0]['windows'][0]['panes'][0]['command'] = 'secret'
        with self.assertRaises(store.StoreError): store.validate_snapshot(after)


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='tmux-store-unit-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.binary = self.home / 'tmux'
        self.binary.write_bytes(b'fixture-native-tmux')
        self.binary.chmod(0o700)
        self.environment = patch.dict(os.environ, {}, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.manager = store.Store(home=self.home, installed=self.binary, socket=self.home / 'socket')
        self.runtime = {'path': str(self.binary), 'hash': store.digest(self.binary), 'version': '3.7c'}
        self.server = {'pid': 42, 'socket': self.manager.socket, 'start': '100.000001', 'started': 100, 'version': '3.7c'}
        self.active = {'version': 1, 'runtime': self.runtime, 'server': self.server}

    def test_socket_selection_native_rmux_and_canonical_isolation(self):
        with patch.dict(os.environ, {'TMUX': str(self.home / 'other') + ',123,1'}):
            native = store.Store(home=self.home, installed=self.binary)
            self.assertEqual(native.socket, str(self.home / 'other'))
            self.assertNotEqual(native.state, self.manager.state)
            with patch.dict(os.environ, {'RMUX': '/rmux,12,1', 'TMUX_TMPDIR': str(self.home)}):
                foreign = store.Store(home=self.home, installed=self.binary)
                self.assertEqual(foreign.socket, str(self.home / f'tmux-{os.getuid()}/default'))
        alias = self.home / 'alias'
        alias.symlink_to(self.home, target_is_directory=True)
        same = store.Store(home=self.home, installed=self.binary, socket=alias / 'socket')
        self.assertEqual(same.state, self.manager.state)
        self.assertEqual(self.manager.state.parent, self.home / '.local/state/tmux-store')

    def test_invalid_native_context_never_falls_back(self):
        for value in ['relative,123,1', '/valid,bad,1', '/valid,1,1', '/bad\npath,123,1', '/valid']:
            with self.subTest(value=value), patch.dict(os.environ, {'TMUX': value}):
                with self.assertRaises(store.StoreError): store.Store(home=self.home, installed=self.binary)

    def test_socket_cannot_be_a_regular_file(self):
        path = self.home / 'not-a-socket'
        path.write_text('untouched')
        with self.assertRaises(store.StoreError): store.Store(home=self.home, installed=self.binary, socket=path)
        self.assertEqual(path.read_text(), 'untouched')

    def test_child_environment_and_explicit_binary(self):
        with patch.dict(os.environ, {'PATH': '/rmux/private/shim', 'RMUX': 'r', 'RMUX_PANE': '%9',
                                    'TMUX': 't', 'TMUX_PANE': '%1'}):
            env = self.manager.environment()
            self.assertFalse(any(key in env for key in ('RMUX', 'RMUX_PANE', 'TMUX', 'TMUX_PANE')))
            argv = self.manager.argv(self.runtime, ['list-sessions'])
            self.assertEqual(argv[0], str(self.binary))
            self.assertIn('-N', argv)
            self.assertEqual(argv[argv.index('-S') + 1], self.manager.socket)
            default = store.Store(home=self.home, socket=self.home / 'second')
            self.assertIn(str(default.installed), ('/opt/homebrew/bin/tmux', '/usr/local/bin/tmux'))

    def test_private_atomic_metadata_previous_symlinks_and_lock(self):
        self.manager.write_json('snapshot.json', {'old': 1})
        self.manager.write_json('snapshot.json', {'new': 2}, previous=True)
        self.assertEqual(self.manager.read_json('snapshot.json.prev'), {'old': 1})
        self.assertEqual(self.manager.state.stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.manager.state / 'snapshot.json').stat().st_mode & 0o777, 0o600)
        target = self.home / 'target'
        target.write_text('{}')
        (self.manager.state / 'active.json').symlink_to(target)
        for call in (lambda: self.manager.read_json('active.json'), lambda: self.manager.write_json('active.json', {})):
            with self.assertRaises(store.StoreError): call()
        other = store.Store(home=self.home, installed=self.binary, socket=self.manager.socket)
        with self.manager.lock():
            with self.assertRaisesRegex(store.StoreError, 'busy'):
                with other.lock(): pass
        self.assertEqual(target.read_text(), '{}')

    def test_binary_preflight_checks_version_and_never_copies(self):
        output = subprocess.CompletedProcess([], 0, 'tmux 3.7c\n', '')
        with patch.object(store.subprocess, 'run', return_value=output) as run:
            self.assertEqual(self.manager.installed_runtime(), self.runtime)
            self.assertEqual(run.call_args.args[0], [str(self.binary), '-V'])
        self.assertFalse((self.home / '.local/share').exists())
        with patch.object(store.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'dyld missing library')):
            with self.assertRaisesRegex(store.StoreError, 'runtime'): self.manager.installed_runtime()

    def test_missing_or_replaced_recorded_runtime_is_not_bootstrapped(self):
        self.manager.write_json('active.json', self.active)
        self.binary.unlink()
        with patch.object(self.manager, 'bootstrap') as bootstrap, patch.object(self.manager, 'command') as command:
            with self.assertRaises((store.StoreError, OSError)): self.manager.attach('work')
            bootstrap.assert_not_called()
            command.assert_not_called()

    def deleted_keg(self):
        old = self.home / 'old-tmux'
        old.write_bytes(b'fixture-old-native-tmux')
        old.chmod(0o700)
        recorded = {'path': str(old), 'hash': store.digest(old), 'version': '3.7c'}
        old.unlink()
        self.upgraded = dict(self.runtime, version='3.8')
        self.manager.write_json('active.json', {'version': 1, 'runtime': recorded, 'server': self.server})
        return recorded

    def serving(self, pid=42, version='3.7c'):
        row = framed([str(pid), self.manager.socket, '100', version])
        return patch.object(self.manager, 'run', return_value=subprocess.CompletedProcess([], 0, row, ''))

    def orphan_process(self, start='100.000001'):
        return patch.object(self.manager, 'process_info', return_value={'ppid': 1, 'start': start, 'path': None})

    def recovery_log(self):
        path = self.manager.state / 'recovery.log'
        return path.read_text() if path.exists() else ''

    def test_deleted_keg_adopts_exact_recorded_generation_with_log_and_notice(self):
        self.deleted_keg()
        with patch.object(self.manager, 'installed_runtime', return_value=self.upgraded), \
             patch.object(self.manager, 'validate_runtime', side_effect=lambda runtime: runtime), \
             self.serving(), self.orphan_process(), patch('sys.stderr', new_callable=io.StringIO) as err:
            active = self.manager.ensure_active()
        self.assertEqual(active, {'version': 1, 'runtime': self.upgraded, 'server': self.server})
        self.assertEqual(self.manager.read_json('active.json'), active)
        self.assertIn('adopted running tmux 3.7c server (pid 42); client now 3.8', err.getvalue())
        self.assertIn(str(self.manager.state / 'recovery.log'), err.getvalue())
        self.assertRegex(self.recovery_log(), r'^\S+ adopted server pid 42 .*3\.7c.*3\.8')
        self.assertEqual((self.manager.state / 'recovery.log').stat().st_mode & 0o777, 0o600)
        with patch.object(self.manager, 'validate_runtime', side_effect=lambda runtime: runtime), \
             self.serving(), self.orphan_process(), patch('sys.stderr', new_callable=io.StringIO) as err:
            self.assertEqual(self.manager.ensure_active(), active)
        self.assertEqual(err.getvalue(), '', 'adopted record is reused without another adoption')

    def test_deleted_keg_refuses_other_generations_and_logs(self):
        for name, pid, start in [('pid', 43, '100.000001'), ('start', 42, '101.000001')]:
            with self.subTest(changed=name):
                recorded = self.deleted_keg()
                with patch.object(self.manager, 'installed_runtime', return_value=self.upgraded), \
                     patch.object(self.manager, 'validate_runtime', side_effect=lambda runtime: runtime), \
                     self.serving(pid=pid), self.orphan_process(start=start), \
                     patch.object(self.manager, 'bootstrap') as bootstrap, patch.object(self.manager, 'command') as command:
                    with self.assertRaises(store.StoreError): self.manager.ensure_active()
                    bootstrap.assert_not_called()
                    command.assert_not_called()
                self.assertEqual(self.manager.read_json('active.json')['runtime'], recorded)
                self.assertIn('refused', self.recovery_log())

    def test_deleted_keg_refuses_owner_socket_version_and_unrecorded_servers(self):
        cases = [('owner', self.serving(), patch.object(self.manager, 'process_info',
                  side_effect=store.StoreError('native server is not owned by this user')), self.server),
                 ('socket', patch.object(self.manager, 'run', return_value=subprocess.CompletedProcess(
                     [], 0, framed(['42', str(self.home / 'other'), '100', '3.7c']), '')), self.orphan_process(), self.server),
                 ('version', self.serving(version='3.6'), self.orphan_process(), self.server),
                 ('unrecorded old', self.serving(), self.orphan_process(), None),
                 ('unrecorded new', self.serving(version='3.8'), self.orphan_process(), None)]
        for name, run, process, server in cases:
            with self.subTest(case=name):
                recorded = self.deleted_keg()
                self.manager.write_json('active.json', {'version': 1, 'runtime': recorded, 'server': server})
                with patch.object(self.manager, 'installed_runtime', return_value=self.upgraded), \
                     patch.object(self.manager, 'validate_runtime', side_effect=lambda runtime: runtime), run, process, \
                     patch.object(self.manager, 'command') as command:
                    with self.assertRaises(store.StoreError): self.manager.ensure_active()
                    command.assert_not_called()
                self.assertEqual(self.manager.read_json('active.json')['runtime'], recorded)

    def test_deleted_keg_never_saves_a_server_from_a_later_probe(self):
        self.deleted_keg()
        other = subprocess.CompletedProcess([], 0, framed(['43', self.manager.socket, '200', '3.8']), '')
        exact = subprocess.CompletedProcess([], 0, framed(['42', self.manager.socket, '100', '3.7c']), '')
        gone = subprocess.CompletedProcess([], 1, '', f'no server running on {self.manager.socket}')
        for first, expected in [(exact, self.server), (gone, None)]:
            with self.subTest(expected=expected):
                self.deleted_keg()
                with patch.object(self.manager, 'installed_runtime', return_value=self.upgraded), \
                     patch.object(self.manager, 'validate_runtime', side_effect=lambda runtime: runtime), \
                     patch.object(self.manager, 'run', side_effect=[first, other]), self.orphan_process(), \
                     patch('sys.stderr', new_callable=io.StringIO):
                    self.assertEqual(self.manager.ensure_active()['server'], expected)
                self.assertEqual(self.manager.read_json('active.json')['server'], expected)

    def test_deleted_keg_logs_installed_runtime_failure(self):
        recorded = self.deleted_keg()
        with patch.object(self.manager, 'installed_runtime', side_effect=store.StoreError('dyld missing library')):
            with self.assertRaisesRegex(store.StoreError, 'dyld'): self.manager.ensure_active()
        self.assertIn('refused adoption: dyld missing library', self.recovery_log())
        self.assertEqual(self.manager.read_json('active.json')['runtime'], recorded)

    def test_deleted_keg_short_log_write_blocks_adoption(self):
        recorded = self.deleted_keg()
        with patch.object(self.manager, 'installed_runtime', return_value=self.upgraded), \
             patch.object(self.manager, 'validate_runtime', side_effect=lambda runtime: runtime), \
             self.serving(), self.orphan_process(), patch.object(store.os, 'write', return_value=1):
            with self.assertRaisesRegex(store.StoreError, 'incomplete recovery log'): self.manager.ensure_active()
        self.assertEqual(self.manager.read_json('active.json')['runtime'], recorded)

    def test_adopted_server_is_known_to_wait_and_retry(self):
        upgraded = dict(self.runtime, version='3.8')
        alive = subprocess.CompletedProcess([], 0, framed(['42', self.manager.socket, '100', '3.7c']), '')
        gone = subprocess.CompletedProcess([], 1, '', f'no server running on {self.manager.socket}')
        with patch.object(self.manager, 'run', side_effect=[alive, gone]), self.orphan_process():
            self.manager.wait_absent(upgraded, self.server)
        operation = self.operation()
        operation['phase'] = 'failed'
        self.manager.write_json('operation.json', operation)
        self.manager.write_json('active.json', {'version': 1, 'runtime': upgraded, 'server': self.server})
        with patch.object(self.manager, 'validate_runtime', side_effect=lambda runtime: runtime), \
             self.serving(), self.orphan_process(), patch.object(self.manager, 'command') as command:
            with self.assertRaisesRegex(store.StoreError, 'still runs'): self.manager.restart()
            command.assert_not_called()

    def test_version_only_runtime_replacement_is_refused(self):
        self.manager.write_json('active.json', dict(self.active, runtime=dict(self.runtime, version='3.6')))
        with patch.object(store.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'tmux 3.7c\n', '')), \
             patch.object(self.manager, 'installed_runtime') as installed:
            with self.assertRaisesRegex(store.StoreError, 'fingerprint changed'): self.manager.ensure_active()
            installed.assert_not_called()

    def test_deleted_keg_with_recorded_server_gone_uses_installed_runtime(self):
        self.deleted_keg()
        gone = subprocess.CompletedProcess([], 1, '', f'no server running on {self.manager.socket}')
        with patch.object(self.manager, 'installed_runtime', return_value=self.upgraded), \
             patch.object(self.manager, 'run', return_value=gone):
            self.assertEqual(self.manager.ensure_active(), {'version': 1, 'runtime': self.upgraded, 'server': None})
        self.assertIn('gone', self.recovery_log())

    def test_deleted_keg_adoption_needs_a_safe_log(self):
        recorded = self.deleted_keg()
        (self.manager.state / 'recovery.log').symlink_to(self.home / 'elsewhere')
        with patch.object(self.manager, 'installed_runtime', return_value=self.upgraded), \
             patch.object(self.manager, 'validate_runtime', side_effect=lambda runtime: runtime), \
             self.serving(), self.orphan_process():
            with self.assertRaises((store.StoreError, OSError)): self.manager.ensure_active()
        self.assertEqual(self.manager.read_json('active.json')['runtime'], recorded)
        self.assertFalse((self.home / 'elsewhere').exists())

    def test_replaced_existing_runtime_is_still_refused(self):
        self.manager.write_json('active.json', dict(self.active, runtime=dict(self.runtime, hash='0' * 64)))
        output = subprocess.CompletedProcess([], 0, 'tmux 3.7c\n', '')
        with patch.object(store.subprocess, 'run', return_value=output), \
             patch.object(self.manager, 'installed_runtime') as installed:
            with self.assertRaisesRegex(store.StoreError, 'fingerprint changed'): self.manager.ensure_active()
            installed.assert_not_called()

    def test_probe_accepts_version_skew_only_for_the_recorded_server(self):
        upgraded = dict(self.runtime, version='3.8')
        with self.serving(), self.orphan_process():
            with self.assertRaisesRegex(store.StoreError, 'version mismatch'): self.manager.probe(upgraded)
            self.assertEqual(self.manager.probe(upgraded, self.server), self.server)
        with self.serving(pid=43), self.orphan_process():
            with self.assertRaisesRegex(store.StoreError, 'version mismatch'): self.manager.probe(upgraded, self.server)

    def test_deleted_executable_passes_only_for_the_recorded_generation(self):
        with patch.object(self.manager, 'validate_runtime'), self.orphan_process():
            self.manager.verify_process(self.runtime, self.server, self.server)
            with self.assertRaisesRegex(store.StoreError, 'generation'): self.manager.verify_process(self.runtime, self.server)
            with self.assertRaisesRegex(store.StoreError, 'generation'):
                self.manager.verify_process(self.runtime, dict(self.server, start='101.000001'), self.server)

    def test_process_info_tolerates_only_a_deleted_executable(self):
        class Library:
            def __init__(self, error): self.error = error
            def proc_pidinfo(self, pid, flavor, arg, buffer, size):
                info = buffer._obj
                info.pid, info.uid, info.ppid, info.sec, info.usec = pid, os.getuid(), 1, 100, 1
                return size
            def proc_pidpath(self, pid, buffer, size):
                store.ctypes.set_errno(self.error)
                return 0
        with patch.object(store.sys, 'platform', 'darwin'):
            with patch.object(store.ctypes, 'CDLL', return_value=Library(store.errno.ENOENT)):
                self.assertEqual(self.manager.process_info(42), {'ppid': 1, 'start': '100.000001', 'path': None})
            with patch.object(store.ctypes, 'CDLL', return_value=Library(store.errno.EPERM)):
                with self.assertRaisesRegex(store.StoreError, 'cannot inspect'): self.manager.process_info(42)

    def test_restart_and_worker_stop_an_adopted_server(self):
        adopted = {'version': 1, 'runtime': dict(self.runtime, version='3.8'), 'server': self.server}
        with patch.object(self.manager, 'ensure_active', return_value=adopted), \
             patch.object(self.manager, 'installed_runtime', return_value=adopted['runtime']), \
             patch.object(self.manager, 'validate_runtime'), patch.object(self.manager, 'capture', return_value=snapshot()), \
             patch.object(self.manager, 'preflight'), patch('sys.stdin.isatty', return_value=True), \
             patch('builtins.input', return_value='yes'), self.serving(), self.orphan_process(), \
             patch.object(self.manager, 'launch_worker') as launch, patch('sys.stdout', new_callable=io.StringIO):
            self.manager.restart()
            launch.assert_called_once()
        operation = self.manager.read_json('operation.json')
        self.assertEqual(operation['old'], adopted)
        gone = subprocess.CompletedProcess([], 1, '', f'no server running on {self.manager.socket}')
        alive = subprocess.CompletedProcess([], 0, framed(['42', self.manager.socket, '100', '3.7c']), '')
        with patch.object(self.manager, 'validate_runtime', side_effect=lambda runtime: runtime), \
             patch.object(self.manager, 'preflight'), patch.object(self.manager, 'capture', return_value=snapshot()), \
             patch.object(self.manager, 'run', side_effect=[alive, alive, gone]), self.orphan_process(), \
             patch.object(self.manager, 'command') as command, patch.object(self.manager, 'restore') as restore, \
             patch('sys.stdout', new_callable=io.StringIO):
            self.manager.worker(operation['id'])
            command.assert_called_once_with(adopted['runtime'], ['kill-server'])
            restore.assert_called_once()
        self.assertEqual(self.manager.read_json('operation.json')['phase'], 'complete')

    def test_protocol_auth_and_wrong_socket_are_not_absence(self):
        for message in ['protocol version mismatch', 'permission denied', 'access not allowed',
                        'error connecting to /someone-else (No such file or directory)']:
            with self.subTest(message=message), patch.object(self.manager, 'run', return_value=subprocess.CompletedProcess([], 1, '', message)):
                with self.assertRaises(store.StoreError): self.manager.probe(self.runtime)
        for message in [f'error connecting to {self.manager.socket} (No such file or directory)',
                        f'error connecting to {self.manager.socket} (Connection refused)',
                        f'no server running on {self.manager.socket}']:
            with patch.object(self.manager, 'run', return_value=subprocess.CompletedProcess([], 1, '', message)):
                self.assertIsNone(self.manager.probe(self.runtime))

    def test_list_absence_does_not_start_and_invalid_names_do_nothing(self):
        with patch.object(self.manager, 'ensure_active', return_value=dict(self.active, server=None)), \
             patch.object(self.manager, 'bootstrap') as bootstrap, patch('sys.stdout', new_callable=io.StringIO) as out:
            self.manager.list_sessions()
            self.assertIn('No tmux server', out.getvalue())
            bootstrap.assert_not_called()
        for name in ['', '-bad', 'a.b', 'a:b', 'bad\nname']:
            with self.subTest(name=name), patch.object(self.manager, 'ensure_active') as ensure:
                with self.assertRaises(store.StoreError): self.manager.attach(name)
                with self.assertRaises(store.StoreError): self.manager.delete(name)
                ensure.assert_not_called()

    def test_exact_name_resolution_and_delete_id(self):
        rows = [{'session_name': 'work', 'session_id': '$1'}, {'session_name': 'workshop', 'session_id': '$2'}]
        with patch.object(self.manager, 'query', return_value=rows):
            self.assertEqual(self.manager.session_id(self.runtime, 'work'), '$1')
            self.assertIsNone(self.manager.session_id(self.runtime, 'wor'))
            with patch.object(self.manager, 'ensure_active', return_value=self.active), patch.object(self.manager, 'command') as command:
                self.manager.delete('work')
                command.assert_called_once_with(self.runtime, ['kill-session', '-t', '$1'])

    def test_protocol_failure_never_creates(self):
        with patch.object(self.manager, 'ensure_active', side_effect=store.StoreError('protocol mismatch')), \
             patch.object(self.manager, 'bootstrap') as bootstrap:
            with self.assertRaises(store.StoreError): self.manager.attach('work')
            bootstrap.assert_not_called()

    def test_rmux_attach_refuses_before_any_native_probe(self):
        with patch.dict(os.environ, {'RMUX': '/rmux,10,1', 'TMUX': '/rmux,10,1', 'TMUX_PANE': '%1'}), \
             patch.object(self.manager, 'ensure_active') as ensure:
            with self.assertRaisesRegex(store.StoreError, 'detach first'): self.manager.attach('work')
            ensure.assert_not_called()

    def test_native_attach_switches_explicit_client_and_clears_identity(self):
        with patch.dict(os.environ, {'TMUX': self.manager.socket + ',42,1', 'TMUX_PANE': '%3'}), \
             patch.object(self.manager, 'ensure_active', return_value=self.active), \
             patch.object(self.manager, 'session_id', return_value='$2'), \
             patch.object(self.manager, 'calling_client', return_value='/dev/ttys123'), \
             patch.object(store.os, 'execve') as execute:
            self.manager.attach('work')
            argv, env = execute.call_args.args[1:]
            self.assertIn('switch-client', argv)
            self.assertEqual(argv[-4:], ['-c', '/dev/ttys123', '-t', '$2'])
            self.assertNotIn('TMUX', env)
            self.assertNotIn('TMUX_PANE', env)

    def test_outer_attach_is_not_switch(self):
        with patch.object(self.manager, 'ensure_active', return_value=self.active), \
             patch.object(self.manager, 'session_id', return_value='$1'), patch.object(store.os, 'execve') as execute:
            self.manager.attach('work')
            self.assertIn('attach-session', execute.call_args.args[1])

    def test_rename_uses_current_pane_and_literal_hashes(self):
        with patch.dict(os.environ, {'TMUX': self.manager.socket + ',42,1', 'TMUX_PANE': '%3'}), \
             patch.object(self.manager, 'ensure_active', return_value=self.active), \
             patch.object(self.manager, 'command') as command:
            self.manager.rename('#{pid} #(id);')
            command.assert_called_once_with(self.runtime, ['rename-window', '-t', '%3', '--', '##{pid} ##(id)\\;'])

    def test_confirmation_cancel_keeps_server_and_snapshot(self):
        self.manager.write_json('snapshot.json', {'old': True})
        with patch.object(self.manager, 'ensure_active', return_value=self.active), \
             patch.object(self.manager, 'installed_runtime', return_value=self.runtime), \
             patch.object(self.manager, 'capture', return_value=snapshot()), \
             patch.object(self.manager, 'preflight'), patch('sys.stdin.isatty', return_value=True), \
             patch('builtins.input', return_value='no'), patch.object(self.manager, 'launch_worker') as launch:
            self.manager.restart()
            launch.assert_not_called()
        self.assertIsNone(self.manager.read_json('operation.json'))
        self.assertEqual(self.manager.read_json('snapshot.json'), {'old': True})

    def operation(self):
        saved = snapshot()
        operation = {'version': 1, 'id': 'a' * 32, 'phase': 'prepared', 'old': self.active,
                     'runtime': self.runtime, 'snapshot_hash': store.snapshot_hash(saved)}
        self.manager.write_json('snapshot.json', saved)
        self.manager.write_json('operation.json', operation)
        return operation

    def test_worker_generation_race_never_kills(self):
        operation = self.operation()
        with patch.object(self.manager, 'validate_runtime', return_value=self.runtime), \
             patch.object(self.manager, 'preflight'), \
             patch.object(self.manager, 'probe', return_value=dict(self.server, start='101.000001')), \
             patch.object(self.manager, 'command') as command:
            with self.assertRaisesRegex(store.StoreError, 'generation'): self.manager.worker(operation['id'])
            command.assert_not_called()
        self.assertEqual(self.manager.read_json('operation.json')['phase'], 'cancelled')
        self.assertEqual(self.manager.read_json('snapshot.json'), snapshot())

    def test_worker_rechecks_after_capture_immediately_before_kill(self):
        operation = self.operation()
        with patch.object(self.manager, 'validate_runtime', return_value=self.runtime), \
             patch.object(self.manager, 'preflight'), patch.object(self.manager, 'verify_process'), \
             patch.object(self.manager, 'capture', return_value=snapshot()), \
             patch.object(self.manager, 'probe', side_effect=[self.server, dict(self.server, pid=99)]), \
             patch.object(self.manager, 'command') as command:
            with self.assertRaisesRegex(store.StoreError, 'generation'): self.manager.worker(operation['id'])
            command.assert_not_called()

    def test_retry_never_kills_partial_server_or_overwrites_snapshot(self):
        operation = self.operation()
        operation['phase'] = 'failed'
        self.manager.write_json('operation.json', operation)
        with patch.object(self.manager, 'validate_runtime', return_value=self.runtime), \
             patch.object(self.manager, 'probe', return_value=self.server), \
             patch.object(self.manager, 'command') as command:
            with self.assertRaisesRegex(store.StoreError, 'still runs'): self.manager.restart()
            command.assert_not_called()
        self.assertEqual(self.manager.read_json('snapshot.json'), snapshot())

    def test_malformed_recovery_records_fail_before_commands(self):
        for malformed in ([], 'invalid', {'version': 1}, {'version': 1, 'phase': 'failed'}):
            with self.subTest(record=malformed):
                self.manager.write_json('operation.json', malformed)
                with patch.object(self.manager, 'command') as command:
                    with self.assertRaises(store.StoreError): self.manager.restart()
                    command.assert_not_called()
        operation = self.operation()
        operation['phase'] = 'failed'
        for malformed in ({'version': 1}, [1]):
            with self.subTest(active=malformed):
                self.manager.write_json('active.json', malformed)
                with patch.object(self.manager, 'validate_runtime', return_value=self.runtime), \
                     patch.object(self.manager, 'command') as command:
                    with self.assertRaises(store.StoreError): self.manager.retry_restart(operation)
                    command.assert_not_called()

    def test_client_rejects_endpoint_overrides(self):
        for args in [[], ['-S', '/unrelated', 'kill-server'], ['-Lother', 'list-sessions']]:
            with self.subTest(args=args), patch.object(self.manager, 'ensure_active') as ensure:
                with self.assertRaises(store.StoreError): self.manager.client(args)
                ensure.assert_not_called()

    def test_cli_rejects_restart_arguments(self):
        with patch.object(store, 'Store') as factory:
            self.assertEqual(store.main(['restart', 'anything']), 2)
            factory.assert_not_called()


BINARY = next((str(path) for path in (Path('/opt/homebrew/bin/tmux'), Path('/usr/local/bin/tmux')) if path.exists()), None)


@unittest.skipUnless(os.environ.get('TMUX_STORE_RUNTIME_TESTS') == '1' and BINARY and sys.platform == 'darwin',
                     'opt-in disposable native runtime tests')
class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='tmux-store-runtime-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.config = self.home / 'tmux.conf'
        self.config.write_text('set -g default-shell /bin/sh\nset -w -g automatic-rename off\nset -g status off\n')
        self.environment = patch.dict(os.environ, {'HOME': str(self.home), 'TERM': 'xterm-256color'})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        for key in ('RMUX', 'RMUX_PANE', 'TMUX', 'TMUX_PANE'): os.environ.pop(key, None)
        self.manager = store.Store(home=self.home, installed=BINARY, socket=self.home / 'socket', config=self.config)
        self.runtime = self.manager.installed_runtime()
        shell = patch.object(store.pwd, 'getpwuid', return_value=type('Account', (), {'pw_shell': '/bin/sh'})())
        shell.start()
        self.addCleanup(shell.stop)
        self.addCleanup(lambda: self.manager.run(self.runtime, ['kill-server']))

    def test_private_first_launch_creates_owned_socket_directory(self):
        socket = self.home / 'new' / 'sock'
        manager = store.Store(home=self.home, installed=BINARY, socket=socket, config=self.config)
        self.addCleanup(lambda: manager.run(self.runtime, ['kill-server']))
        with patch('sys.stdout', new_callable=io.StringIO): manager.list_sessions()
        self.assertFalse(socket.parent.exists(), 'listing created runtime directories')
        manager.bootstrap(self.runtime, 'first')
        self.assertTrue(socket.is_socket())
        self.assertEqual(socket.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(manager.process_info(manager.probe(self.runtime)['pid'])['ppid'], 1)

    def test_private_client_close_preserves_ppid1_panes_and_processes(self):
        import fcntl
        import select
        import struct
        import termios
        import time

        self.manager.bootstrap(self.runtime, 'survivor', cwd=str(self.home))
        self.manager.record_active(self.runtime)
        server = self.manager.probe(self.runtime)
        self.assertEqual(self.manager.process_info(server['pid'])['ppid'], 1)
        sid = self.manager.session_id(self.runtime, 'survivor')
        pane, pane_pid = self.manager.command(self.runtime, ['list-panes', '-t', sid, '-F', '#{pane_id}|#{pane_pid}']).split('|')
        marker = self.home / 'marker.pid'
        self.manager.command(self.runtime, ['send-keys', '-t', pane, '-l', '/bin/sleep 60 & printf "%s" $! > marker.pid'])
        self.manager.command(self.runtime, ['send-keys', '-t', pane, 'Enter'])
        deadline = time.monotonic() + 5
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertTrue(marker.exists(), self.manager.command(self.runtime, ['capture-pane', '-p', '-t', pane]))
        marker_pid = int(marker.read_text())
        marker_start = self.manager.process_info(marker_pid)['start']

        def attach_client():
            master, slave = os.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
            client = subprocess.Popen(self.manager.argv(self.runtime, ['attach-session', '-t', sid]),
                                      env=self.manager.environment(), stdin=slave, stdout=slave, stderr=slave,
                                      start_new_session=True)
            os.close(slave)
            try:
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    if select.select([master], [], [], .03)[0]:
                        try: data = os.read(master, 65536)
                        except OSError: data = b''
                        if b'\x1b[c' in data:
                            os.write(master, b'\x1b[?1;2c\x1b[>0;1;0c')
                    rows = self.manager.query(self.runtime, ['list-clients', '-t', sid], {'client_pid': 'int', 'session_id': '$'})
                    if any(row == {'client_pid': client.pid, 'session_id': sid} for row in rows):
                        return client, master
                    self.assertIsNone(client.poll(), 'private PTY client exited before attaching')
                self.fail('private PTY client did not attach')
            except BaseException:
                os.close(master)
                if client.poll() is None: client.terminate()
                client.wait(timeout=5)
                raise

        first_client, master = attach_client()
        os.close(master)
        try:
            first_client.wait(timeout=5)
        except subprocess.TimeoutExpired:
            first_client.terminate()
            first_client.wait(timeout=5)
        self.assertEqual(self.manager.probe(self.runtime), server)
        self.assertEqual(self.manager.process_info(server['pid'])['ppid'], 1)
        self.assertEqual(self.manager.command(self.runtime, ['display-message', '-p', '-t', pane, '#{pane_pid}']), pane_pid)
        self.assertEqual(self.manager.process_info(marker_pid)['start'], marker_start)
        self.assertEqual(self.manager.session_id(self.runtime, 'survivor'), sid)
        second_client, master = attach_client()
        os.close(master)
        try:
            second_client.wait(timeout=5)
        except subprocess.TimeoutExpired:
            second_client.terminate()
            second_client.wait(timeout=5)
        print(f'Private PTY close/reattach: server={server["pid"]} PPID=1, pane={pane_pid}, marker={marker_pid}; all unchanged.')

    def test_private_deleted_executable_is_adopted_then_restarted(self):
        import shutil
        old = self.home / 'old-keg' / 'tmux'
        old.parent.mkdir()
        shutil.copy2(Path(BINARY).resolve(), old)
        old_runtime = self.manager.runtime_at(old)
        self.manager.bootstrap(old_runtime, 'kept', cwd=str(self.home))
        recorded = self.manager.record_active(old_runtime)
        old.unlink()
        self.assertIsNone(self.manager.process_info(recorded['server']['pid'])['path'])
        with patch('sys.stderr', new_callable=io.StringIO) as err:
            active = self.manager.ensure_active()
        self.assertEqual(active, {'version': 1, 'runtime': self.runtime, 'server': recorded['server']})
        self.assertIn('adopted running tmux', err.getvalue())
        self.assertIn('adopted server pid', (self.manager.state / 'recovery.log').read_text())
        with patch('sys.stdout', new_callable=io.StringIO) as out:
            self.manager.list_sessions()
        self.assertIn('kept: 1 windows', out.getvalue())
        with patch('sys.stdin.isatty', return_value=True), patch('builtins.input', return_value='yes'), \
             patch.object(self.manager, 'launch_worker') as launch, patch('sys.stdout', new_callable=io.StringIO):
            self.manager.restart()
        with patch('sys.stdout', new_callable=io.StringIO):
            self.manager.worker(launch.call_args.args[0]['id'])
        self.assertEqual(self.manager.read_json('operation.json')['phase'], 'complete')
        server = self.manager.probe(self.runtime)
        self.assertNotEqual(server['pid'], recorded['server']['pid'])
        self.assertEqual(Path(self.manager.process_info(server['pid'])['path']).resolve(), Path(self.runtime['path']))
        self.assertIsNotNone(self.manager.session_id(self.runtime, 'kept'))

    def test_private_backslash_names_roundtrip_and_exact_delete(self):
        name = 'work\\path'
        with patch.object(store.os, 'execve'):
            self.manager.attach(name)
            self.manager.attach(name)
        sid = self.manager.session_id(self.runtime, name)
        self.assertIsNotNone(sid)
        self.assertEqual(len(self.manager.query(self.runtime, ['list-sessions'], store.SESSION)), 1)
        pane = self.manager.command(self.runtime, ['list-panes', '-t', sid, '-F', '#{pane_id}'])
        server = self.manager.probe(self.runtime)
        with patch.dict(os.environ, {'TMUX': self.manager.socket + f',{server["pid"]},0', 'TMUX_PANE': pane}):
            self.manager.rename('雪 \\ #{pid};')
        before = self.manager.capture(self.runtime)
        for _ in range(2):
            self.manager.command(self.runtime, ['kill-server'])
            self.manager.wait_absent(self.runtime)
            self.manager.restore(self.runtime, before)
            self.assertEqual(store.structural(self.manager.capture(self.runtime)), store.structural(before))
        self.manager.delete(name)
        self.manager.wait_absent(self.runtime)

    def test_private_roundtrip_multiple_sessions_windows_and_literal_names(self):
        self.config.write_text(self.config.read_text() + 'set -g renumber-windows on\n')
        with patch('sys.stdout', new_callable=io.StringIO): self.manager.list_sessions()
        self.assertFalse(Path(self.manager.socket).exists())
        self.manager.bootstrap(self.runtime, 'alpha work', width=160, height=48, cwd=str(self.home))
        ids = self.manager.command(self.runtime, ['display-message', '-p', '#{session_id}|#{pane_id}']).split('|')
        sid, pane = ids
        self.manager.command(self.runtime, ['split-window', '-h', '-t', pane, '-c', str(self.home)])
        self.manager.command(self.runtime, ['split-window', '-v', '-t', pane, '-c', str(self.home)])
        self.manager.command(self.runtime, ['new-window', '-d', '-t', sid + ':5', '-n', 'extra', '-c', str(self.home)])
        self.manager.command(self.runtime, ['new-session', '-d', '-s', 'beta', '-c', str(self.home)])
        self.manager.command(self.runtime, ['select-window', '-t', sid + ':5'])
        active = self.manager.record_active(self.runtime)
        with patch.dict(os.environ, {'TMUX': self.manager.socket + f",{active['server']['pid']},0", 'TMUX_PANE': pane}):
            self.manager.rename('雪 #{pid} #(touch SHOULD_NOT_EXIST);')
        before = self.manager.capture(self.runtime)
        self.assertIn('雪 #{pid} #(touch SHOULD_NOT_EXIST);', [w['name'] for s in before['sessions'] for w in s['windows']])
        self.assertFalse((self.home / 'SHOULD_NOT_EXIST').exists())
        self.manager.command(self.runtime, ['kill-server'])
        self.manager.wait_absent(self.runtime)
        self.manager.restore(self.runtime, before)
        self.assertEqual(store.structural(self.manager.capture(self.runtime)), store.structural(before))
        self.assertEqual(self.manager.command(self.runtime, ['show-options', '-A', '-v', '-t', '$0', 'renumber-windows']), 'on')
        for row in self.manager.query(self.runtime, ['list-windows', '-a'], store.WINDOW):
            self.assertEqual(self.manager.command(self.runtime, ['show-options', '-wA', '-v', '-t', row['window_id'], 'window-size']),
                             self.manager.command(self.runtime, ['show-options', '-gwv', 'window-size']))
        self.assertEqual(self.manager.process_info(self.manager.probe(self.runtime)['pid'])['ppid'], 1)

    def test_private_restart_inside_pane_and_confirmation_cancel(self):
        import shlex
        import time
        driver = self.home / 'restart.py'
        driver.write_text('import sys\nsys.path.insert(0, ' + repr(str(MODULE.parent)) + ')\n'
                          'from store import Store\nStore(home=' + repr(str(self.home)) + ', installed=' + repr(BINARY) +
                          ', socket=' + repr(self.manager.socket) + ', config=' + repr(str(self.config)) + ').restart()\n')
        self.manager.bootstrap(self.runtime, 'caller', cwd=str(self.home))
        self.manager.command(self.runtime, ['new-session', '-d', '-s', 'detached', '-c', str(self.home)])
        self.manager.record_active(self.runtime)
        original = self.manager.probe(self.runtime)
        invocation = shlex.join([sys.executable, '-B', str(driver)])
        pane = self.manager.command(self.runtime, ['list-panes', '-a', '-F', '#{pane_id}']).splitlines()[0]

        def wait_for(predicate):
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                if predicate(): return
                time.sleep(.05)
            log = self.manager.state / 'restart.log'
            self.fail('timed out: ' + (log.read_text() if log.exists() else 'no worker log'))

        def output():
            return self.manager.command(self.runtime, ['capture-pane', '-p', '-t', pane])

        self.manager.command(self.runtime, ['send-keys', '-t', pane, '-l', invocation])
        self.manager.command(self.runtime, ['send-keys', '-t', pane, 'Enter'])
        wait_for(lambda: 'Type yes to continue:' in output())
        self.manager.command(self.runtime, ['send-keys', '-t', pane, 'no', 'Enter'])
        wait_for(lambda: 'Cancelled; no server stopped.' in output())
        self.assertEqual(self.manager.probe(self.runtime), original)
        self.assertIsNone(self.manager.read_json('operation.json'))
        self.manager.command(self.runtime, ['send-keys', '-t', pane, '-l', invocation])
        self.manager.command(self.runtime, ['send-keys', '-t', pane, 'Enter'])
        wait_for(lambda: output().count('Type yes to continue:') >= 2)
        self.manager.command(self.runtime, ['send-keys', '-t', pane, 'yes', 'Enter'])
        wait_for(lambda: (self.manager.read_json('operation.json') or {}).get('phase') in ('complete', 'failed', 'cancelled'))
        self.assertEqual(self.manager.read_json('operation.json')['phase'], 'complete',
                         (self.manager.state / 'restart.log').read_text())
        self.assertNotEqual(self.manager.probe(self.runtime)['pid'], original['pid'])
        saved = self.manager.read_json('snapshot.json')
        self.assertEqual([s['name'] for s in saved['sessions']], ['caller', 'detached'])
        self.assertEqual(store.structural(self.manager.capture(self.runtime)), store.structural(saved))
        self.assertEqual(self.manager.process_info(self.manager.probe(self.runtime)['pid'])['ppid'], 1)


if __name__ == '__main__': unittest.main()
