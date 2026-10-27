#!/usr/bin/env python3
"""The sound pack: the sounds that are a download, not part of the APK.

`assets/sounds/sounds.json` (in git) lists every sound with its SHA-256 and
size, and marks the core set `"bundled": true`; those files are in
`assets/sounds/` and ship in the APK. Every other sound is a file on a
`sounds-YYYYMMDD` GitHub prerelease of beejsbj/meditejo, named `<id>.opus`,
which the app downloads on request and checks against the SHA-256 the JSON
pins. The JSON's `pack` section names the release. `process_sounds.py` builds
the pack files into `build/sound-pack/` (not in git). See
docs/fork/ARCHITECTURE.md ("The sound pack").

    sound_pack.py verify [--library F]  the library, NOTICE and assets/sounds agree (offline)
    sound_pack.py status [--library F]  the pack release pins exactly the library's pack sounds
    sound_pack.py check [--library F]   the pinned release serves every pack file (no download)
    sound_pack.py fetch [--dest DIR]    download and verify the pack into build/sound-pack
    sound_pack.py publish [--dry-run]   upload build/sound-pack as a new prerelease and pin it
    sound_pack.py verify-apk APK        the APK carries exactly the bundled sounds, none of the pack

The pack is a prerelease with a `sounds-` tag: the in-app updater reads only
`releases/latest`, ignores prereleases and anything not tagged `vX.Y.Z`
(lib/services/updates). Every failure exits non-zero with a message. Standard
library only.
"""
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
import re
import sys
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LIBRARY = ROOT / 'assets' / 'sounds' / 'sounds.json'
NOTICE = ROOT / 'assets' / 'sounds' / 'NOTICE'
SOUNDS_DIR = ROOT / 'assets' / 'sounds'
PACK_DIR = ROOT / 'build' / 'sound-pack'
MANIFEST_NAME = 'sounds-pack.json'
TAG_PATTERN = re.compile(r'^sounds-\d{8}(-\d+)?$')
SHA_PATTERN = re.compile(r'^[0-9a-f]{64}$')
ID_PATTERN = re.compile(r'^[a-z0-9]+(-[a-z0-9]+)*$')
LICENCES = {'CC0-1.0', 'CC-BY-3.0', 'CC-BY-4.0', 'PD'}


def _load_catalogue():
    # The release plumbing (retrying requests, streamed hashing, `gh`) is the
    # catalogue tool's. `python3 -I` leaves the script directory off sys.path,
    # so it is loaded by path.
    spec = importlib.util.spec_from_file_location('meditejo_catalogue', HERE / 'catalogue.py')
    module = importlib.util.module_from_spec(spec)
    sys.modules['meditejo_catalogue'] = module
    spec.loader.exec_module(module)
    return module


cat = _load_catalogue()
Failure, NotFound = cat.Failure, cat.NotFound


def base_url():
    return os.environ.get('MEDITEJO_SOUNDS_BASE', cat.DEFAULT_BASE).rstrip('/')


def read_library(path=LIBRARY):
    library = cat.read_manifest(path)
    sounds = library.get('sounds')
    if not isinstance(sounds, list) or not sounds:
        raise Failure(f'{path} lists no sounds')
    seen = set()
    for entry in sounds:
        sid = entry.get('id') if isinstance(entry, dict) else None
        if not (isinstance(sid, str) and ID_PATTERN.match(sid)):
            raise Failure(f'{path}: {entry!r} has no usable id')
        if sid in seen:
            raise Failure(f'{path}: duplicate sound {sid}')
        seen.add(sid)
        if entry.get('file') != f'{sid}.opus':
            raise Failure(f"{path}: {sid}: file must be {sid}.opus, not {entry.get('file')!r}")
        if not isinstance(entry.get('bundled'), bool):
            raise Failure(f'{path}: {sid}: bundled must be true or false')
        size, digest = entry.get('bytes'), entry.get('sha256')
        if not (isinstance(size, int) and not isinstance(size, bool) and size > 0):
            raise Failure(f'{path}: {sid}: bytes {size!r} is not a size')
        if not (isinstance(digest, str) and SHA_PATTERN.match(digest)):
            raise Failure(f'{path}: {sid}: sha256 is not a lower-case SHA-256')
        spdx = (entry.get('license') or {}).get('spdx')
        if spdx not in LICENCES:
            raise Failure(f'{path}: {sid}: licence {spdx!r} is not one Meditejo ships')
    return library


def bundled(library):
    return [e for e in library['sounds'] if e['bundled']]


def packed(library):
    return [e for e in library['sounds'] if not e['bundled']]


def digest_of(entries):
    """One hash for the set of pack files: what the release must hold."""
    lines = sorted(f"{e['id']} {e['sha256']} {e['bytes']}" for e in entries)
    return hashlib.sha256('\n'.join(lines).encode()).hexdigest()


def pinned_pack(library, source=LIBRARY):
    """The library's `pack` section, validated; None when there is no pack."""
    entries = packed(library)
    pack = library.get('pack')
    if not entries:
        return None
    if not isinstance(pack, dict):
        raise Failure(
            f'{source} has downloadable sounds but pins no release. Publish the pack '
            'with `python3 -I tools/meditejo/sound_pack.py publish`.')
    tag = pack.get('release')
    if not (isinstance(tag, str) and TAG_PATTERN.match(tag)):
        raise Failure(f'{source}: pack.release {tag!r} is not a sounds-YYYYMMDD tag')
    if pack.get('digest') != digest_of(entries):
        raise Failure(
            f'{source}: the pack sounds changed since {tag} was pinned (its digest no '
            'longer matches). Publish the pack again: `sound_pack.py publish`.')
    if pack.get('files') != len(entries) or pack.get('bytes') != sum(e['bytes'] for e in entries):
        raise Failure(f'{source}: pack.files or pack.bytes disagrees with the pack sounds')
    return {'release': tag, 'digest': pack['digest']}


def file_url(tag, entry):
    return f"{base_url()}/{tag}/{entry['file']}"


# ---------------------------------------------------------------- verify

def verify(args):
    library_path = Path(args.library) if args.library else LIBRARY
    library = read_library(library_path)
    on_disk = {p.name for p in SOUNDS_DIR.glob('*.opus')} if SOUNDS_DIR.is_dir() else set()
    problems = []
    for entry in library['sounds']:
        path = SOUNDS_DIR / entry['file']
        if entry['bundled']:
            if not path.is_file():
                problems.append(f"{entry['id']} is bundled but {path.relative_to(ROOT)} is missing")
            elif path.stat().st_size != entry['bytes'] or cat.sha256_file(path) != entry['sha256']:
                problems.append(f"{entry['id']}: {path.name} is not the file the library pins")
        elif entry['file'] in on_disk:
            problems.append(f"{entry['id']} is in the pack but {entry['file']} is also in assets/sounds "
                            '(it would ship in the APK)')
    known = {e['file'] for e in library['sounds']}
    problems += [f'assets/sounds/{name} is in no library entry' for name in sorted(on_disk - known)]
    notice = NOTICE.read_text() if NOTICE.is_file() else ''
    problems += [f"NOTICE does not cover {e['file']}" for e in library['sounds']
                 if f"{e['file']}:" not in notice]
    if problems:
        raise Failure('the sound library is inconsistent:\n  ' + '\n  '.join(problems))
    pinned_pack(library, library_path)  # raises when the pack pin is stale
    b, p = bundled(library), packed(library)
    print(f"sound library: {len(b)} bundled ({sum(e['bytes'] for e in b)} bytes), "
          f"{len(p)} in the pack ({sum(e['bytes'] for e in p)} bytes); NOTICE covers all")


def status(args):
    library = read_library(Path(args.library) if args.library else LIBRARY)
    pin = pinned_pack(library)
    print(f"pack pinned: {pin['release']}" if pin else 'no downloadable sounds')


# ---------------------------------------------------------------- check / fetch

def check(args):
    library_path = Path(args.library) if args.library else LIBRARY
    library = read_library(library_path)
    pin = pinned_pack(library, library_path)
    if not pin:
        print('no downloadable sounds; nothing to check')
        return
    for entry in packed(library):
        url = file_url(pin['release'], entry)
        with cat.request(url, method='HEAD') as response:
            length = response.headers.get('Content-Length')
        if length is not None and int(length) != entry['bytes']:
            raise Failure(f"{url}: {length} bytes on the release, the library pins {entry['bytes']}")
    print(f"pinned sound pack is available: {pin['release']} ({len(packed(library))} files)")


def fetch(args):
    library = read_library()
    pin = pinned_pack(library)
    if not pin:
        print('no downloadable sounds; nothing to fetch')
        return
    dest = Path(args.dest) if args.dest else PACK_DIR
    dest.mkdir(parents=True, exist_ok=True)
    for entry in packed(library):
        target = dest / entry['file']
        if (target.is_file() and target.stat().st_size == entry['bytes']
                and cat.sha256_file(target) == entry['sha256']):
            continue
        handle, temporary = tempfile.mkstemp(dir=dest, prefix='.fetch-', suffix='.tmp')
        os.close(handle)
        try:
            url = file_url(pin['release'], entry)
            size, digest = cat.download(url, temporary)
            if size != entry['bytes'] or digest != entry['sha256']:
                raise Failure(f"{url}: got {size} bytes / {digest}, the library pins "
                              f"{entry['bytes']} / {entry['sha256']}")
            os.chmod(temporary, 0o644)
            os.replace(temporary, target)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    print(f"{dest}: {len(packed(library))} files, SHA-256 verified ({pin['release']})")


# ---------------------------------------------------------------- publish

def release_state(tag, entries):
    """None when [tag] is free; True when it holds exactly [entries]; False when
    it is taken by something else."""
    probe = cat.gh('release', 'view', tag, '--repo', cat.REPO, '--json', 'tagName', check=False)
    if probe.returncode != 0:
        if 'not found' in probe.stderr.lower():
            return None
        raise Failure(f'cannot look up release {tag}: {probe.stderr.strip()}')
    with tempfile.TemporaryDirectory() as scratch:
        try:
            path = Path(scratch) / MANIFEST_NAME
            cat.download(f'{base_url()}/{tag}/{MANIFEST_NAME}', path)
            held = json.loads(path.read_text()).get('digest')
        except NotFound:
            return False  # a release with no manifest is not ours
        # Any other failure (5xx, timeout) propagates: it must not read as
        # "taken" and make publish create a second release.
    return held == digest_of(entries)


def publish(args):
    library = read_library()
    entries = packed(library)
    if not entries:
        raise Failure('every sound is bundled; there is no pack to publish')
    problems = []
    for entry in entries:
        path = PACK_DIR / entry['file']
        if not path.is_file():
            problems.append(f"{entry['file']} is missing from {PACK_DIR.relative_to(ROOT)}")
        elif path.stat().st_size != entry['bytes'] or cat.sha256_file(path) != entry['sha256']:
            problems.append(f"{entry['file']} is not the file the library pins")
    if problems:
        raise Failure('cannot publish the pack:\n  ' + '\n  '.join(problems) +
                      '\nBuild it with tools/meditejo/sounds/process_sounds.py, or fetch the '
                      'pinned one with `sound_pack.py fetch`.')
    digest = digest_of(entries)
    pinned = library.get('pack')
    if isinstance(pinned, dict) and pinned.get('digest') == digest:
        print(f"already pinned: {pinned.get('release')}")
        return

    day = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%d')
    tag, suffix, create = f'sounds-{day}', 1, True
    while not args.dry_run:
        state = release_state(tag, entries)
        if state is None:
            break
        if state:
            print(f'{tag} already carries this pack; pinning it')
            create = False
            break
        suffix += 1
        tag = f'sounds-{day}-{suffix}'
    total = sum(e['bytes'] for e in entries)
    manifest = {
        'schema': 1, 'release': tag, 'digest': digest,
        'files': [{'id': e['id'], 'file': e['file'], 'bytes': e['bytes'], 'sha256': e['sha256']}
                  for e in sorted(entries, key=lambda e: e['id'])],
    }
    if args.dry_run:
        print(f'would create prerelease {tag} with {len(entries)} files ({total} bytes) '
              f'and {MANIFEST_NAME}, and pin it in {LIBRARY.relative_to(ROOT)}')
        return
    if create:
        with tempfile.TemporaryDirectory() as scratch:
            manifest_path = Path(scratch) / MANIFEST_NAME
            manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
            notes = (
                'Meditejo sound pack: looped recordings the app downloads on request '
                '(the sounds that do not ship inside the APK). Not an app release: it is '
                'a prerelease, which the in-app updater never reads. The app fetches each '
                'file by the SHA-256 pinned in assets/sounds/sounds.json; see '
                f'docs/fork/ARCHITECTURE.md.\n\n{len(entries)} sounds, {total} bytes. '
                f'Pack digest: {digest}')
            done = cat.gh('release', 'create', tag,
                          *[str(PACK_DIR / e['file']) for e in entries], str(manifest_path),
                          '--repo', cat.REPO, '--prerelease', '--latest=false',
                          '--title', f'Sound pack {day}', '--notes', notes, check=False)
        if done.returncode != 0:
            raise Failure(f'gh release create {tag} failed: {done.stderr.strip()}')
        print(done.stdout.strip())
        # Prove the upload before pinning it: read every file back and compare.
        for entry in entries:
            with tempfile.TemporaryDirectory() as scratch:
                size, got = cat.download(file_url(tag, entry), Path(scratch) / entry['file'])
            if size != entry['bytes'] or got != entry['sha256']:
                raise Failure(f"{tag} was created but {entry['file']} reads back as {size} bytes / {got}")
    library['pack'] = {'release': tag, 'digest': digest, 'files': len(entries), 'bytes': total}
    ordered = {k: library[k] for k in library if k not in ('pack', 'sounds')}
    ordered['pack'] = library['pack']
    ordered['sounds'] = library['sounds']
    LIBRARY.write_text(json.dumps(ordered, indent=2, ensure_ascii=False) + '\n')
    print(f'pinned {tag} in {LIBRARY.relative_to(ROOT)}')


# ---------------------------------------------------------------- verify-apk

def verify_apk(args):
    library = read_library()
    prefix = 'assets/flutter_assets/assets/sounds/'
    with zipfile.ZipFile(args.apk) as apk:
        shipped = {n[len(prefix):]: n for n in apk.namelist()
                   if n.startswith(prefix) and n.endswith('.opus')}
        wanted = {e['file']: e for e in bundled(library)}
        problems = [f'{name} is in the APK but belongs to the downloadable pack'
                    for name in sorted(set(shipped) - set(wanted))]
        problems += [f'{name} is bundled but missing from the APK' for name in sorted(set(wanted) - set(shipped))]
        for name, entry in wanted.items():
            if name in shipped:
                data = apk.read(shipped[name])
                if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
                    problems.append(f'{name} in the APK is not the file the library pins')
        try:
            packaged = apk.read(prefix + 'sounds.json')
        except KeyError:
            raise Failure(f'{args.apk} has no sounds.json')
    if packaged != LIBRARY.read_bytes():
        problems.append('the packaged sounds.json differs from the checkout')
    if problems:
        raise Failure(f'{args.apk}:\n  ' + '\n  '.join(problems))
    print(f'APK carries the {len(wanted)} bundled sounds and none of the pack')


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    commands = parser.add_subparsers(dest='command', required=True)
    for name, run, help_ in (('verify', verify, 'library, NOTICE and assets agree'),
                             ('status', status, 'the pack release is pinned and current'),
                             ('check', check, 'the pinned pack is downloadable')):
        sub = commands.add_parser(name, help=help_)
        sub.add_argument('--library', help="a sounds.json other than the checkout's")
        sub.set_defaults(run=run)
    sub = commands.add_parser('fetch', help='download and verify the pack')
    sub.add_argument('--dest', help='default: build/sound-pack')
    sub.set_defaults(run=fetch)
    sub = commands.add_parser('publish', help='upload the pack and pin it')
    sub.add_argument('--dry-run', action='store_true')
    sub.set_defaults(run=publish)
    sub = commands.add_parser('verify-apk', help='the APK carries the bundled sounds only')
    sub.add_argument('apk')
    sub.set_defaults(run=verify_apk)
    args = parser.parse_args()
    try:
        args.run(args)
    except Failure as e:
        sys.exit(f'sound_pack.py: {e}')


if __name__ == '__main__':
    main()
