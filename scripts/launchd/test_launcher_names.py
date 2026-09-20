#!/usr/bin/env python3
"""Named launchers and scoped installers; never contact services or clean caches."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]
PATH = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
JOBS = {
    'copilot-relay': ('Copilot Relay', ['copilot-relay', 'start']),
    'npm-cache-clean': ('Weekly npm Cache Cleanup',
                        ['__REPO_ROOT__/scripts/launchd/clean-npm-caches.sh']),
}


def expected_job(job, home='__HOME__', repo='__REPO_ROOT__'):
    name, arguments = JOBS[job]
    expected = {
        'Label': f'com.d0n9x1n.{job}',
        'ProgramArguments': [f'{home}/.local/libexec/{name}',
                             *(arg.replace('__REPO_ROOT__', repo) for arg in arguments)],
        'EnvironmentVariables': {'PATH': PATH},
        'RunAtLoad': job == 'copilot-relay',
        'StandardOutPath': f'{home}/Library/Logs/{job}.out.log',
        'StandardErrorPath': f'{home}/Library/Logs/{job}.err.log',
        'WorkingDirectory': home,
        'ProcessType': 'Background',
    }
    if job == 'copilot-relay':
        expected.update(KeepAlive=True, ThrottleInterval=10)
    else:
        expected['StartCalendarInterval'] = {'Weekday': 0, 'Hour': 3, 'Minute': 17}
    return expected


class LauncherTests(unittest.TestCase):
    def test_exact_template_metadata(self):
        for job in JOBS:
            with self.subTest(job=job):
                path = REPO / f'config/launchd/com.d0n9x1n.{job}.plist'
                self.assertEqual(plistlib.loads(path.read_bytes()), expected_job(job))

    def test_manifest_entries(self):
        manifest = (REPO / 'config/manifest.tsv').read_text().splitlines()
        for name, _ in JOBS.values():
            self.assertIn(f'link\tscripts/launchd/{name}\t.local/libexec/{name}', manifest)

    def test_launchers_preserve_arguments_environment_exit_and_pid(self):
        env = {key: value for key, value in os.environ.items() if key != 'BASH_ENV'}
        env['LAUNCHER_SENTINEL'] = 'unchanged & <value>'
        command = 'printf "%s\\n" "$$" "$BASH" "$LAUNCHER_SENTINEL" "$0" "$@"; exit 23'
        for job, (name, _) in JOBS.items():
            with self.subTest(job=job):
                launcher = REPO / 'scripts/launchd' / name
                interpreter = '/usr/bin/env' if job == 'copilot-relay' else '/bin/bash'
                self.assertEqual(launcher.read_text(), f'#!/bin/bash\nexec {interpreter} "$@"\n')
                self.assertTrue(os.access(launcher, os.X_OK))
                args = ['/bin/bash'] if job == 'copilot-relay' else []
                process = subprocess.Popen([
                    str(launcher), *args, '-c', command, 'name with spaces',
                    'argument with spaces', '', '*literal*', '& <xml> "quotes"'],
                    env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                stdout, stderr = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 23, stderr)
                self.assertEqual(stdout.splitlines(), [
                    str(process.pid), '/bin/bash', env['LAUNCHER_SENTINEL'],
                    'name with spaces', 'argument with spaces', '', '*literal*',
                    '& <xml> "quotes"'])


class ScopedInstallerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='launcher-install-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.home = self.root / 'home & <space> "double" \'single\' | pipe'
        self.repo = self.root / 'repo & <space> "double" \'single\' | pipe'
        self.home.mkdir()
        self.repo.mkdir()
        files = ['install.sh', 'scripts/apollo-theme.sh', 'config/manifest.tsv',
                 'scripts/launchd/clean-npm-caches.sh']
        for job, (name, _) in JOBS.items():
            files += [f'config/launchd/com.d0n9x1n.{job}.plist', f'scripts/launchd/{name}']
        for relative in files:
            source = REPO / relative
            if source.exists():
                dest = self.repo / relative
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, dest)
        (self.home / '.copilot-relay').mkdir()
        (self.home / '.copilot-relay/github_token').touch()
        self.events = self.home / 'events.jsonl'
        self.env = {key: value for key, value in os.environ.items() if key != 'BASH_ENV'}
        self.env.update(HOME=str(self.home), PATH='/usr/bin:/bin:/usr/sbin:/sbin',
                        TEST_PYTHON=sys.executable, HEALTH_CODE='200', MISSING_CLI='0',
                        RECOVER='0', SKIP_NPM_GLOBALS='0')

    def run_installer(self, commands):
        script = '''set -euo pipefail
DOT_CONFIGS_INSTALL_LIB_ONLY=1 source "$1/install.sh"
record() {
    "$TEST_PYTHON" -c 'import json, sys; f = open(sys.argv[1], "a"); f.write(json.dumps(sys.argv[2:]) + "\\n")' "$HOME/events.jsonl" "$@"
}
have_cmd() {
    if [ "$1" = copilot-relay ]; then test "$MISSING_CLI" = 0; else command -v "$1" >/dev/null; fi
}
launchctl() {
    record launchctl "$@"
    case "$1" in
        print) test -f "$HOME/loaded" ;;
        bootout) rm -f "$HOME/loaded" ;;
        bootstrap) touch "$HOME/loaded" ;;
        kickstart) return 0 ;;
        *) return 98 ;;
    esac
}
curl() {
    record curl "$@"
    if [ "$RECOVER" = 1 ] && [ -f "$HOME/health-checked" ]; then
        printf 200
    else
        printf '%s' "$HEALTH_CODE"
    fi
    touch "$HOME/health-checked"
}
sleep() { record sleep "$@"; }
npm() { record forbidden npm "$@"; return 99; }
copilot-relay() { record forbidden copilot-relay "$@"; return 99; }
''' + commands
        result = subprocess.run(['/bin/bash', '-c', script, 'test', str(self.repo)],
                                env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls('forbidden'), [])
        return result

    def calls(self, kind):
        if not self.events.exists():
            return []
        return [row[1:] for row in map(json.loads, self.events.read_text().splitlines())
                if row[0] == kind]

    def assert_installed(self, job):
        name = JOBS[job][0]
        installed = self.home / '.local/libexec' / name
        self.assertTrue(installed.is_symlink())
        self.assertEqual(installed.resolve(), self.repo / 'scripts/launchd' / name)
        self.assertTrue(os.access(installed, os.X_OK))
        plist = self.home / f'Library/LaunchAgents/com.d0n9x1n.{job}.plist'
        self.assertEqual(plistlib.loads(plist.read_bytes()),
                         expected_job(job, str(self.home), str(self.repo)))

    def test_relay_stage_only_twice_never_checks_health_or_calls_launchctl(self):
        # Stage-only is safe even without the coordinator's live-health precheck.
        self.env['HEALTH_CODE'] = '000'
        self.run_installer('''install_copilot_relay 501 stage-only
cp "$HOME/Library/LaunchAgents/com.d0n9x1n.copilot-relay.plist" "$HOME/first.plist"
install_copilot_relay 501 stage-only
cmp "$HOME/first.plist" "$HOME/Library/LaunchAgents/com.d0n9x1n.copilot-relay.plist"
''')
        self.assert_installed('copilot-relay')
        self.assertEqual(self.calls('launchctl'), [])
        self.assertEqual(self.calls('curl'), [])
        self.assertEqual(list((self.home / '.local/libexec').glob('*.bak.*')), [])
        self.assertEqual([p.name for p in (self.home / 'Library/LaunchAgents').iterdir()],
                         ['com.d0n9x1n.copilot-relay.plist'])

    def test_relay_stage_only_without_cli_or_auth_still_never_unloads(self):
        self.env['MISSING_CLI'] = '1'
        (self.home / '.copilot-relay/github_token').unlink()
        (self.home / 'loaded').touch()
        self.run_installer('install_copilot_relay 501 stage-only\n')
        self.assert_installed('copilot-relay')
        self.assertTrue((self.home / 'loaded').exists())
        self.assertEqual(self.calls('launchctl'), [])

    def test_npm_install_twice_bootstraps_only_its_job_without_kickstart(self):
        self.run_installer('''install_npm_cache_clean 501
cp "$HOME/Library/LaunchAgents/com.d0n9x1n.npm-cache-clean.plist" "$HOME/first.plist"
install_npm_cache_clean 501
cmp "$HOME/first.plist" "$HOME/Library/LaunchAgents/com.d0n9x1n.npm-cache-clean.plist"
''')
        self.assert_installed('npm-cache-clean')
        label = 'gui/501/com.d0n9x1n.npm-cache-clean'
        plist = str(self.home / 'Library/LaunchAgents/com.d0n9x1n.npm-cache-clean.plist')
        self.assertEqual(self.calls('launchctl'),
                         [['print', label], ['bootout', label], ['print', label],
                          ['bootstrap', 'gui/501', plist]] * 2)
        self.assertEqual(self.calls('curl'), [])
        self.assertEqual(list((self.home / '.local/libexec').glob('*.bak.*')), [])
        self.assertEqual([p.name for p in (self.home / 'Library/LaunchAgents').iterdir()],
                         ['com.d0n9x1n.npm-cache-clean.plist'])

    def test_relay_normal_healthy_twice_leaves_service_untouched(self):
        self.run_installer('install_copilot_relay 501\ninstall_copilot_relay 501\n')
        self.assert_installed('copilot-relay')
        self.assertEqual(self.calls('launchctl'), [])
        self.assertEqual(len(self.calls('curl')), 2)

    def test_relay_normal_unhealthy_recovers(self):
        self.env.update(HEALTH_CODE='000', RECOVER='1')
        (self.home / 'loaded').touch()
        result = self.run_installer('install_copilot_relay 501\n')
        self.assert_installed('copilot-relay')
        label = 'gui/501/com.d0n9x1n.copilot-relay'
        plist = str(self.home / 'Library/LaunchAgents/com.d0n9x1n.copilot-relay.plist')
        self.assertEqual(self.calls('launchctl'), [
            ['print', label], ['bootout', label], ['print', label],
            ['bootstrap', 'gui/501', plist], ['kickstart', '-k', label]])
        self.assertEqual(len(self.calls('curl')), 2)
        self.assertIn('copilot-relay is healthy at', result.stdout)

    def test_relay_normal_missing_cli_skips_render_and_services(self):
        self.env['MISSING_CLI'] = '1'
        for skip in ('0', '1'):
            with self.subTest(skip=skip):
                self.env['SKIP_NPM_GLOBALS'] = skip
                result = self.run_installer('install_copilot_relay 501\n')
                self.assertIn('copilot-relay not on PATH' if skip == '0' else
                              'SKIP_NPM_GLOBALS=1 and copilot-relay is not on PATH', result.stdout)
                self.assertFalse((self.home / 'Library/LaunchAgents').exists())
                self.assertEqual(self.calls('launchctl'), [])
                self.assertEqual(self.calls('curl'), [])

    def test_relay_normal_missing_auth_unloads_and_requests_auth(self):
        (self.home / '.copilot-relay/github_token').unlink()
        (self.home / 'loaded').touch()
        result = self.run_installer('install_copilot_relay 501\n')
        self.assert_installed('copilot-relay')
        label = 'gui/501/com.d0n9x1n.copilot-relay'
        self.assertEqual(self.calls('launchctl'), [['print', label], ['bootout', label]])
        self.assertEqual(self.calls('curl'), [])
        self.assertIn('not authenticated', result.stderr)
        self.assertIn("npx copilot-relay auth", result.stderr)


if __name__ == '__main__':
    unittest.main()
