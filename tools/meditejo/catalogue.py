#!/usr/bin/env python3
"""The bundled Dharma Seed catalogue lives outside git.

`assets/dharma_seed/catalogue.json` (in git) pins one snapshot: its `asset`
section names a GitHub prerelease of beejsbj/meditejo and the SHA-256 and size
of the gzipped database attached to it. `assets/dharma_seed/catalogue.sqlite.gz`
is git-ignored and is fetched from that release. See docs/fork/ARCHITECTURE.md
("The bundled catalogue").

    catalogue.py fetch                fetch and verify the pinned snapshot
    catalogue.py check [--manifest F] the pinned asset is downloadable (no download)
    catalogue.py publish [--dry-run]  upload the local snapshot as a new
                                      prerelease and pin it in the manifest
    catalogue.py verify-apk APK       the APK carries exactly the pinned snapshot

Every failure exits non-zero with a message: a build with no catalogue, or the
wrong one, must never go by quietly. Standard library only.
"""
import argparse
import datetime as dt
import gzip
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

REPO = 'beejsbj/meditejo'
DEFAULT_BASE = f'https://github.com/{REPO}/releases/download'
ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / 'assets' / 'dharma_seed'
MANIFEST = DIRECTORY / 'catalogue.json'
ASSET_NAME = 'catalogue.sqlite.gz'
TAG_PATTERN = re.compile(r'^catalogue-\d{8}(-\d+)?$')
SHA_PATTERN = re.compile(r'^[0-9a-f]{64}$')


class Failure(Exception):
    pass


class NotFound(Failure):
    """The server said 404: the thing is not there (as opposed to unreachable)."""


def base_url():
    # Overridable so the tests can serve a fake release from localhost.
    return os.environ.get('MEDITEJO_CATALOGUE_BASE', DEFAULT_BASE).rstrip('/')


def read_manifest(path):
    try:
        manifest = json.loads(Path(path).read_text())
    except (OSError, ValueError) as e:
        raise Failure(f'cannot read {path}: {e}')
    if not isinstance(manifest, dict):
        raise Failure(f'{path} is not a JSON object')
    return manifest


def pinned_asset(manifest, source=MANIFEST):
    """The manifest's `asset` section, validated: which release, which bytes."""
    asset = manifest.get('asset')
    if not isinstance(asset, dict):
        raise Failure(
            f'{source} pins no snapshot (no "asset" section). Publish one with '
            '`python3 -I tools/meditejo/catalogue.py publish`, or restore the manifest.')
    tag, name = asset.get('release'), asset.get('name')
    size, digest = asset.get('bytes'), asset.get('sha256')
    if not (isinstance(tag, str) and TAG_PATTERN.match(tag)):
        raise Failure(f'{source}: asset.release {tag!r} is not a catalogue-YYYYMMDD tag')
    if name != ASSET_NAME:
        raise Failure(f'{source}: asset.name must be {ASSET_NAME}, not {name!r}')
    if not (isinstance(size, int) and not isinstance(size, bool) and size > 5 * 1024 * 1024):
        raise Failure(f'{source}: asset.bytes {size!r} is not a plausible snapshot size')
    if not (isinstance(digest, str) and SHA_PATTERN.match(digest)):
        raise Failure(f'{source}: asset.sha256 is not a lower-case SHA-256')
    return {'release': tag, 'name': name, 'bytes': size, 'sha256': digest}


def asset_url(asset):
    return f"{base_url()}/{asset['release']}/{asset['name']}"


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def request(url, method='GET', attempts=4):
    last = None
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(url, method=method, headers={
                'User-Agent': f'Meditejo-catalogue (+https://github.com/{REPO})'})
            return urllib.request.urlopen(req, timeout=60)
        except urllib.error.HTTPError as e:
            last = e
            e.close()
            if e.code < 500 and e.code != 429:
                break  # a 404 will not get better
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            last = e
        time.sleep(2 ** attempt)
    if isinstance(last, urllib.error.HTTPError) and last.code == 404:
        raise NotFound(f'{method} {url} failed: {last}')
    raise Failure(f'{method} {url} failed: {last}')


def download(url, destination):
    """Streams [url] to [destination]; returns (bytes, sha256)."""
    digest, size = hashlib.sha256(), 0
    with request(url) as response, open(destination, 'wb') as out:
        for chunk in iter(lambda: response.read(1 << 20), b''):
            out.write(chunk)
            digest.update(chunk)
            size += len(chunk)
    return size, digest.hexdigest()


def fetch(_args):
    asset = pinned_asset(read_manifest(MANIFEST))
    target = DIRECTORY / ASSET_NAME
    if (target.is_file() and target.stat().st_size == asset['bytes']
            and sha256_file(target) == asset['sha256']):
        print(f"{target.relative_to(ROOT)}: already the pinned snapshot ({asset['release']})")
        return
    DIRECTORY.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=DIRECTORY, prefix='.fetch-', suffix='.tmp')
    os.close(handle)
    try:
        url = asset_url(asset)
        print(f'fetching {url}')
        size, digest = download(url, temporary)
        if size != asset['bytes']:
            raise Failure(f"{url}: got {size} bytes, the manifest pins {asset['bytes']}")
        if digest != asset['sha256']:
            raise Failure(f"{url}: SHA-256 is {digest}, the manifest pins {asset['sha256']}")
        os.chmod(temporary, 0o644)  # mkstemp makes it private
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f"{target.relative_to(ROOT)}: {size} bytes, SHA-256 verified ({asset['release']})")


def check(args):
    manifest_path = Path(args.manifest) if args.manifest else MANIFEST
    asset = pinned_asset(read_manifest(manifest_path), manifest_path)
    url = asset_url(asset)
    with request(url, method='HEAD') as response:
        length = response.headers.get('Content-Length')
    if length is not None and int(length) != asset['bytes']:
        raise Failure(f"{url}: {length} bytes on the release, the manifest pins {asset['bytes']}")
    print(f"pinned snapshot is available: {asset['release']} ({asset['bytes']} bytes)")


def gh(*arguments, check=True):
    return subprocess.run(['gh', *arguments], text=True, capture_output=True, check=check)


def release_asset_sha(tag):
    """SHA-256 of the snapshot on release [tag], or None when there is no such release."""
    probe = gh('release', 'view', tag, '--repo', REPO, '--json', 'tagName', check=False)
    if probe.returncode != 0:
        if 'not found' in probe.stderr.lower():
            return None
        raise Failure(f'cannot look up release {tag}: {probe.stderr.strip()}')
    with tempfile.TemporaryDirectory() as scratch:
        path = Path(scratch) / ASSET_NAME
        try:
            _, digest = download(f'{base_url()}/{tag}/{ASSET_NAME}', path)
        except NotFound:
            return ''  # the release exists but carries no snapshot
        # Any other failure (5xx, timeout) propagates: it must not read as
        # "taken" and make publish create a second release.
        return digest


def publish(args):
    manifest = read_manifest(MANIFEST)
    packed = DIRECTORY / ASSET_NAME
    if not packed.is_file():
        raise Failure(f'{packed} is missing. Fetch the pinned snapshot or build one first.')
    digest, size = sha256_file(packed), packed.stat().st_size
    # The snapshot must be the one the manifest describes before it is pinned.
    unpacked, count = hashlib.sha256(), 0
    try:
        with gzip.open(packed, 'rb') as f:
            for chunk in iter(lambda: f.read(1 << 20), b''):
                unpacked.update(chunk)
                count += len(chunk)
    except (OSError, EOFError) as e:
        raise Failure(f'{packed} is not a readable gzip: {e}')
    if count != manifest.get('bytes') or unpacked.hexdigest() != manifest.get('sha256'):
        raise Failure(f'{packed} does not unpack to the database {MANIFEST.name} describes.')
    try:
        as_of = dt.datetime.fromisoformat(str(manifest['asOf']).replace('Z', '+00:00'))
    except (KeyError, ValueError):
        raise Failure(f'{MANIFEST.name} has no readable asOf')
    pinned = manifest.get('asset')
    if isinstance(pinned, dict) and pinned.get('sha256') == digest:
        print(f"already pinned: {pinned.get('release')}")
        return

    day = as_of.astimezone(dt.timezone.utc).strftime('%Y%m%d')
    tag, suffix, create = f'catalogue-{day}', 1, True
    while not args.dry_run:
        existing = release_asset_sha(tag)
        if existing is None:
            break  # the tag is free
        if existing == digest:
            print(f'{tag} already carries this snapshot; pinning it')
            create = False
            break
        suffix += 1  # taken by another snapshot (or an empty release)
        tag = f'catalogue-{day}-{suffix}'
    title = f"Dharma Seed catalogue {as_of.astimezone(dt.timezone.utc).strftime('%Y-%m-%d')}"
    notes = (
        'Bundled Dharma Seed catalogue snapshot (catalogue text only, no audio). '
        'Not an app release: it is a prerelease, which the in-app updater never reads. '
        'Builds fetch it by the SHA-256 pinned in assets/dharma_seed/catalogue.json; '
        'see docs/fork/ARCHITECTURE.md.\n\n'
        f"Talks: {manifest['counts']['talks']}, retreats: {manifest['counts']['retreats']}, "
        f"teachers: {manifest['counts']['teachers']}. SHA-256 of the gzip: {digest}")
    if args.dry_run:
        print(f'would create prerelease {tag} ({title}) with {packed.name}: '
              f'{size} bytes, sha256 {digest}, and pin it in {MANIFEST.name}')
        return
    if create:
        done = gh('release', 'create', tag, str(packed), '--repo', REPO, '--prerelease',
                  '--latest=false', '--title', title, '--notes', notes, check=False)
        if done.returncode != 0:
            raise Failure(f'gh release create {tag} failed: {done.stderr.strip()}')
        print(done.stdout.strip())
        # Prove the upload before pinning it: download it back and compare.
        verify = release_asset_sha(tag)
        if verify != digest:
            raise Failure(f'{tag} was created but its snapshot reads back as {verify!r}, not {digest}')
    manifest['asset'] = {'release': tag, 'name': ASSET_NAME, 'bytes': size, 'sha256': digest}
    MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'pinned {tag} in {MANIFEST.relative_to(ROOT)}')


def verify_apk(args):
    asset = pinned_asset(read_manifest(MANIFEST))
    entry = 'assets/flutter_assets/assets/dharma_seed/' + ASSET_NAME
    with zipfile.ZipFile(args.apk) as apk:
        try:
            data = apk.read(entry)
        except KeyError:
            raise Failure(f'{args.apk} has no {entry}: the build shipped with no catalogue')
        manifest_entry = apk.read('assets/flutter_assets/assets/dharma_seed/catalogue.json')
    if len(data) != asset['bytes'] or hashlib.sha256(data).hexdigest() != asset['sha256']:
        raise Failure(f'{args.apk}: the packaged catalogue is not the pinned {asset["release"]}')
    if manifest_entry != MANIFEST.read_bytes():
        raise Failure(f'{args.apk}: the packaged catalogue.json differs from the checkout')
    print(f"APK carries the pinned catalogue {asset['release']} ({len(data)} bytes)")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('fetch', help='fetch and verify the pinned snapshot').set_defaults(run=fetch)
    sub = commands.add_parser('check', help='the pinned asset is downloadable')
    sub.add_argument('--manifest', help='a manifest other than the checkout\'s')
    sub.set_defaults(run=check)
    sub = commands.add_parser('publish', help='upload the local snapshot and pin it')
    sub.add_argument('--dry-run', action='store_true')
    sub.set_defaults(run=publish)
    sub = commands.add_parser('verify-apk', help='the APK carries the pinned snapshot')
    sub.add_argument('apk')
    sub.set_defaults(run=verify_apk)
    args = parser.parse_args()
    try:
        args.run(args)
    except Failure as e:
        sys.exit(f'catalogue.py: {e}')


if __name__ == '__main__':
    main()
