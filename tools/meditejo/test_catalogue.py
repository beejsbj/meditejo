"""Offline tests for catalogue.py: python3 -I -m unittest discover -s tools/meditejo -p 'test_catalogue.py'

A throwaway HTTP server stands in for the GitHub release downloads.
"""
import functools
import hashlib
import http.server
import importlib.util
import json
import os
import tempfile
import threading
import unittest
import zipfile
from pathlib import Path

_spec = importlib.util.spec_from_file_location('catalogue', Path(__file__).with_name('catalogue.py'))
catalogue = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(catalogue)

TAG = 'catalogue-20261019'
PAYLOAD = os.urandom(6 * 1024 * 1024)  # above the tool's "plausible snapshot" floor


class _Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


class CatalogueTool(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        scratch = Path(self.scratch.name)
        self.served = scratch / 'served'
        (self.served / TAG).mkdir(parents=True)
        (self.served / TAG / catalogue.ASSET_NAME).write_bytes(PAYLOAD)
        handler = functools.partial(_Quiet, directory=str(self.served))
        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        os.environ['MEDITEJO_CATALOGUE_BASE'] = f'http://127.0.0.1:{self.server.server_port}'

        self.directory = scratch / 'checkout' / 'assets' / 'dharma_seed'
        self.directory.mkdir(parents=True)
        catalogue.ROOT = scratch / 'checkout'
        catalogue.DIRECTORY = self.directory
        catalogue.MANIFEST = self.directory / 'catalogue.json'
        self.write_manifest()
        self.packed = self.directory / catalogue.ASSET_NAME

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        os.environ.pop('MEDITEJO_CATALOGUE_BASE', None)
        self.scratch.cleanup()

    def write_manifest(self, **asset_overrides):
        asset = {'release': TAG, 'name': catalogue.ASSET_NAME, 'bytes': len(PAYLOAD),
                 'sha256': hashlib.sha256(PAYLOAD).hexdigest(), **asset_overrides}
        catalogue.MANIFEST.write_text(json.dumps({'schema': 1, 'asset': asset}))

    def run_command(self, command, **kwargs):
        args = type('Args', (), kwargs)()
        getattr(catalogue, command)(args)

    def test_fetch_downloads_and_verifies(self):
        self.run_command('fetch')
        self.assertEqual(self.packed.read_bytes(), PAYLOAD)

    def test_fetch_leaves_a_good_copy_alone(self):
        self.run_command('fetch')
        before = self.packed.stat().st_mtime_ns
        self.server.shutdown()  # a second fetch must not need the network
        self.run_command('fetch')
        self.assertEqual(self.packed.stat().st_mtime_ns, before)

    def test_fetch_replaces_a_pointer_sized_or_stale_copy(self):
        self.packed.write_bytes(b'version https://git-lfs.github.com/spec/v1\n')
        self.run_command('fetch')
        self.assertEqual(self.packed.read_bytes(), PAYLOAD)

    def test_fetch_refuses_a_hash_mismatch_and_keeps_nothing(self):
        self.write_manifest(sha256='0' * 64)
        with self.assertRaisesRegex(catalogue.Failure, 'SHA-256'):
            self.run_command('fetch')
        self.assertFalse(self.packed.exists())
        self.assertEqual([p.name for p in self.directory.iterdir()], ['catalogue.json'])

    def test_fetch_refuses_a_size_mismatch(self):
        self.write_manifest(bytes=len(PAYLOAD) + 1)
        with self.assertRaisesRegex(catalogue.Failure, 'bytes'):
            self.run_command('fetch')

    def test_fetch_fails_on_a_missing_asset(self):
        self.write_manifest(release='catalogue-20990101')
        with self.assertRaisesRegex(catalogue.Failure, 'failed'):
            self.run_command('fetch')
        self.assertFalse(self.packed.exists())

    def test_fetch_fails_when_the_manifest_pins_nothing(self):
        catalogue.MANIFEST.write_text(json.dumps({'schema': 1}))
        with self.assertRaisesRegex(catalogue.Failure, 'pins no snapshot'):
            self.run_command('fetch')

    def test_a_malformed_pin_is_refused(self):
        for override in ({'release': 'v0.1.3'}, {'name': 'other.gz'}, {'sha256': 'ABC'},
                         {'bytes': 12}):
            self.write_manifest(**override)
            with self.assertRaises(catalogue.Failure, msg=str(override)):
                self.run_command('fetch')

    def test_check_finds_the_asset_without_downloading(self):
        self.run_command('check', manifest=None)
        self.write_manifest(release='catalogue-20990101')
        with self.assertRaises(catalogue.Failure):
            self.run_command('check', manifest=None)

    def test_check_reads_another_manifest(self):
        other = Path(self.scratch.name) / 'other.json'
        other.write_text(json.dumps({'asset': {
            'release': TAG, 'name': catalogue.ASSET_NAME, 'bytes': len(PAYLOAD),
            'sha256': hashlib.sha256(PAYLOAD).hexdigest()}}))
        catalogue.MANIFEST.write_text('{}')  # the checkout's own pins nothing
        self.run_command('check', manifest=str(other))

    def make_apk(self, payload, manifest_bytes=None):
        apk = Path(self.scratch.name) / 'app.apk'
        with zipfile.ZipFile(apk, 'w', zipfile.ZIP_DEFLATED) as z:
            base = 'assets/flutter_assets/assets/dharma_seed/'
            if payload is not None:
                z.writestr(base + catalogue.ASSET_NAME, payload)
            z.writestr(base + 'catalogue.json',
                       catalogue.MANIFEST.read_bytes() if manifest_bytes is None else manifest_bytes)
        return str(apk)

    def test_verify_apk_accepts_exactly_the_pinned_snapshot(self):
        self.run_command('verify_apk', apk=self.make_apk(PAYLOAD))

    def test_verify_apk_refuses_a_missing_or_different_snapshot(self):
        with self.assertRaisesRegex(catalogue.Failure, 'no catalogue'):
            self.run_command('verify_apk', apk=self.make_apk(None))
        with self.assertRaisesRegex(catalogue.Failure, 'not the pinned'):
            self.run_command('verify_apk', apk=self.make_apk(PAYLOAD[:-1]))
        with self.assertRaisesRegex(catalogue.Failure, 'differs'):
            self.run_command('verify_apk', apk=self.make_apk(PAYLOAD, b'{}'))


if __name__ == '__main__':
    unittest.main()
