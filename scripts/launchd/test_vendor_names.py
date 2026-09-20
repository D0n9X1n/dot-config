#!/usr/bin/env python3
"""Offline tests: temporary homes and mocked signature/LaunchServices commands only."""
import base64
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name('vendor_names.py')
spec = importlib.util.spec_from_file_location('vendor_names', SCRIPT)
vendor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vendor)


class OverlayTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='vendor-names-')
        self.root = Path(self.tmp.name).resolve()
        self.home = self.root / 'home with spaces'
        self.home.mkdir(mode=0o700)
        self.system = self.root / 'system'
        self.system.mkdir()
        self.calls = []
        self.bad_signature = False
        self.team = None
        self.identifier = None
        self.overlay = vendor.Overlay(self.home, system=self.system, runner=self.runner)
        self.not_root = patch.object(vendor.os, 'geteuid', return_value=501)
        self.not_root.start()
        self.addCleanup(self.not_root.stop)
        self.addCleanup(self.tmp.cleanup)

    def runner(self, args, **kwargs):
        self.calls.append(args)
        self.assertNotIn('sudo', args)
        self.assertNotIn('launchctl', args)
        if args[0] == '/usr/bin/osascript':
            target = next(t for t in vendor.ASSOCIATIONS if json.dumps(t['bundle']) in args[-1])
            return subprocess.CompletedProcess(args, 0, str(self.system / target['app'].lstrip('/')), '')
        self.assertEqual(args[0], '/usr/bin/codesign')
        if '--verify' in args:
            return subprocess.CompletedProcess(args, int(self.bad_signature), '', 'invalid' if self.bad_signature else '')
        app = next((target for target in vendor.ASSOCIATIONS
                    if str(self.system / target['app'].lstrip('/')) in args[-1]),
                   vendor.ASSOCIATIONS[0])
        return subprocess.CompletedProcess(args, 0, '',
            'Identifier=' + (self.identifier or app['bundle']) + '\nTeamIdentifier=' +
            (self.team if self.team is not None else app['team']) + '\n')

    def proxy(self, index=0, **updates):
        target = vendor.PROXIES[index]
        path = self.home / 'Library/LaunchAgents' / (target['label'] + '.plist')
        path.parent.mkdir(parents=True, exist_ok=True)
        job = {'Label': target['label'], 'ProgramArguments': [target['binary'], *target['args']],
               'WorkingDirectory': str(self.home / '.V2rayU'),
               'KeepAlive': False, 'RunAtLoad': False, 'Disabled': True,
               'StandardOutPath': str(self.home / 'logs/output'), 'VendorExtra': {'keep': 1}}
        job.update(updates)
        path.write_bytes(plistlib.dumps(job, sort_keys=False))
        path.chmod(0o640)
        return path, job

    def association(self, index=0):
        target = vendor.ASSOCIATIONS[index]
        app = self.system / target['app'].lstrip('/')
        (app / 'Contents').mkdir(parents=True, exist_ok=True)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': target['bundle']}))
        if index == 0:
            path = self.home / 'Library/LaunchAgents' / (target['label'] + '.plist')
            executable = self.home / 'Library/Application Support/Steam/SteamApps/steamclean'
        else:
            path = self.system / 'Library/LaunchDaemons' / (target['label'] + '.plist')
            executable = app / 'Contents/MacOS/helper'
        path.parent.mkdir(parents=True, exist_ok=True)
        executable.parent.mkdir(parents=True, exist_ok=True)
        executable.write_bytes(b'fake signed binary')
        job = {'Label': target['label'], 'ProgramArguments': [str(executable), '--vendor-argument'],
               'RunAtLoad': False, 'KeepAlive': False, 'Disabled': True}
        if index == 0:
            job.update(Program=str(executable), ProgramArguments=[str(executable), 'Public'],
                       RunAtLoad=True, WatchPaths=[str(self.home / 'Steam.AppBundle/Steam')])
        elif index == 3:
            job['Program'] = job.pop('ProgramArguments')[0]
        elif index == 4:
            job['Program'] = str(executable)
        path.write_bytes(plistlib.dumps(job))
        return path, job, app

    def snapshot(self):
        return {str(p.relative_to(self.root)): (p.read_bytes(), p.stat().st_mode)
                for p in self.root.rglob('*') if p.is_file() and not p.is_symlink()}

    def test_preview_no_writes_and_fixed_allowlist(self):
        self.proxy()
        before = self.snapshot()
        output = self.overlay.run()
        self.assertEqual(before, self.snapshot())
        self.assertIn('PREVIEW', '\n'.join(output))
        self.assertIn('SKIP', '\n'.join(output))
        self.assertFalse((self.home / '.local').exists())
        self.assertEqual(len(vendor.PROXIES), 3)
        self.assertEqual(len(vendor.ASSOCIATIONS), 5)
        self.assertNotIn('tun-helper', repr(vendor.PROXIES) + repr(vendor.ASSOCIATIONS))
        self.assertNotIn('teamviewer', repr(vendor.ASSOCIATIONS).lower())

    def test_proxy_apply_changes_only_executable_and_preserves_disabled(self):
        fixtures = [self.proxy(i) for i in range(3)]
        self.overlay.run('apply')
        for i, (path, original) in enumerate(fixtures):
            current = plistlib.loads(path.read_bytes())
            launcher = self.home / '.local/libexec' / vendor.PROXIES[i]['name']
            expected = dict(original, ProgramArguments=[str(launcher), *original['ProgramArguments'][1:]])
            self.assertEqual(current, expected)
            self.assertEqual(path.stat().st_mode & 0o777, 0o640)
            self.assertEqual(launcher.stat().st_mode & 0o777, 0o700)
            self.assertIn('exec -a ', launcher.read_text())
            self.assertIn('"$@"', launcher.read_text())
        self.assertEqual(self.calls, [])

    def test_launcher_exec_preserves_original_argv0_arguments_cwd_and_pid(self):
        self.proxy()
        self.overlay.run('apply')
        cwd = self.home / '.V2rayU'
        (cwd / 'v2ray-core').mkdir(parents=True)
        (cwd / 'v2ray-core/v2ray').symlink_to('/bin/bash')
        launcher = self.home / '.local/libexec' / vendor.PROXIES[0]['name']
        env = {k: v for k, v in os.environ.items() if k not in ('BASH_ENV', 'ENV')}
        process = subprocess.Popen([str(launcher), '-c', 'printf "%s\\n" "$0" "$$" "$PWD"'],
                                   cwd=cwd, env=env, stdout=subprocess.PIPE, text=True)
        stdout, _ = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0)
        self.assertEqual(stdout.splitlines(), ['./v2ray-core/v2ray', str(process.pid), str(cwd)])

    def test_backup_exact_private_idempotency_and_rollback(self):
        path, _ = self.proxy()
        original = path.read_bytes()
        self.overlay.run('apply')
        before = self.snapshot()
        self.overlay.run('apply')
        self.assertEqual(before, self.snapshot())
        state = self.home / '.local/state/dot-configs/startup-names'
        self.assertEqual(state.stat().st_mode & 0o777, 0o700)
        record = next(state.glob('*.json'))
        self.assertEqual(record.stat().st_mode & 0o777, 0o600)
        self.assertEqual(base64.b64decode(json.loads(record.read_text())['original']), original)
        self.overlay.run('rollback')
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual(path.stat().st_mode & 0o777, 0o640)
        self.assertFalse((self.home / '.local/libexec' / vendor.PROXIES[0]['name']).exists())
        self.overlay.run('rollback')
        self.overlay.run('apply')
        self.assertNotEqual(path.read_bytes(), original)

    def test_vendor_change_refused_on_apply_and_rollback(self):
        path, _ = self.proxy()
        self.overlay.run('apply')
        path.write_bytes(path.read_bytes() + b'\n')
        before = self.snapshot()
        for action in ['apply', 'rollback']:
            with self.subTest(action=action), self.assertRaises(vendor.Refusal):
                self.overlay.run(action)
        output = '\n'.join(self.overlay.run('preview'))
        self.assertIn('CONFLICT yanue.v2rayu.v2ray-core', output)
        self.assertEqual(before, self.snapshot())

    def test_missing_launcher_allows_rollback_but_not_apply(self):
        path, _ = self.proxy()
        original = path.read_bytes()
        self.overlay.run('apply')
        launcher = self.home / '.local/libexec' / vendor.PROXIES[0]['name']
        launcher.unlink()
        before = self.snapshot()
        with self.assertRaises(vendor.Refusal):
            self.overlay.run('apply')
        self.assertEqual(before, self.snapshot())
        self.overlay.run('rollback')
        self.assertEqual(path.read_bytes(), original)
        self.assertFalse(launcher.exists())
        self.assertEqual(path.stat().st_mode & 0o777, 0o640)

    def test_preview_continues_after_conflicting_and_missing_targets(self):
        self.proxy(0, KeepAlive=True)
        self.proxy(2)
        self.association()
        before = self.snapshot()
        output = self.overlay.run('preview')
        self.assertEqual(len(output), 8)
        self.assertIn('CONFLICT yanue.v2rayu.v2ray-core', output[0])
        self.assertIn('SKIP USER yanue.v2rayu.xray-core', output[1])
        self.assertIn('USER PREVIEW yanue.v2rayu.sing-box', output[2])
        self.assertIn('USER PREVIEW com.valvesoftware.steamclean', output[3])
        self.assertEqual(before, self.snapshot())
        with self.assertRaises(vendor.Refusal):
            self.overlay.run('apply')
        self.assertEqual(before, self.snapshot())

    def test_unknown_launcher_never_overwritten_or_deleted(self):
        self.proxy()
        launcher = self.home / '.local/libexec' / vendor.PROXIES[0]['name']
        launcher.parent.mkdir(parents=True)
        launcher.write_text('unfamiliar')
        before = self.snapshot()
        with self.assertRaises(vendor.Refusal):
            self.overlay.run('apply')
        self.assertEqual(before, self.snapshot())
        launcher.unlink()
        self.overlay.run('apply')
        launcher.write_text('external change')
        before = self.snapshot()
        with self.assertRaises(vendor.Refusal):
            self.overlay.run('rollback')
        self.assertEqual(before, self.snapshot())

    def test_rejects_changed_label_args_cwd_flags_program(self):
        mutations = [{'Label': 'other'}, {'ProgramArguments': ['/bin/sh', '-c', 'anything']},
                     {'WorkingDirectory': '/tmp'}, {'RunAtLoad': True}, {'KeepAlive': {}},
                     {'Program': '/bin/sh'}, {'EnvironmentVariables': {'BASH_ENV': '/tmp/init'}}]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.proxy(**mutation)
                before = self.snapshot()
                with self.assertRaises(vendor.Refusal):
                    self.overlay.run('apply')
                self.assertEqual(before, self.snapshot())

    def test_file_and_ancestor_symlinks_rejected(self):
        path, _ = self.proxy()
        destination = self.home / 'original.plist'
        path.rename(destination)
        path.symlink_to(destination)
        with self.assertRaises(vendor.Refusal):
            self.overlay.run('apply')
        path.unlink()
        destination.rename(path)
        agents = path.parent
        other = self.home / 'agents'
        agents.rename(other)
        agents.symlink_to(other, target_is_directory=True)
        with self.assertRaises(vendor.Refusal):
            self.overlay.run('apply')

    def test_state_and_launcher_ancestor_symlinks_rejected(self):
        self.proxy()
        local = self.home / '.local'
        local.mkdir()
        outside = self.root / 'elsewhere'
        outside.mkdir()
        (local / 'state').symlink_to(outside, target_is_directory=True)
        with self.assertRaises(vendor.Refusal):
            self.overlay.run('apply')
        (local / 'state').unlink()
        (local / 'libexec').symlink_to(outside, target_is_directory=True)
        with self.assertRaises(vendor.Refusal):
            self.overlay.run('apply')
        self.assertEqual(list(outside.iterdir()), [])

    def test_foreign_ownership_and_unsafe_state_permissions_rejected(self):
        self.proxy()
        with patch.object(vendor.os, 'getuid', return_value=os.getuid() + 1):
            with self.assertRaises(vendor.Refusal):
                self.overlay.run('apply')
        self.overlay.run('apply')
        state = self.home / '.local/state/dot-configs/startup-names'
        state.chmod(0o755)
        with self.assertRaises(vendor.Refusal):
            self.overlay.run('rollback')

    def test_preflight_stops_all_writes_on_later_invalid_target(self):
        self.proxy(0)
        self.proxy(1, KeepAlive=True)
        before = self.snapshot()
        with self.assertRaises(vendor.Refusal):
            self.overlay.run('apply')
        self.assertEqual(before, self.snapshot())

    def test_steam_only_association_changes_and_signatures_verified(self):
        path, original, _ = self.association()
        self.overlay.run('apply')
        self.assertEqual(plistlib.loads(path.read_bytes()),
                         dict(original, AssociatedBundleIdentifiers=['com.valvesoftware.steam']))
        self.assertEqual(len({c[-1] for c in self.calls if '--verify' in c}), 2)
        self.assertEqual(len({c[-1] for c in self.calls if '-dv' in c}), 2)
        self.assertTrue(any('URLForApplicationWithBundleIdentifier' in ' '.join(c) for c in self.calls))
        self.assertFalse(any('-register' in c or '-unregister' in c for c in self.calls))

    def test_signed_identity_failures_are_closed(self):
        path, _, app = self.association()
        for team in ['', 'not set', 'WRONGTEAM']:
            with self.subTest(team=team):
                self.team = team
                with self.assertRaises(vendor.Refusal):
                    self.overlay.run('apply')
        self.team = None
        self.identifier = 'wrong.bundle'
        with self.assertRaises(vendor.Refusal):
            self.overlay.run('apply')
        self.identifier = None
        self.bad_signature = True
        with self.assertRaises(vendor.Refusal):
            self.overlay.run('apply')
        self.bad_signature = False
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'wrong.bundle'}))
        with self.assertRaises(vendor.Refusal):
            self.overlay.run('apply')
        self.assertNotIn('AssociatedBundleIdentifiers', plistlib.loads(path.read_bytes()))

    def test_launchservices_requires_exact_registered_app(self):
        self.association()
        good_runner = self.overlay.runner
        for result in ['', '/Applications/Another.app', None]:
            def runner(args, **kwargs):
                if args[0] == '/usr/bin/osascript':
                    return subprocess.CompletedProcess(args, int(result is None), result or '', '')
                return good_runner(args, **kwargs)
            with self.subTest(result=result), patch.object(self.overlay, 'runner', side_effect=runner):
                before = self.snapshot()
                with self.assertRaises(vendor.Refusal):
                    self.overlay.run('apply')
                self.assertEqual(before, self.snapshot())

    def test_conflicting_association_and_steam_executable_rejected(self):
        path, original, _ = self.association()
        path.write_bytes(plistlib.dumps(dict(original, AssociatedBundleIdentifiers=['wrong.bundle'])))
        with self.assertRaises(vendor.Refusal):
            self.overlay.run('apply')
        path.write_bytes(plistlib.dumps(dict(original, Program='/bin/sh')))
        with self.assertRaises(vendor.Refusal):
            self.overlay.run('apply')

    def test_system_associations_preview_only_even_with_apply(self):
        fixtures = [self.association(i) for i in range(1, 5)]
        before = self.snapshot()
        output = self.overlay.run('apply')
        self.assertEqual(before, self.snapshot())
        self.assertEqual(sum('SYSTEM PREVIEW' in line for line in output), 4)
        for path, original, _ in fixtures:
            self.assertEqual(plistlib.loads(path.read_bytes()), original)

    def test_missing_signed_app_skips_and_rollback_does_not_need_app(self):
        path, original, app = self.association()
        self.overlay.run('apply')
        app.rename(app.with_name('missing'))
        self.overlay.run('rollback')
        self.assertEqual(plistlib.loads(path.read_bytes()), original)
        self.assertIn('SKIP', '\n'.join(self.overlay.run('apply')))

    def test_apply_and_rollback_refuse_root_before_any_command(self):
        self.proxy()
        with patch.object(vendor.os, 'geteuid', return_value=0):
            for action in ['apply', 'rollback']:
                with self.assertRaises(vendor.Refusal):
                    self.overlay.run(action)
        self.assertEqual(self.calls, [])
        self.assertFalse((self.home / '.local').exists())

    def test_atomic_replace_refuses_change_after_preflight(self):
        path, _ = self.proxy()
        original_replace = self.overlay.replace
        def race(path_arg, expected, data, mode):
            if path_arg == path:
                path.write_bytes(b'external vendor replacement')
            return original_replace(path_arg, expected, data, mode)
        with patch.object(self.overlay, 'replace', side_effect=race):
            with self.assertRaises(vendor.Refusal):
                self.overlay.run('apply')
        self.assertEqual(path.read_bytes(), b'external vendor replacement')

    def test_cli_has_no_arbitrary_targets_and_defaults_to_preview(self):
        with patch.object(vendor, 'Overlay', return_value=self.overlay):
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(vendor.main([]), 0)
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                vendor.main(['--target', '/tmp/anything'])
        self.assertFalse((self.home / '.local').exists())


if __name__ == '__main__':
    unittest.main()
