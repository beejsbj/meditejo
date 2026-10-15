#!/usr/bin/env python3
"""Stage source and public dependency content; never copy host credentials."""
import pathlib
import shutil
import subprocess
import sys
import tarfile

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
shutil.copy2(root / 'tools/meditejo/daytona_build.sh', stage / 'daytona_build.sh')
# Only package sources/hashes, never pub credentials or active global executables.
with tarfile.open(stage / 'pub-packages.tgz', 'w:gz') as archive:
    for name in ('hosted', 'hosted-hashes', 'git'):
        source = cache / name
        if source.exists():
            archive.add(source, arcname=name)
