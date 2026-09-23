#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = 'source config/zsh/zz-rmux.zsh; source config/zsh/zz-tmux.zsh; '


class HelperTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='tmux-helpers-')
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.capture = self.home / 'calls.jsonl'
        self.env = {k: v for k, v in os.environ.items()
                    if k not in ('RMUX', 'RMUX_PANE', 'TMUX', 'TMUX_PANE', 'ZDOTDIR')}
        self.env.update(HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin',
                        MUX_CAPTURE=str(self.capture))
        stub = f'''#!{sys.executable}
import json, os, sys
from pathlib import Path
with open(os.environ['MUX_CAPTURE'], 'a') as stream:
    stream.write(json.dumps([Path(sys.argv[0]).name, sys.argv[1:]]) + '\\n')
'''
        for name in ('tmux-store', 'rmux-store', 'rmux', 'tmux', 'claude', 'copilot'):
            executable = self.bin / name
            executable.write_text(stub)
            executable.chmod(0o755)

    def shell(self, code, interactive=False, **env):
        result = subprocess.run(['/bin/zsh', '-fi' if interactive else '-f', '-c', SOURCE + code],
                                cwd=ROOT, env=dict(self.env, **env), capture_output=True,
                                text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def calls(self):
        return [json.loads(line) for line in self.capture.read_text().splitlines()] if self.capture.exists() else []

    def test_source_never_attaches_and_keeps_native_command(self):
        self.shell('[[ $+functions[tmux] == 0 ]]; [[ $+functions[tr] == 0 ]]')
        self.assertEqual(self.calls(), [])

    def test_helper_mapping_and_interactive_tr(self):
        self.shell('tt main; tr work; tl; td work; th; ts', interactive=True)
        self.assertEqual(self.calls(), [['tmux-store', args] for args in
                         (['attach', 'main'], ['attach', 'work'], ['list'],
                          ['delete', 'work'], ['help'], ['restart'])])

    def test_translation_utility_stays_usable(self):
        output = self.shell("printf abc | tr a-z A-Z; print; printf abc | tr -d b; print; "
                            "printf abc | command tr a-z A-Z", interactive=True)
        self.assertEqual(output, 'ABC\nac\nABC')
        self.assertEqual(self.calls(), [])

    def test_arity_errors_do_not_call_backend(self):
        self.shell('tt >/dev/null 2>&1; [[ $? == 2 ]] || return 1; '
                   'tt one two >/dev/null 2>&1; [[ $? == 2 ]] || return 1; '
                   'td >/dev/null 2>&1; [[ $? == 2 ]] || return 1; '
                   'for helper in tl th ts; do "$helper" extra >/dev/null 2>&1; '
                   '[[ $? == 2 ]] || return 1; done')
        self.assertEqual(self.calls(), [])

    def test_detach_dispatch_prefers_rmux(self):
        self.shell('exit; logout', RMUX='rmux-socket', TMUX='compat-socket')
        self.assertEqual(self.calls(), [['rmux-store', ['client', 'detach-client']]] * 2)

    def test_native_tmux_detaches(self):
        self.shell('exit; logout', TMUX='/tmp/native,123,0')
        self.assertEqual(self.calls(), [['tmux-store', ['client', 'detach-client']]] * 2)

    def test_normal_exit_keeps_status(self):
        result = subprocess.run(['/bin/zsh', '-f', '-c', SOURCE + 'exit 7'], cwd=ROOT,
                                env=self.env, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 7)
        self.assertEqual(self.calls(), [])

    def test_ctrl_d_detaches_only_empty_mux_buffer(self):
        self.shell("zle() { print -r -- \"$*\"; }; BUFFER=''; _rmux_detach_or_delete_char; "
                   "BUFFER=text; _rmux_detach_or_delete_char", TMUX='/tmp/native,123,0')
        self.assertEqual(self.calls(), [['tmux-store', ['client', 'detach-client']]])
        self.capture.unlink()
        output = self.shell("zle() { print -r -- \"$*\"; }; BUFFER=''; _rmux_detach_or_delete_char")
        self.assertEqual(output.strip(), '.delete-char-or-list')
        self.assertEqual(self.calls(), [])

    def test_titles_route_to_native_store_without_path_tmux(self):
        title = 'literal #{session_name}; $(not-a-command)'
        self.shell('source config/zsh/cc.zsh; source config/zsh/gg.zsh; '
                   f'cc {shlex.quote(title)}; gg {shlex.quote(title)}', TMUX='/tmp/native,123,0')
        calls = self.calls()
        self.assertEqual([call[0] for call in calls], ['tmux-store', 'claude', 'tmux-store', 'copilot'])
        self.assertEqual(calls[0][1][0], 'rename')
        self.assertTrue(calls[0][1][1].endswith(title))
        self.assertTrue(calls[2][1][1].endswith(title))
        self.assertEqual(calls[1][1], ['--permission-mode', 'bypassPermissions', '--model',
                                     'claude-sonnet-5[1m]', '--effort', 'high'])
        self.assertEqual(calls[3][1], ['--yolo', '--model', 'gpt-6-astra',
                                     '--context', 'long_context', '--effort', 'high'])

    def test_titles_keep_rmux_route_when_both_markers_present(self):
        self.shell('source config/zsh/cc.zsh; cc title', RMUX='rmux-socket', TMUX='compat-socket')
        self.assertEqual([call[0] for call in self.calls()], ['rmux', 'claude'])


if __name__ == '__main__':
    unittest.main()
