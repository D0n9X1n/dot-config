"""Workspace-only snapshots and private atomic state shared by mux helpers."""
import contextlib
import fcntl
import hashlib
import json
import os
import re
import stat
import tempfile


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


class PrivateState:
    lock_label = 'rmux-store'

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
                raise StoreError(f'{self.lock_label} busy; another operation holds the lock') from exc
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
