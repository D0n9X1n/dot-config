#!/usr/bin/env python3
"""Preview vendor names; --apply/--rollback change only allowlisted USER jobs on disk."""
import argparse
import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shlex
import stat
import subprocess
import tempfile

PROXIES = (
    {'label': 'yanue.v2rayu.v2ray-core', 'name': 'V2rayU V2Ray Proxy Core (Legacy)',
     'binary': './v2ray-core/v2ray', 'args': ['run', '-config', 'config.json']},
    {'label': 'yanue.v2rayu.xray-core', 'name': 'V2rayU Xray Proxy Core',
     'binary': '/usr/local/v2rayu/bin/xray-core/xray-arm64', 'args': ['run', '-c', 'config.json']},
    {'label': 'yanue.v2rayu.sing-box', 'name': 'V2rayU sing-box Proxy Core',
     'binary': '/usr/local/v2rayu/bin/sing-box/sing-box-arm64', 'args': ['run', '-c', 'config.json']},
)
ASSOCIATIONS = (
    {'label': 'com.valvesoftware.steamclean', 'bundle': 'com.valvesoftware.steam',
     'app': '/Applications/Steam.app', 'team': 'MXGJJ98X76', 'user': True},
    {'label': 'com.adobe.acc.installer.v2', 'bundle': 'com.adobe.acc.AdobeCreativeCloud',
     'app': '/Applications/Utilities/Adobe Creative Cloud/ACC/Creative Cloud.app', 'team': 'JQ525L2MZD'},
    {'label': 'com.xk72.charles.ProxyHelper', 'bundle': 'com.xk72.Charles',
     'app': '/Applications/Charles.app', 'team': '9A5PCU4FSD'},
    {'label': 'com.microsoft.autoupdate.helper', 'bundle': 'com.microsoft.autoupdate2',
     'app': '/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app', 'team': 'UBF8T346G9'},
    {'label': 'com.bjango.istatmenus.installer', 'bundle': 'com.bjango.istatmenus',
     'app': '/Applications/iStat Menus.app', 'team': 'Y93TK974AT'},
)
LIMIT = 2 * 1024 * 1024


class Refusal(Exception):
    """An identity, ownership, or compare-before-write check failed."""


def digest(data):
    return hashlib.sha256(data).hexdigest()


def plist(data):
    try:
        value = plistlib.loads(data)
        if not isinstance(value, dict):
            raise ValueError('not a dictionary')
        return value
    except (ValueError, TypeError, plistlib.InvalidFileException) as error:
        raise Refusal(f'invalid plist: {error}') from error


class Overlay:
    def __init__(self, home=None, *, system=Path('/'), runner=subprocess.run):
        # system/runner are offline-test seams, deliberately not CLI options.
        self.home = Path(home) if home is not None else Path.home()
        self.system = Path(system)
        self.runner = runner
        self.state = self.home / '.local/state/dot-configs/startup-names'

    def safe(self, path, *, private=False):
        """Reject symlinks at every level, foreign-owned/writable USER paths."""
        if not path.is_absolute() or '..' in path.parts:
            raise Refusal(f'nonabsolute or unnormalized path: {path}')
        for part in [*reversed(path.parents), path]:
            try:
                info = part.lstat()
            except FileNotFoundError:
                continue
            if stat.S_ISLNK(info.st_mode):
                raise Refusal(f'symlink path: {part}')
            if part != path and not stat.S_ISDIR(info.st_mode):
                raise Refusal(f'non-directory ancestor: {part}')
            if part == self.home or self.home in part.parents:
                if info.st_uid != os.getuid() or info.st_mode & 0o022:
                    raise Refusal(f'foreign owner or writable-by-others path: {part}')
            if part == path and not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)):
                raise Refusal(f'not a regular file/directory: {part}')
            if stat.S_ISREG(info.st_mode) and info.st_nlink != 1:
                raise Refusal(f'hardlinked file: {part}')
            if private and (part == self.state or self.state in part.parents) and info.st_mode & 0o077:
                raise Refusal(f'backup permissions must be private: {part}')

    def read(self, path, *, private=False):
        self.safe(path, private=private)
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        except FileNotFoundError:
            return None
        with os.fdopen(fd, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size > LIMIT:
                raise Refusal(f'not a bounded regular file: {path}')
            data = stream.read(LIMIT + 1)
            if len(data) > LIMIT:
                raise Refusal(f'file exceeds size limit: {path}')
            return data, stat.S_IMODE(info.st_mode)

    def mkdir(self, path):
        self.safe(path, private=True)
        missing = []
        cursor = path
        while not cursor.exists():
            missing.append(cursor)
            cursor = cursor.parent
        for directory in reversed(missing):
            directory.mkdir(mode=0o700)
        self.safe(path, private=True)

    def replace(self, path, expected, data, mode):
        """Same-directory atomic publication, with a last-moment byte/mode check."""
        self.safe(path, private=True)
        fd, temporary = tempfile.mkstemp(prefix='.startup-names-', dir=path.parent)
        try:
            with os.fdopen(fd, 'wb') as stream:
                stream.write(data)
                os.fchmod(stream.fileno(), mode)
                stream.flush()
                os.fsync(stream.fileno())
            if self.read(path, private=True) != expected:
                raise Refusal(f'changed before replacement: {path}')
            if expected is None:
                # link is no-clobber: do not replace a file created after the check.
                os.link(temporary, path, follow_symlinks=False)
            else:
                os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    def command(self, args):
        try:
            return self.runner(args, capture_output=True, text=True, timeout=15,
                               env={'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LC_ALL': 'C'})
        except (OSError, subprocess.SubprocessError) as error:
            raise Refusal(f'identity command unavailable: {args[0]}: {error}') from error

    def signature(self, path, team):
        verified = self.command(['/usr/bin/codesign', '--verify', '--strict', str(path)])
        details = self.command(['/usr/bin/codesign', '-dv', '--verbose=4', str(path)])
        fields = {}
        for line in (details.stdout + '\n' + details.stderr).splitlines():
            key, separator, value = line.partition('=')
            if separator and key in ('Identifier', 'TeamIdentifier'):
                if key in fields:
                    raise Refusal(f'ambiguous signature identity: {path}')
                fields[key] = value.strip()
        if verified.returncode or details.returncode or fields.get('TeamIdentifier') != team:
            raise Refusal(f'invalid signature or TeamIdentifier: {path}')
        return fields

    def association(self, target, job):
        app = self.system / target['app'].lstrip('/')
        self.safe(app)
        if not app.exists():
            return None, 'app missing'
        arguments = job.get('ProgramArguments')
        program = job.get('Program')
        if arguments is not None and (not isinstance(arguments, list) or not arguments or
                                      not all(isinstance(a, str) for a in arguments)):
            raise Refusal(f'unexpected ProgramArguments: {target["label"]}')
        executable = program if program is not None else (arguments[0] if arguments else None)
        if not isinstance(executable, str) or not executable:
            raise Refusal(f'missing executable: {target["label"]}')
        if arguments and program is not None and executable != arguments[0]:
            raise Refusal(f'Program overrides executable: {target["label"]}')
        if target.get('user'):
            expected = str(self.home / 'Library/Application Support/Steam/SteamApps/steamclean')
            if executable != expected:
                raise Refusal('unexpected Steam executable or Program override')
        executable = Path(executable)
        self.safe(executable)
        if not executable.is_file():
            raise Refusal(f'signed executable missing: {executable}')
        info = self.read(app / 'Contents/Info.plist')
        if info is None or plist(info[0]).get('CFBundleIdentifier') != target['bundle']:
            raise Refusal(f'app bundle identifier mismatch: {app}')
        identity = self.signature(app, target['team'])
        self.signature(executable, target['team'])
        if identity.get('Identifier') != target['bundle']:
            raise Refusal(f'signed app identifier mismatch: {app}')
        existing = job.get('AssociatedBundleIdentifiers')
        if existing not in (None, [], [target['bundle']]):
            raise Refusal(f'conflicting bundle association: {target["label"]}')
        # NSWorkspace is a read-only LaunchServices lookup. Never register/unregister.
        script = ('ObjC.import("AppKit"); var u = $.NSWorkspace.sharedWorkspace.'
                  'URLForApplicationWithBundleIdentifier(' + json.dumps(target['bundle']) +
                  '); u ? ObjC.unwrap(u.path) : "";')
        result = self.command(['/usr/bin/osascript', '-l', 'JavaScript', '-e', script])
        registered = result.stdout.strip()
        if result.returncode or registered != str(app):
            raise Refusal(f'LaunchServices registration absent, unavailable, or different: {app}')
        return dict(job, AssociatedBundleIdentifiers=[target['bundle']]), 'LaunchServices match'

    def proxy(self, target, job):
        expected = [target['binary'], *target['args']]
        if ('Program' in job or job.get('ProgramArguments') != expected or
                job.get('WorkingDirectory') != str(self.home / '.V2rayU') or
                job.get('RunAtLoad') is not False or job.get('KeepAlive') is not False):
            raise Refusal(f'unexpected proxy executable/arguments/cwd/flags: {target["label"]}')
        environment = job.get('EnvironmentVariables', {})
        if not isinstance(environment, dict) or any(k in environment for k in ('BASH_ENV', 'ENV', 'SHELLOPTS', 'BASHOPTS')):
            raise Refusal(f'unsafe shell startup environment: {target["label"]}')
        launcher = self.home / '.local/libexec' / target['name']
        binary = shlex.quote(target['binary'])
        content = f'#!/bin/bash\nexec -a {binary} {binary} "$@"\n'.encode()
        return dict(job, ProgramArguments=[str(launcher), *target['args']]), launcher, content

    def plan(self, target, action):
        user = 'name' in target or target.get('user', False)
        directory = self.home / 'Library/LaunchAgents' if user else self.system / 'Library/LaunchDaemons'
        path = directory / (target['label'] + '.plist')
        current = self.read(path)
        record_path = self.state / (target['label'] + '.json')
        saved = self.read(record_path, private=True) if user else None
        prefix = 'USER' if user else 'SYSTEM PREVIEW (no writes)'
        if current is None:
            if saved:
                raise Refusal(f'recorded job disappeared: {path}')
            return None, f'SKIP {prefix} {target["label"]}: job missing'
        if action == 'rollback' and (not user or not saved):
            return None, f'SKIP {prefix} {target["label"]}: no user backup'
        original = current
        if saved:
            try:
                record = json.loads(saved[0])
                original = (base64.b64decode(record['original'], validate=True), record['mode'])
                if (record['version'] != 1 or digest(original[0]) != record['original_sha256'] or
                        not isinstance(original[1], int) or original[1] & ~0o777 or original[1] & 0o022):
                    raise ValueError('invalid original backup')
            except (ValueError, KeyError, TypeError) as error:
                raise Refusal(f'invalid backup: {record_path}') from error
        job = plist(original[0])
        if job.get('Label') != target['label']:
            raise Refusal(f'label mismatch: {path}')
        launcher = content = None
        note = ''
        if 'name' in target:
            updated, launcher, content = self.proxy(target, job)
        elif action == 'rollback':
            updated = dict(job, AssociatedBundleIdentifiers=[target['bundle']])
        else:
            updated, note = self.association(target, job)
            if updated is None:
                return None, f'SKIP {prefix} {target["label"]}: {note}'
        applied = (plistlib.dumps(updated, sort_keys=False), original[1])
        expected_record = {'version': 1, 'original': base64.b64encode(original[0]).decode(),
                           'mode': original[1], 'original_sha256': digest(original[0]),
                           'applied_sha256': digest(applied[0]),
                           'launcher_sha256': digest(content) if content is not None else None}
        if saved and record != expected_record:
            raise Refusal(f'backup does not match approved overlay: {record_path}')
        if current not in (original, applied):
            raise Refusal(f'vendor/external job changes: {path}')
        existing_launcher = self.read(launcher) if launcher else None
        if launcher and existing_launcher is not None and (not saved or existing_launcher != (content, 0o700)):
            raise Refusal(f'unfamiliar/changed launcher: {launcher}')
        if action != 'rollback' and saved and current == applied and launcher and existing_launcher is None:
            raise Refusal(f'applied launcher disappeared: {launcher}')
        if action == 'rollback' and current == original and existing_launcher is not None:
            # Crash after restoring plist, before deleting our known launcher: safe recovery.
            note = 'finish interrupted rollback'
        desired = original if action == 'rollback' else applied
        change = (user and (current != desired or (launcher and
                  ((action == 'rollback' and existing_launcher is not None) or
                   (action != 'rollback' and existing_launcher is None)))))
        plan = {'path': path, 'current': current, 'desired': desired, 'original': original,
                'launcher': launcher, 'content': content, 'existing_launcher': existing_launcher,
                'record_path': record_path, 'record': expected_record, 'saved': saved}
        status = 'ROLLBACK' if action == 'rollback' else ('APPLY' if action == 'apply' else 'PREVIEW')
        detail = target.get('name', target.get('bundle'))
        return (plan if change else None), f'{prefix} {status} {target["label"]} -> {detail}' + (f' ({note})' if note else '')

    def run(self, action='preview'):
        if action not in ('preview', 'apply', 'rollback'):
            raise Refusal('unknown action')
        if action != 'preview' and os.geteuid() == 0:
            raise Refusal('refusing privileged user code; run as your normal user')
        self.safe(self.home)
        self.safe(self.state, private=True)
        plans, messages = [], []
        for target in (*PROXIES, *ASSOCIATIONS):
            try:
                plan, message = self.plan(target, action)
            except Refusal as error:
                if action != 'preview':
                    raise
                messages.append(f'CONFLICT {target["label"]}: {error}')
                continue
            messages.append(message)
            if plan:
                plans.append(plan)
        if action == 'preview' or not plans:
            return messages
        self.mkdir(self.state)
        lock = self.state / '.lock'
        self.safe(lock, private=True)
        fd = os.open(lock, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'r+') as stream:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            # Rebuild under the cooperative lock; a second command cannot race backups.
            plans = [self.plan(t, action)[0] for t in (*PROXIES, ASSOCIATIONS[0])]
            for item in filter(None, plans):
                if item['saved'] is None:
                    encoded = (json.dumps(item['record'], sort_keys=True) + '\n').encode()
                    self.replace(item['record_path'], None, encoded, 0o600)
                launcher = item['launcher']
                if action != 'rollback' and launcher and item['existing_launcher'] is None:
                    self.mkdir(launcher.parent)
                    self.replace(launcher, None, item['content'], 0o700)
                if item['current'] != item['desired']:
                    self.replace(item['path'], item['current'], *item['desired'])
                if action == 'rollback' and launcher and item['existing_launcher'] is not None:
                    if self.read(launcher) != item['existing_launcher']:
                        raise Refusal(f'launcher changed before removal: {launcher}')
                    launcher.unlink()
        return messages


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--apply', action='store_true', help='apply only allowlisted USER jobs (disk only)')
    group.add_argument('--rollback', action='store_true', help='restore USER backups only when recorded files are unchanged')
    args = parser.parse_args(argv)
    action = 'apply' if args.apply else 'rollback' if args.rollback else 'preview'
    try:
        for message in Overlay().run(action):
            print(message)
        return 0
    except (Refusal, OSError) as error:
        print(f'REFUSED: {error}', file=__import__('sys').stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
