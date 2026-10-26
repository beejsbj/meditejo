"""Offline tests for the sound pipeline's Freesound source and seam metrics:

    python3 -I -m unittest discover -s tools/meditejo -p 'test_sounds.py'

`meditejo-freesound-fetch` is replaced by a fake: no network, no tokens.
Needs numpy (the pipeline itself does).
"""
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

try:
    import numpy as np
except ImportError:  # pragma: no cover
    raise unittest.SkipTest('numpy is required')

_path = Path(__file__).with_name('sounds') / 'process_sounds.py'
_spec = importlib.util.spec_from_file_location('process_sounds', _path)
ps = importlib.util.module_from_spec(_spec)
sys.modules['process_sounds'] = ps
_spec.loader.exec_module(ps)
REAL_TOOL = ps.freesound_tool

CC0 = 'http://creativecommons.org/publicdomain/zero/1.0/'
BY3 = 'http://creativecommons.org/licenses/by/3.0/'
NC = 'http://creativecommons.org/licenses/by-nc/3.0/'


def sound(**kw):
    base = {'id': 'rain-indoors', 'freesound': 242889, 'license': 'CC0-1.0',
            'author': 'samesamesame', 'category': 'rain'}
    base.update(kw)
    return base


def info(license=CC0, username='samesamesame', type='wav'):
    return {'id': 242889, 'license': license, 'username': username, 'type': type,
            'filesize': 4}


class FakeTool:
    """Stands in for subprocess.run when the Freesound tool is called."""

    def __init__(self, info_json, payload=b'RIFFdata'):
        self.info_json, self.payload, self.calls = info_json, payload, []

    def __call__(self, cmd, **kw):
        self.calls.append(cmd[1])
        if cmd[1] == 'info':
            return subprocess.CompletedProcess(cmd, 0, json.dumps(self.info_json), '')
        Path(cmd[3]).write_bytes(self.payload)
        return subprocess.CompletedProcess(cmd, 0, '{}', '')


class FreesoundSource(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cache = Path(self.tmp.name)
        patches = [mock.patch.object(ps, 'freesound_tool', return_value='/bin/fake'),
                   mock.patch.object(ps.time, 'sleep')]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def tearDown(self):
        self.tmp.cleanup()

    def test_cache_miss_downloads_pins_and_checks_the_licence(self):
        tool = FakeTool(info())
        s = sound()
        with mock.patch.object(ps.subprocess, 'run', tool):
            path = ps.fetch(s, self.cache, pin=True)
        self.assertEqual(path.name, 'freesound-242889.wav')
        self.assertEqual(tool.calls, ['info', 'get'])
        self.assertEqual(s['sha256'], hashlib.sha256(b'RIFFdata').hexdigest())

    def test_cache_hit_needs_no_tool_and_checks_the_pin(self):
        (self.cache / 'freesound-242889.wav').write_bytes(b'RIFFdata')
        good = sound(sha256=hashlib.sha256(b'RIFFdata').hexdigest())
        with mock.patch.object(ps, 'freesound_tool', side_effect=AssertionError('no tool')):
            self.assertEqual(ps.fetch(good, self.cache, pin=False).name, 'freesound-242889.wav')
            with self.assertRaisesRegex(SystemExit, 'source changed'):
                ps.fetch(sound(sha256='0' * 64), self.cache, pin=False)
            with self.assertRaisesRegex(SystemExit, 'no pinned sha256'):
                ps.fetch(sound(), self.cache, pin=False)

    def test_a_missing_tool_fails_clearly(self):
        with mock.patch.object(ps, 'freesound_tool', REAL_TOOL), \
                mock.patch.object(ps.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(SystemExit, 'CI included'):
                ps.fetch(sound(), self.cache, pin=True)

    def test_url_sources_never_touch_the_tool(self):
        url = 'https://example.test/files/1019.flac'
        name = hashlib.sha256(url.encode()).hexdigest()[:16] + '-1019.flac'
        (self.cache / name).write_bytes(b'fLaC')
        s = {'id': 'x', 'downloadUrl': url, 'sha256': hashlib.sha256(b'fLaC').hexdigest()}
        with mock.patch.object(ps, 'freesound_tool', side_effect=AssertionError('no tool')):
            self.assertEqual(ps.fetch(s, self.cache, pin=False).name, name)

    def test_refuses_a_licence_the_library_does_not_accept(self):
        for lic in (NC, 'http://creativecommons.org/licenses/by-sa/4.0/',
                    'http://creativecommons.org/licenses/sampling+/1.0/', ''):
            tool = FakeTool(info(license=lic))
            with mock.patch.object(ps.subprocess, 'run', tool):
                with self.assertRaisesRegex(SystemExit, 'does not accept'):
                    ps.fetch(sound(), self.cache, pin=True)
            self.assertEqual(tool.calls, ['info'], 'nothing is downloaded')

    def test_refuses_when_freesound_disagrees_with_the_manifest(self):
        with mock.patch.object(ps.subprocess, 'run', FakeTool(info(license=BY3))):
            with self.assertRaisesRegex(SystemExit, 'CC-BY-3.0, sources.json says CC0-1.0'):
                ps.fetch(sound(), self.cache, pin=True)
        with mock.patch.object(ps.subprocess, 'run', FakeTool(info(username='someone-else'))):
            with self.assertRaisesRegex(SystemExit, 'author'):
                ps.fetch(sound(), self.cache, pin=True)

    def test_cc_by_is_accepted_when_the_manifest_says_so(self):
        s = sound(license='CC-BY-3.0', author='SDLx')
        with mock.patch.object(ps.subprocess, 'run', FakeTool(info(license=BY3, username='SDLx'))):
            self.assertTrue(ps.fetch(s, self.cache, pin=True).exists())


class Manifest(unittest.TestCase):
    def test_cc_by_needs_the_whole_credit(self):
        credit = {'id': 'train', 'category': 'room', 'license': 'CC-BY-3.0',
                  'author': 'SDLx', 'originalTitle': 'Trains of the Yamanote Line',
                  'pageUrl': 'https://freesound.org/people/SDLx/sounds/259988/'}
        ps.validate([credit])
        for key in ('author', 'originalTitle', 'pageUrl'):
            with self.assertRaisesRegex(SystemExit, key):
                ps.validate([{**credit, key: ''}])

    def test_unknown_licences_and_duplicates_are_refused(self):
        base = {'id': 'a', 'category': 'rain', 'license': 'CC0-1.0'}
        with self.assertRaisesRegex(SystemExit, 'not allowed'):
            ps.validate([{**base, 'license': 'CC-BY-NC-4.0'}])
        with self.assertRaisesRegex(SystemExit, 'duplicate'):
            ps.validate([base, base])
        with self.assertRaisesRegex(SystemExit, 'numeric'):
            ps.validate([{**base, 'freesound': '242889'}])

    def test_the_shipped_manifest_is_valid(self):
        manifest = json.loads(ps.SOURCES.read_text())
        ps.validate(manifest['sounds'])
        for s in manifest['sounds']:
            self.assertTrue(('freesound' in s) ^ ('downloadUrl' in s), s['id'])
            self.assertEqual(len(s.get('sha256', '')), 64, s['id'])


class SeamMetrics(unittest.TestCase):
    def noise(self, seconds=6, seed=1):
        rng = np.random.default_rng(seed)
        return rng.standard_normal((int(seconds * ps.RATE), 2)) * 0.05

    def test_a_crossfaded_loop_has_an_ordinary_seam(self):
        n = self.noise(8)
        loop = ps.bake_loop(n, 6.0, 2.0)
        m = ps.seam_metrics(loop)
        self.assertLessEqual(m['spectralDb'], m['spectralP95Db'] + 1.0)
        self.assertLessEqual(m['rmsStepDb'], m['rmsStepP95Db'] + 1.0)

    def test_a_level_jump_at_the_seam_shows(self):
        loop = self.noise(6)
        # A smooth fade of 20 dB over the loop: quiet at the end, loud at the
        # start, so only the wrap-around jumps.
        loop *= np.linspace(1, 0.1, len(loop))[:, None]
        m = ps.seam_metrics(loop)
        self.assertGreater(m['rmsStepDb'], 15)
        self.assertGreater(m['rmsStepDb'], 3 * m['rmsStepP95Db'])


if __name__ == '__main__':
    unittest.main()
