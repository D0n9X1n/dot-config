#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import store


def layout(body):
    checksum = 0
    for char in body:
        checksum = (((checksum >> 1) | ((checksum & 1) << 15)) + ord(char)) & 0xffff
    return f"{checksum:04x},{body}"


def workspace():
    return ([{'session_name': 'a', 'session_id': '$0', 'session_windows': 1, 'session_grouped': False}],
            [{'session_name': 'a', 'window_index': 0, 'window_id': '@0', 'window_name': 'work',
              'window_width': 80, 'window_height': 24, 'window_panes': 2, 'window_active': True,
              'window_layout': layout('80x24,0,0{39x24,0,0,7,40x24,40,0,2}')}],
            [{'session_name': 'a', 'window_index': 0, 'pane_id': '%7', 'pane_index': 0,
              'pane_width': 39, 'pane_height': 24, 'pane_active': False,
              'pane_current_path': '/tmp', 'pane_current_command': 'SECRET'},
             {'session_name': 'a', 'window_index': 0, 'pane_id': '%2', 'pane_index': 1,
              'pane_width': 40, 'pane_height': 24, 'pane_active': True, 'pane_current_path': '/tmp'}])


class LayoutTests(unittest.TestCase):
    def test_nested_leaf_order(self):
        value = layout('160x48,0,0{80x48,0,0[80x24,0,0,0,80x23,0,25,2],79x48,81,0,1}')
        self.assertEqual([x['id'] for x in store.parse_layout(value)], [0, 2, 1])

    def test_invalid_checksum(self):
        with self.assertRaises(store.StoreError): store.parse_layout('0000,80x24,0,0,1')

    def test_malformed_tree_and_geometry(self):
        for body in ['80x24,0,0{39x24,0,0,1}', '80x24,0,0{39x24,0,0,1,40x24,39,0,2}',
                     '80x24,0,0,1trailing', '80x24,0,0{39x24,0,0,1,40x24,40,0,1}']:
            with self.subTest(body=body), self.assertRaises(store.StoreError): store.parse_layout(layout(body))


class SnapshotTests(unittest.TestCase):
    def test_whitelist_and_leaf_order(self):
        result = store.make_snapshot(*workspace())
        self.assertNotIn('SECRET', json.dumps(result))
        self.assertEqual(result['version'], 1)
        self.assertEqual([p['width'] for p in result['sessions'][0]['windows'][0]['panes']], [39, 40])
        self.assertEqual(store.validate_snapshot(result), result)

    def test_reject_counts_links_unknown_relationships(self):
        for field in ['count', 'linked', 'pane', 'active', 'grouped']:
            sessions, windows, panes = workspace()
            if field == 'count': sessions[0]['session_windows'] = 4
            if field == 'linked': windows.append(dict(windows[0], window_index=1))
            if field == 'pane': panes[1]['window_index'] = 9
            if field == 'active': panes[0]['pane_active'] = True
            if field == 'grouped': sessions[0]['session_grouped'] = True
            with self.subTest(field=field), self.assertRaises(store.StoreError): store.make_snapshot(sessions, windows, panes)

    def test_empty_valid(self):
        self.assertEqual(store.make_snapshot([], [], [])['sessions'], [])

    def test_saved_schema_is_strict(self):
        result = store.make_snapshot(*workspace())
        result['environment'] = {'TOKEN': 'no'}
        with self.assertRaises(store.StoreError): store.validate_snapshot(result)

    def test_reject_name_control_and_non_absolute_cwd(self):
        for name in ['', '-bad', 'a:b', 'a.b', 'line\nbreak']:
            sessions, windows, panes = workspace()
            sessions[0]['session_name'] = name
            with self.subTest(name=name), self.assertRaises(store.StoreError): store.make_snapshot(sessions, windows, panes)
        sessions, windows, panes = workspace()
        panes[0]['pane_current_path'] = 'relative'
        with self.assertRaises(store.StoreError): store.make_snapshot(sessions, windows, panes)


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='rmux-store-unit-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        for name in ['rmux', 'rmux-daemon']:
            (self.bin / name).write_bytes((name + '-test').encode())
            (self.bin / name).chmod(0o755)
        self.store = store.Store(home=self.home, installed=self.bin / 'rmux', socket=self.home / 'sock')

    def retain(self):
        with patch.object(self.store, 'check_dependencies'): return self.store.retain_installed()

    def test_private_atomic_metadata_and_previous(self):
        self.store.write_json('snapshot.json', {'a': 1}, previous=True)
        self.store.write_json('snapshot.json', {'a': 2}, previous=True)
        self.assertEqual(self.store.read_json('snapshot.json.prev'), {'a': 1})
        self.assertEqual(self.store.state.stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.store.state / 'snapshot.json').stat().st_mode & 0o777, 0o600)

    def test_symlink_reads_and_writes_refused(self):
        target = self.home / 'target'
        target.write_text('{}')
        (self.store.state / 'active.json').symlink_to(target)
        for action in [lambda: self.store.read_json('active.json'), lambda: self.store.write_json('active.json', {})]:
            with self.assertRaises(store.StoreError): action()
        self.assertEqual(target.read_text(), '{}')

    def test_lock_is_nonblocking(self):
        other = store.Store(home=self.home, installed=self.bin / 'rmux', socket=self.home / 'sock')
        with self.store.lock():
            with self.assertRaisesRegex(store.StoreError, 'busy'):
                with other.lock(): pass

    def test_retains_pair_and_modes_immutable_hash(self):
        first = self.retain()
        self.assertEqual((Path(first['path']) / 'rmux-daemon').read_bytes(), b'rmux-daemon-test')
        self.assertEqual((Path(first['path']) / 'rmux').stat().st_mode & 0o777, 0o755)
        (self.bin / 'rmux').write_bytes(b'new')
        second = self.retain()
        self.assertNotEqual(first['hash'], second['hash'])
        self.assertEqual((Path(first['path']) / 'rmux').read_bytes(), b'rmux-test')

    def test_non_system_dependency_refused(self):
        output = subprocess.CompletedProcess([], 0, '/bin/rmux:\n\t@rpath/libbad.dylib (compatibility version 1)\n', '')
        with patch('store.platform.system', return_value='Darwin'), patch('store.subprocess.run', return_value=output):
            with self.assertRaises(store.StoreError): self.store.check_dependencies(self.bin / 'rmux')
        with patch('store.platform.system', return_value='Linux'):
            with self.assertRaisesRegex(store.StoreError, 'Darwin'): self.store.check_dependencies(self.bin / 'rmux')

    def test_unknown_server_fingerprint_refused(self):
        runtime = self.retain()
        with patch.object(self.store, 'retain_installed', return_value=runtime), \
             patch.object(self.store, 'probe', return_value={'pid': 42, 'socket': str(self.home / 'sock'), 'start': 'now'}), \
             patch.object(self.store, 'verify_process', side_effect=store.StoreError('fingerprint mismatch')):
            with self.assertRaisesRegex(store.StoreError, 'fingerprint'): self.store.prepare()
        self.assertIsNone(self.store.read_json('active.json'))

    def test_verified_generation_survives_homebrew_cleanup(self):
        runtime = self.retain()
        server = {'pid': 42, 'socket': '/socket', 'start': 'verified start'}
        self.store.write_json('active.json', {'version': 1, 'runtime': runtime, 'server': server})
        with patch.object(self.store, 'process_info', return_value={'start': server['start']}), \
             patch('store.subprocess.run') as inspect:
            self.store.verify_process(runtime, server)
            inspect.assert_not_called()

    def test_help_is_helpers_only(self):
        self.assertIn('PPID 1', store.HELP)
        self.assertIn('brew upgrade rmux', store.HELP)
        self.assertNotIn('rmux ARGS', store.HELP)
        self.assertNotIn('prepare records', store.HELP)

    def test_protocol_error_never_bootstraps(self):
        with patch.object(self.store, 'ensure_active', side_effect=store.StoreError('protocol mismatch')), \
             patch.object(self.store, 'bootstrap') as bootstrap:
            with self.assertRaises(store.StoreError): self.store.rr('main')
            bootstrap.assert_not_called()

    def test_exact_session_resolution(self):
        runtime = self.retain()
        with patch.object(self.store, 'json_command', return_value=[{'session_name': 'work', 'session_id': '$1'}, {'session_name': 'workshop', 'session_id': '$2'}]):
            self.assertEqual(self.store.session_id(runtime, 'work'), '$1')
            self.assertIsNone(self.store.session_id(runtime, 'wor'))

    def test_explicit_endpoint_passthrough(self):
        for args in [['-L', 'other', 'ls'], ['-S/tmp/socket', 'ls'], ['-Lother', 'ls']]: self.assertTrue(self.store.foreign(args))
        with patch.dict(os.environ, {'RMUX': '/foreign,1,0'}): self.assertTrue(self.store.foreign(['ls']))

    def test_unavailable_vs_protocol(self):
        runtime = self.retain()
        for message, unavailable in [('error connecting to /x (No such file or directory)', True),
                                     ('error connecting to /x (Connection refused)', True),
                                     ('no server running on /private/tmp/rmux-501/default', True),
                                     ('protocol version mismatch', False), ('permission denied', False)]:
            with patch.object(self.store, 'run', return_value=subprocess.CompletedProcess([], 1, '', message)):
                if unavailable: self.assertIsNone(self.store.probe(runtime))
                else:
                    with self.assertRaises(store.StoreError): self.store.probe(runtime)

    def test_saved_partial_state_not_overwritten(self):
        self.store.write_json('snapshot.json', {'original': True})
        self.store.write_json('operation.json', {'phase': 'failed'})
        with patch.object(self.store, 'retry_restart', return_value=None) as retry:
            self.store.restart()
            retry.assert_called_once()
        self.assertEqual(self.store.read_json('snapshot.json'), {'original': True})

    def test_worker_refuses_changed_generation_before_kill(self):
        runtime = self.retain()
        snapshot = store.make_snapshot(*workspace())
        operation = {'version': 1, 'id': 'a' * 32, 'phase': 'prepared',
                     'runtime': runtime, 'old': {'runtime': runtime, 'server': {'pid': 42, 'start': 'old', 'socket': '/x'}},
                     'snapshot_hash': store.hashlib.sha256(json.dumps(snapshot, sort_keys=True).encode()).hexdigest()}
        self.store.write_json('snapshot.json', snapshot)
        self.store.write_json('operation.json', operation)
        with patch.object(self.store, 'probe', return_value={'pid': 42, 'start': 'new', 'socket': '/x'}), \
             patch.object(self.store, 'command') as command:
            with self.assertRaisesRegex(store.StoreError, 'generation'): self.store.worker(operation['id'])
            command.assert_not_called()
        self.assertEqual(self.store.read_json('snapshot.json'), snapshot)
        self.assertEqual(self.store.read_json('operation.json')['phase'], 'cancelled')
        with patch.object(self.store, 'ensure_active', return_value={'server': None}), \
             patch.object(self.store, 'retry_restart') as retry:
            self.store.restart()
            retry.assert_not_called()

    def test_restart_rejects_parameters(self):
        with patch('store.Store') as factory:
            self.assertEqual(store.main(['restart', 'anything']), 2)
            factory.assert_not_called()


@unittest.skipUnless(os.environ.get('RMUX_STORE_INTEGRATION') == '1' and Path('/opt/homebrew/bin/rmux').exists(), 'opt-in disposable runtime test')
class RuntimeTests(unittest.TestCase):
    def test_restart_from_inside_pane_and_cancellation(self):
        import shlex
        import time
        with tempfile.TemporaryDirectory(prefix='rmux-store-worker-') as root:
            home = Path(root).resolve()
            config = home / '.rmux.conf'
            config.write_text('set -g default-shell /bin/sh\nset -w -g automatic-rename off\n')
            manager = store.Store(home=home, installed=Path('/opt/homebrew/bin/rmux'), socket=home / 'socket', config=config)
            driver = home / 'restart.py'
            driver.write_text('import sys\nsys.path.insert(0, ' + repr(str(Path(store.__file__).parent)) + ')\n'
                              'from store import Store\nStore(home=' + repr(str(home)) + ', socket=' +
                              repr(str(home / 'socket')) + ', config=' + repr(str(config)) + ').restart()\n')
            with patch.dict(os.environ, {'HOME': str(home)}):
                runtime = manager.prepare()['runtime']
                try:
                    manager.bootstrap(runtime, 'caller', cwd=str(home))
                    manager.command(runtime, ['new-session', '-d', '-s', 'detached', '-c', str(home)])
                    manager.record_active(runtime)
                    original = manager.probe(runtime)
                    invocation = shlex.join([sys.executable, '-B', str(driver)])
                    def wait_for(predicate):
                        deadline = time.monotonic() + 15
                        while time.monotonic() < deadline:
                            if predicate():
                                return
                            time.sleep(.05)
                        self.fail('timed out; worker log: ' + ((manager.state / 'restart.log').read_text() if (manager.state / 'restart.log').exists() else 'none'))
                    def prompt():
                        return 'Type yes to continue:' in manager.command(runtime, ['capture-pane', '-p', '-t', '$0:0'])
                    manager.command(runtime, ['send-keys', '-t', '$0:0', invocation, 'Enter'])
                    wait_for(prompt)
                    manager.command(runtime, ['send-keys', '-t', '$0:0', 'no', 'Enter'])
                    wait_for(lambda: 'Cancelled; no server stopped.' in manager.command(runtime, ['capture-pane', '-p', '-t', '$0:0']))
                    self.assertEqual(manager.probe(runtime), original)
                    self.assertIsNone(manager.read_json('operation.json'))
                    manager.command(runtime, ['clear-history', '-t', '$0:0'])
                    manager.command(runtime, ['send-keys', '-t', '$0:0', invocation, 'Enter'])
                    time.sleep(.2)
                    manager.command(runtime, ['send-keys', '-t', '$0:0', 'yes', 'Enter'])
                    wait_for(lambda: (manager.read_json('operation.json') or {}).get('phase') in ('complete', 'failed'))
                    operation = manager.read_json('operation.json')
                    self.assertEqual(operation['phase'], 'complete', (manager.state / 'restart.log').read_text() + '\nSAVED ' + json.dumps(manager.read_json('snapshot.json')) + '\nLIVE ' + json.dumps(manager.capture(runtime)))
                    self.assertNotEqual(manager.probe(runtime)['pid'], original['pid'])
                    self.assertEqual(manager.process_info(manager.probe(runtime)['pid'])['ppid'], 1)
                    snapshot = manager.read_json('snapshot.json')
                    self.assertEqual([s['name'] for s in snapshot['sessions']], ['caller', 'detached'])
                    self.assertEqual(store.structural(manager.capture(runtime)), store.structural(snapshot))
                finally:
                    manager.run(runtime, ['kill-server'], no_start=True)

    def test_roundtrip_disposable_socket(self):
        with tempfile.TemporaryDirectory(prefix='rmux-store-runtime-') as root:
            home = Path(root).resolve()
            manager = store.Store(home=home, installed=Path('/opt/homebrew/bin/rmux'), socket=home / 'socket', config=Path('/dev/null'))
            try:
                active = manager.prepare()
                self.assertIsNone(active['server'])
                self.assertFalse((home / 'socket').exists())
                runtime = active['runtime']
                manager.bootstrap(runtime, 'alpha', width=160, height=48, cwd=str(home))
                manager.record_active(runtime)
                manager.command(runtime, ['split-window', '-h', '-t', '$0:0', '-c', str(home)])
                manager.command(runtime, ['split-window', '-v', '-t', '%0', '-c', str(home)])
                manager.command(runtime, ['new-window', '-d', '-t', '$0:5', '-n', 'extra', '-c', str(home)])
                manager.command(runtime, ['new-session', '-d', '-s', 'beta', '-c', str(home)])
                manager.command(runtime, ['select-window', '-t', '$0:5'])
                before = manager.capture(runtime)
                manager.command(runtime, ['kill-server'])
                manager.wait_absent(runtime)
                manager.restore(runtime, before)
                after = manager.capture(runtime)
                self.assertEqual(store.structural(before), store.structural(after))
                self.assertEqual(manager.process_info(manager.probe(runtime)['pid'])['ppid'], 1)
            finally:
                if 'runtime' in locals(): manager.run(runtime, ['kill-server'], no_start=True)


if __name__ == '__main__': unittest.main()
