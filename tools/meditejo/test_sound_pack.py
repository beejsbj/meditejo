"""Offline tests for sound_pack.py: the library, NOTICE and assets agree, the
pack pin follows the pack's contents, a download is checked, and an APK holds
only the bundled sounds.

    python3 -I -m unittest discover -s tools/meditejo -p 'test_sound_pack.py'

No network and no `gh`: a throwaway library on disk, and the real one for the
repository's own invariants.
"""
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

_path = Path(__file__).with_name('sound_pack.py')
_spec = importlib.util.spec_from_file_location('sound_pack', _path)
sp = importlib.util.module_from_spec(_spec)
sys.modules['sound_pack'] = sp
_spec.loader.exec_module(sp)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def entry(sid, data, bundled):
    return {'id': sid, 'file': f'{sid}.opus', 'bundled': bundled, 'bytes': len(data),
            'sha256': sha(data), 'license': {'spdx': 'CC0-1.0'}}


class Repo:
    """A scratch checkout: assets/sounds with a library, NOTICE and files."""

    def __init__(self, test):
        self.dir = Path(tempfile.mkdtemp())
        test.addCleanup(lambda: __import__('shutil').rmtree(self.dir, ignore_errors=True))
        self.sounds = self.dir / 'assets' / 'sounds'
        self.sounds.mkdir(parents=True)
        self.core = b'core-loop' * 50
        self.far = b'far-loop' * 60
        self.library = {
            'version': 1,
            'sounds': [entry('near', self.core, True), entry('far', self.far, False)],
        }
        (self.sounds / 'near.opus').write_bytes(self.core)
        (self.sounds / 'NOTICE').write_text('near.opus: "Near"\nfar.opus: "Far"\n')
        self.pin()
        self.patches = [
            mock.patch.object(sp, 'ROOT', self.dir),
            mock.patch.object(sp, 'SOUNDS_DIR', self.sounds),
            mock.patch.object(sp, 'LIBRARY', self.sounds / 'sounds.json'),
            mock.patch.object(sp, 'NOTICE', self.sounds / 'NOTICE'),
        ]
        for patch in self.patches:
            patch.start()
            test.addCleanup(patch.stop)

    def pin(self, release='sounds-20261027'):
        pack = [e for e in self.library['sounds'] if not e['bundled']]
        self.library['pack'] = {'release': release, 'digest': sp.digest_of(pack),
                                'files': len(pack), 'bytes': sum(e['bytes'] for e in pack)}
        self.save()

    def save(self):
        (self.sounds / 'sounds.json').write_text(json.dumps(self.library))

    def run(self, command, *extra):
        argv = ['sound_pack.py', command, *extra]
        with mock.patch.object(sys, 'argv', argv):
            sp.main()


class Args:
    library = None


class VerifyTest(unittest.TestCase):
    def test_a_consistent_library_passes(self):
        repo = Repo(self)
        repo.run('verify')
        repo.run('status')

    def test_a_pack_file_in_the_apk_directory_is_refused(self):
        repo = Repo(self)
        (repo.sounds / 'far.opus').write_bytes(repo.far)
        with self.assertRaisesRegex(SystemExit, 'would ship in the APK'):
            repo.run('verify')

    def test_a_missing_or_changed_bundled_file_is_refused(self):
        repo = Repo(self)
        (repo.sounds / 'near.opus').write_bytes(b'changed')
        with self.assertRaisesRegex(SystemExit, 'not the file the library pins'):
            repo.run('verify')
        (repo.sounds / 'near.opus').unlink()
        with self.assertRaisesRegex(SystemExit, 'is missing'):
            repo.run('verify')

    def test_an_unlisted_file_is_refused(self):
        repo = Repo(self)
        (repo.sounds / 'stray.opus').write_bytes(b'x')
        with self.assertRaisesRegex(SystemExit, 'in no library entry'):
            repo.run('verify')

    def test_notice_must_cover_every_sound_downloaded_or_not(self):
        repo = Repo(self)
        (repo.sounds / 'NOTICE').write_text('near.opus: "Near"\n')
        with self.assertRaisesRegex(SystemExit, r'NOTICE does not cover far\.opus'):
            repo.run('verify')

    def test_notice_lines_are_matched_whole(self):
        repo = Repo(self)
        repo.library['sounds'][0]['id'] = 'rain'
        repo.library['sounds'][0]['file'] = 'rain.opus'
        (repo.sounds / 'near.opus').rename(repo.sounds / 'rain.opus')
        repo.save()
        # `heavy-rain.opus:` ends with `rain.opus:` but does not credit it.
        (repo.sounds / 'NOTICE').write_text('heavy-rain.opus: "Heavy"\nfar.opus: "Far"\n')
        with self.assertRaisesRegex(SystemExit, r'NOTICE does not cover rain\.opus'):
            repo.run('verify')

    def test_a_changed_pack_sound_needs_a_new_release(self):
        repo = Repo(self)
        repo.library['sounds'][1]['sha256'] = sha(b'another far loop')
        repo.save()
        with self.assertRaisesRegex(SystemExit, 'changed since sounds-20261027'):
            repo.run('verify')
        with self.assertRaisesRegex(SystemExit, 'Publish the pack again'):
            repo.run('status')

    def test_an_unpinned_pack_is_refused(self):
        repo = Repo(self)
        del repo.library['pack']
        repo.save()
        with self.assertRaisesRegex(SystemExit, 'pins no release'):
            repo.run('verify')

    def test_the_pin_must_be_a_sounds_tag(self):
        repo = Repo(self)
        for tag in ('v0.1.4', 'catalogue-20261019', 'sounds-1'):
            repo.pin(tag)
            with self.assertRaisesRegex(SystemExit, 'not a sounds-YYYYMMDD tag'):
                repo.run('verify')

    def test_a_library_with_no_pack_needs_no_pin(self):
        repo = Repo(self)
        repo.library['sounds'][1]['bundled'] = True
        (repo.sounds / 'far.opus').write_bytes(repo.far)
        del repo.library['pack']
        repo.save()
        repo.run('verify')

    def test_a_licence_meditejo_does_not_ship_is_refused(self):
        repo = Repo(self)
        repo.library['sounds'][0]['license'] = {'spdx': 'CC-BY-NC-4.0'}
        repo.save()
        with self.assertRaisesRegex(SystemExit, 'not one Meditejo ships'):
            repo.run('verify')


class RealLibraryTest(unittest.TestCase):
    """The repository's own library, as committed."""

    def test_the_committed_library_is_consistent(self):
        sp_real = sp
        library = sp_real.read_library(sp_real.ROOT / 'assets' / 'sounds' / 'sounds.json')
        bundled = [e for e in library['sounds'] if e['bundled']]
        packed = [e for e in library['sounds'] if not e['bundled']]
        self.assertTrue(bundled and packed)
        self.assertLess(sum(e['bytes'] for e in bundled), 6 * 1024 * 1024)
        self.assertRegex(library['pack']['release'], r'^sounds-\d{8}(-\d+)?$')
        self.assertEqual(library['pack']['digest'], sp_real.digest_of(packed))


class ApkTest(unittest.TestCase):
    def apk(self, repo, extra=None, skip=None, library_bytes=None):
        path = repo.dir / 'app.apk'
        prefix = 'assets/flutter_assets/assets/sounds/'
        with zipfile.ZipFile(path, 'w') as z:
            if skip != 'near':
                z.writestr(prefix + 'near.opus', repo.core)
            for name, data in (extra or {}).items():
                z.writestr(prefix + name, data)
            z.writestr(prefix + 'sounds.json', library_bytes or (repo.sounds / 'sounds.json').read_bytes())
        return str(path)

    def test_an_apk_with_the_bundled_sounds_only_passes(self):
        repo = Repo(self)
        repo.run('verify-apk', self.apk(repo))

    def test_a_pack_sound_in_the_apk_is_refused(self):
        repo = Repo(self)
        with self.assertRaisesRegex(SystemExit, 'belongs to the downloadable pack'):
            repo.run('verify-apk', self.apk(repo, extra={'far.opus': repo.far}))

    def test_a_missing_or_altered_bundled_sound_is_refused(self):
        repo = Repo(self)
        with self.assertRaisesRegex(SystemExit, 'missing from the APK'):
            repo.run('verify-apk', self.apk(repo, skip='near'))
        with self.assertRaisesRegex(SystemExit, 'differs from the checkout'):
            repo.run('verify-apk', self.apk(repo, library_bytes=b'{}'))


class PublishTest(unittest.TestCase):
    def test_nothing_is_uploaded_when_the_pin_is_current(self):
        repo = Repo(self)
        pack = repo.dir / 'build' / 'sound-pack'
        pack.mkdir(parents=True)
        (pack / 'far.opus').write_bytes(repo.far)
        with mock.patch.object(sp, 'PACK_DIR', pack), mock.patch.object(sp.cat, 'gh') as gh:
            repo.run('publish')
        gh.assert_not_called()

    def test_a_pack_file_that_is_not_the_pinned_one_is_refused(self):
        repo = Repo(self)
        repo.library['sounds'][1]['sha256'] = sha(b'new far loop')
        repo.save()
        pack = repo.dir / 'build' / 'sound-pack'
        pack.mkdir(parents=True)
        (pack / 'far.opus').write_bytes(repo.far)
        with mock.patch.object(sp, 'PACK_DIR', pack), mock.patch.object(sp.cat, 'gh') as gh:
            with self.assertRaisesRegex(SystemExit, 'is not the file the library pins'):
                repo.run('publish')
        gh.assert_not_called()

    def test_an_existing_release_is_read_back_before_it_is_pinned(self):
        repo = Repo(self)
        repo.library['sounds'][1] = entry('far', b'a new far loop', False)
        repo.save()
        pack = repo.dir / 'build' / 'sound-pack'
        pack.mkdir(parents=True)
        (pack / 'far.opus').write_bytes(b'a new far loop')
        before = (repo.sounds / 'sounds.json').read_text()
        # The tag exists and its manifest matches, but the file did not arrive.
        with mock.patch.object(sp, 'PACK_DIR', pack), \
                mock.patch.object(sp, 'release_state', return_value=True), \
                mock.patch.object(sp.cat, 'gh') as gh, \
                mock.patch.object(sp.cat, 'download', return_value=(3, 'f' * 64)):
            with self.assertRaisesRegex(SystemExit, 'holds far.opus as 3 bytes'):
                repo.run('publish')
        gh.assert_not_called()
        self.assertEqual((repo.sounds / 'sounds.json').read_text(), before)

    def test_a_dry_run_changes_nothing(self):
        repo = Repo(self)
        repo.library['sounds'][1] = entry('far', b'a new far loop', False)
        repo.save()
        before = (repo.sounds / 'sounds.json').read_text()
        pack = repo.dir / 'build' / 'sound-pack'
        pack.mkdir(parents=True)
        (pack / 'far.opus').write_bytes(b'a new far loop')
        with mock.patch.object(sp, 'PACK_DIR', pack), mock.patch.object(sp.cat, 'gh') as gh:
            repo.run('publish', '--dry-run')
        gh.assert_not_called()
        self.assertEqual((repo.sounds / 'sounds.json').read_text(), before)


if __name__ == '__main__':
    unittest.main()
