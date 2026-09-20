#!/usr/bin/env python3
import json
import os
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name('copilot-relay-healthcheck.sh')
LAUNCHER = SCRIPT.with_name('Copilot Relay Health Check')
REPO = SCRIPT.parents[2]


def stub(kind):
    root = Path(os.environ['WATCHDOG_TEST_ROOT'])
    fixture = json.loads((root / 'fixture.json').read_text())
    events = root / 'events'
    previous = events.read_text().splitlines() if events.exists() else []
    with events.open('a') as log:
        log.write(json.dumps([kind, *sys.argv[3:]]) + '\n')
    if kind == 'curl':
        count = sum(json.loads(line)[0] == 'curl' for line in previous)
        codes = fixture['health']
        print(codes[min(count, len(codes) - 1)], end='')
    elif kind == 'probe':
        (root / 'probe.pid').write_text(str(os.getpid()))
        if fixture.get('hang'):
            import time
            time.sleep(30)
        print(fixture.get('output', '{}'))
        raise SystemExit(fixture['rc'])
    elif kind == 'launchctl':
        if sys.argv[3] == 'print':
            raise SystemExit(0 if fixture.get('loaded', True) else 1)
    else:
        raise AssertionError(kind)


class LauncherTests(unittest.TestCase):
    def test_template_keeps_job_identity_and_schedule(self):
        template = REPO / 'config/launchd/com.d0n9x1n.copilot-relay-healthcheck.plist'
        job = plistlib.loads(template.read_bytes())
        self.assertEqual(job['Label'], 'com.d0n9x1n.copilot-relay-healthcheck')
        self.assertEqual(job['ProgramArguments'], [
            '__HOME__/.local/libexec/Copilot Relay Health Check',
            '__REPO_ROOT__/scripts/launchd/copilot-relay-healthcheck.sh'])
        self.assertEqual(job['StartInterval'], 60)
        self.assertIs(job['RunAtLoad'], True)
        self.assertEqual(job['EnvironmentVariables']['PATH'],
                         '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin')
        self.assertEqual(job['WorkingDirectory'], '__HOME__')
        self.assertEqual(job['ProcessType'], 'Background')
        for key, suffix in [('StandardOutPath', 'out'), ('StandardErrorPath', 'err')]:
            self.assertEqual(job[key], f'__HOME__/Library/Logs/copilot-relay-healthcheck.{suffix}.log')
        self.assertIn('link\tscripts/launchd/Copilot Relay Health Check\t'
                      '.local/libexec/Copilot Relay Health Check\n',
                      (REPO / 'config/manifest.tsv').read_text())

    def test_launcher_preserves_bash_arguments_exit_and_pid(self):
        env = {k: v for k, v in os.environ.items() if k != 'BASH_ENV'}
        process = subprocess.Popen([
            str(LAUNCHER), '-c', 'printf "%s\\n" "$$" "$BASH" "$0" "$@"; exit 23',
            'name with spaces', 'argument with spaces', '', '*literal*'],
            env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 23, stderr)
        self.assertEqual(stdout.splitlines(), [str(process.pid), '/bin/bash',
                         'name with spaces', 'argument with spaces', '', '*literal*'])

    def test_scoped_install_twice_touches_only_healthcheck(self):
        with tempfile.TemporaryDirectory(prefix='healthcheck-install-') as root:
            home = Path(root) / 'home & space'
            home.mkdir()
            (home / '.copilot-relay').mkdir()
            (home / '.copilot-relay/github_token').touch()
            script = '''set -euo pipefail
DOT_CONFIGS_INSTALL_LIB_ONLY=1 source "$1/install.sh"
have_cmd() { return 0; }
launchctl() {
    printf '%s\\n' "$*" >>"$HOME/calls"
    case "$1" in
        print) test -f "$HOME/loaded" ;;
        bootout) rm -f "$HOME/loaded" ;;
        bootstrap) touch "$HOME/loaded" ;;
        kickstart) return 0 ;;
        *) return 1 ;;
    esac
}
install_copilot_relay_healthcheck 501
install_copilot_relay_healthcheck 501
'''
            result = subprocess.run(['/bin/bash', '-c', script, 'test', str(REPO)],
                                    env=dict(os.environ, HOME=str(home)), capture_output=True,
                                    text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            installed = home / '.local/libexec/Copilot Relay Health Check'
            self.assertTrue(installed.is_symlink())
            self.assertEqual(installed.resolve(), LAUNCHER.resolve())
            self.assertTrue(os.access(installed, os.X_OK))
            job = plistlib.loads((home / 'Library/LaunchAgents/'
                                  'com.d0n9x1n.copilot-relay-healthcheck.plist').read_bytes())
            self.assertEqual(job['ProgramArguments'], [str(installed), str(SCRIPT)])
            calls = (home / 'calls').read_text().splitlines()
            self.assertEqual(sum(call.startswith('bootstrap ') for call in calls), 2)
            self.assertEqual(sum(call.startswith('kickstart ') for call in calls), 2)
            for call in calls:
                self.assertIn('com.d0n9x1n.copilot-relay-healthcheck', call)


class WatchdogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='watchdog-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.events = self.root / 'events'
        self.log = self.root / 'health.log'
        self.stamp = self.root / 'deep.stamp'
        bootstrap = self.root / 'stubs.bash'
        bootstrap.write_text('''curl() { "$WATCHDOG_PYTHON" "$WATCHDOG_STUB" stub curl "$@"; }
launchctl() { "$WATCHDOG_PYTHON" "$WATCHDOG_STUB" stub launchctl "$@"; }
copilot-relay() { exec "$WATCHDOG_PYTHON" "$WATCHDOG_STUB" stub probe "$@"; }
''')
        self.env = dict(os.environ, HOME=str(self.root), BASH_ENV=str(bootstrap),
                        WATCHDOG_TEST_ROOT=str(self.root), WATCHDOG_PYTHON=sys.executable,
                        WATCHDOG_STUB=str(Path(__file__).resolve()),
                        COPILOT_RELAY_HEALTH_LOG=str(self.log),
                        COPILOT_RELAY_DEEP_STAMP=str(self.stamp),
                        COPILOT_RELAY_DEEP_INTERVAL='900', COPILOT_RELAY_DEEP_MAX_TIME='5',
                        COPILOT_RELAY_PLIST=str(self.root / 'relay.plist'))
        Path(self.env['COPILOT_RELAY_PLIST']).touch()
        self.work = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(120)'])
        self.addCleanup(self.stop_work)

    def stop_work(self):
        self.work.terminate()
        self.work.wait(timeout=5)

    def run_watchdog(self, rc=2, health=None, **extra):
        fixture = dict(rc=rc, health=health or ['200'], **extra)
        (self.root / 'fixture.json').write_text(json.dumps(fixture))
        result = subprocess.run([str(LAUNCHER), str(SCRIPT)], env=self.env, text=True,
                                capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(self.work.poll(), 'in-flight work was terminated')
        return self.log.read_text() if self.log.exists() else ''

    def calls(self, kind):
        rows = [json.loads(line) for line in self.events.read_text().splitlines()]
        return [row[1:] for row in rows if row[0] == kind]

    def test_healthy_relay_survives_every_deep_result(self):
        for rc in (0, 1, 2, 124, 9):
            with self.subTest(rc=rc):
                self.stamp.unlink(missing_ok=True)
                self.events.unlink(missing_ok=True)
                log = self.run_watchdog(rc)
                self.assertEqual(self.calls('launchctl'), [])
                self.assertEqual(len(self.calls('probe')), 1)
                self.assertEqual(len(self.calls('curl')), 1 if rc == 0 else 2)
                if rc:
                    self.assertIn(f'exit {rc}', log)
                    self.assertIn('leaving', log)

    def test_failure_is_stamped_and_not_repeated(self):
        self.run_watchdog(2)
        self.assertTrue(self.stamp.exists())
        self.run_watchdog(2)
        self.assertEqual(len(self.calls('probe')), 1)
        self.assertEqual(self.calls('launchctl'), [])

    def test_disabled_deep_check(self):
        self.env['COPILOT_RELAY_DEEP_INTERVAL'] = '0'
        self.run_watchdog()
        self.assertEqual(self.calls('probe'), [])
        self.assertFalse(self.stamp.exists())

    def test_initial_dead_service_recovers_without_probe(self):
        self.run_watchdog(health=['000', '200'])
        self.assertEqual(self.calls('probe'), [])
        self.assertTrue(any(call[0] == 'kickstart' for call in self.calls('launchctl')))

    def test_service_dies_during_probe(self):
        for rc in (1, 2, 124, 9):
            with self.subTest(rc=rc):
                self.stamp.unlink(missing_ok=True)
                self.events.unlink(missing_ok=True)
                self.run_watchdog(rc, health=['200', '000', '200'])
                self.assertTrue(any(call[0] == 'kickstart' for call in self.calls('launchctl')))
                self.assertEqual(len(self.calls('probe')), 1)

    def test_unloaded_service_bootstraps(self):
        self.run_watchdog(health=['000', '200'], loaded=False)
        self.assertTrue(any(call[0] == 'bootstrap' for call in self.calls('launchctl')))

    def test_timeout_only_stops_diagnostic(self):
        self.env['COPILOT_RELAY_DEEP_MAX_TIME'] = '1'
        log = self.run_watchdog(hang=True)
        self.assertIn('exit 124', log)
        self.assertEqual(self.calls('launchctl'), [])
        self.assertTrue(self.stamp.exists())
        with self.assertRaises(ProcessLookupError):
            os.kill(int((self.root / 'probe.pid').read_text()), 0)
        self.run_watchdog()
        self.assertEqual(len(self.calls('probe')), 1)

    def test_safe_diagnostics_only(self):
        output = json.dumps({'running': True, 'config': {'token': 'SECRET_TOKEN'},
                             'health': {'ok': True, 'ms': 4.9, 'detail': 'private prompt'},
                             'deep': {'ok': False, 'ms': 120, 'detail': 'http 503: SECRET_TOKEN\nforged log'}})
        log = self.run_watchdog(output=output)
        self.assertIn('"running":true', log)
        self.assertIn('"health_ok":true', log)
        self.assertIn('"health_ms":4', log)
        self.assertIn('"deep_ok":false', log)
        self.assertIn('"deep_http":503', log)
        for secret in ('SECRET_TOKEN', 'private prompt', 'forged log', 'config'):
            self.assertNotIn(secret, log)
        self.assertLess(len(log), 512)
        self.assertEqual(self.calls('probe'), [['status', '--deep', '--json']])
        self.assertEqual(self.calls('launchctl'), [])

    def test_untrusted_field_types_are_discarded(self):
        output = json.dumps({'running': True, 'health': {'ok': 'SECRET_TOKEN', 'ms': -1},
                             'deep': {'ok': [], 'ms': 9999999999, 'detail': 'SECRET_TOKEN' * 1000}})
        log = self.run_watchdog(output=output)
        for field in ('health_ok', 'health_ms', 'deep_ok', 'deep_ms', 'deep_http'):
            self.assertIn(f'"{field}":null', log)
        self.assertNotIn('SECRET_TOKEN', log)
        self.assertLess(len(log), 512)
        self.assertEqual(self.calls('launchctl'), [])

    def test_multiple_diagnostic_documents_are_rejected(self):
        output = '{"running":true,"health":{"ok":true}}\n{"running":true,"health":{"ok":false}}'
        log = self.run_watchdog(output=output)
        self.assertIn('diagnostic=unavailable', log)
        self.assertNotIn('"running"', log)
        self.assertEqual(self.calls('launchctl'), [])

    def test_missing_or_invalid_running_is_rejected(self):
        for output in ('{}', '{"running":"true"}', '{"running":1}', '[]'):
            with self.subTest(output=output):
                self.stamp.unlink(missing_ok=True)
                self.log.unlink(missing_ok=True)
                log = self.run_watchdog(output=output)
                self.assertIn('diagnostic=unavailable', log)
                self.assertEqual(self.calls('launchctl'), [])

    def test_malformed_diagnostic_is_not_logged(self):
        log = self.run_watchdog(output='SECRET_TOKEN\n\x1b[31m private prompt')
        self.assertNotIn('SECRET_TOKEN', log)
        self.assertNotIn('private prompt', log)
        self.assertIn('diagnostic=unavailable', log)
        self.assertEqual(self.calls('launchctl'), [])


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'stub':
        stub(sys.argv[2])
    else:
        unittest.main()
