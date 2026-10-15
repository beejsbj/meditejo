#!/usr/bin/env python3
"""Stage source and public dependency content; never copy host credentials."""
import json
import pathlib
import shutil
import subprocess
import sys
import tarfile
from urllib.parse import unquote, urlparse

root, stage, cache = map(pathlib.Path, sys.argv[1:])
names = subprocess.check_output(
    ['git', '-C', str(root), 'ls-files', '-z', '--cached', '--others', '--exclude-standard']
).decode().split('\0')
# Dart codegen outputs are intentionally ignored upstream but required to build.
for pattern in ('*.g.dart', '*.freezed.dart'):
    names.extend(str(p.relative_to(root)) for p in (root / 'lib').rglob(pattern))
for name in sorted(set(names)):
    path = pathlib.PurePosixPath(name)
    if not name or path.is_absolute() or '..' in path.parts:
        continue
    if path.parts[0] not in {'android', 'assets', 'lib'} and name not in {
        'pubspec.yaml', 'pubspec.lock', 'l10n.yaml', 'analysis_options.yaml'
    }:
        continue
    if any(p in {'.gradle', '.cxx', '.kotlin', 'build', 'captures', 'fastlane'} for p in path.parts):
        continue
    if path.name in {'keystore.properties', 'local.properties', 'google-services.json', 'auth.json'} or path.suffix in {'.jks', '.keystore', '.p12', '.pem', '.key'}:
        continue
    source = root / name
    if source.is_symlink() or not source.is_file():
        continue
    target = stage / 'app' / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
for name in ('daytona_build.sh', 'footprint.py'):
    shutil.copy2(pathlib.Path(__file__).resolve().parent / name, stage / name)
revision = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
(stage / 'source-revision.txt').write_text(revision + '\n')
print(f'Staging source {root} at {revision} (current working bytes)', flush=True)
# Use the resolved package graph, not unrelated packages in the shared cache.
# External Git/path dependencies need an explicit staging policy first.
cache = cache.resolve()
hosted = cache / 'hosted/pub.dev'
flutter_sdk = pathlib.Path(shutil.which('flutter')).resolve().parent.parent
packages = set()
for config_path in (root / '.dart_tool/package_config.json',
                    flutter_sdk / 'packages/flutter_tools/.dart_tool/package_config.json'):
    config = json.loads(config_path.read_text())
    for package in config['packages']:
        uri = urlparse(package['rootUri'])
        if uri.scheme not in ('', 'file'):
            raise SystemExit(f"Unsupported package URI for {package['name']}")
        package_root = pathlib.Path(unquote(uri.path))
        if not package_root.is_absolute():
            package_root = config_path.parent / package_root
        package_root = package_root.resolve()
        if package_root.is_relative_to(cache):
            if package_root.parent != hosted:
                raise SystemExit(f"Only hosted pub.dev dependencies may be uploaded: {package['name']}")
            packages.add(package_root)
        elif not package_root.is_relative_to(root) and not package_root.is_relative_to(flutter_sdk):
            raise SystemExit(f"External path dependency needs an explicit staging policy: {package['name']}")
# Only resolved package sources/hashes, never credentials or global executables.
with tarfile.open(stage / 'pub-packages.tgz', 'w:gz', compresslevel=1) as archive:
    for source in sorted(packages):
        archive.add(source, arcname=str(source.relative_to(cache)))
        digest = cache / 'hosted-hashes/pub.dev' / (source.name + '.sha256')
        if digest.is_file():
            archive.add(digest, arcname=str(digest.relative_to(cache)))
print(f'Staged {len(packages)} resolved pub.dev packages', flush=True)
