#!/usr/bin/env python3
"""Verify that the APK ships every full notice used by the in-app registry."""
import json
from pathlib import Path
import sys
import zipfile

root = Path(__file__).resolve().parents[2]
manifest = root / 'assets/licenses/newpipe-runtime-dependencies.json'
components = json.loads(manifest.read_text())['components']
paths = {manifest, *(root / 'assets/licenses' / text for c in components for text in c['texts'])}
with zipfile.ZipFile(sys.argv[1]) as apk:
    for path in sorted(paths):
        asset = 'assets/flutter_assets/' + path.relative_to(root).as_posix()
        if apk.read(asset) != path.read_bytes():
            raise SystemExit(f'APK notice differs: {asset}')
    native = [name for name in apk.namelist() if name.startswith('META-INF/') and
              any(word in name.upper() for word in ('LICENSE', 'NOTICE', 'COPYRIGHT'))]
    if not native:
        raise SystemExit('APK stripped all native licence/notice resources')
    print(f'APK carries {len(paths)} full notice assets and {len(native)} native legal resources')
