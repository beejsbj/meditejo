#!/usr/bin/env python3
"""Verify that the APK ships every full notice used by the in-app registry."""
import json
from pathlib import Path
import sys
import zipfile

root = Path(__file__).resolve().parents[2]
manifests = [root / 'assets/licenses/newpipe-runtime-dependencies.json',
             root / 'assets/licenses/soloud-native-components.json']
paths = set(manifests)
for manifest in manifests:
    components = json.loads(manifest.read_text())['components']
    paths |= {root / 'assets/licenses' / text for c in components for text in c['texts']}
# The bundled sounds' own licence notice travels with them.
paths.add(root / 'assets/sounds/NOTICE')
# The cue sounds' notice (pulse CC0 dedication, bell attribution) ships too.
paths.add(root / 'assets/audio/NOTICE')
# Every bundled cue sound ships byte-for-byte, and the notice names it.
cue_notice = (root / 'assets/audio/NOTICE').read_text()
cue_sounds = sorted((root / 'assets/audio').glob('*.wav'))
unnamed = [p.name for p in cue_sounds if p.name not in cue_notice]
if unnamed:
    raise SystemExit(f'assets/audio/NOTICE does not credit: {", ".join(unnamed)}')
with zipfile.ZipFile(sys.argv[1]) as apk:
    for sound in cue_sounds:
        asset = 'assets/flutter_assets/' + sound.relative_to(root).as_posix()
        if asset not in apk.namelist():
            raise SystemExit(f'APK is missing cue sound: {asset}')
        if apk.read(asset) != sound.read_bytes():
            raise SystemExit(f'APK cue sound differs: {asset}')
    for path in sorted(paths):
        asset = 'assets/flutter_assets/' + path.relative_to(root).as_posix()
        if apk.read(asset) != path.read_bytes():
            raise SystemExit(f'APK notice differs: {asset}')
    # The pinned runtime JARs were inspected: only jsoup ships a legal
    # resource in its binary JAR. All others need the explicit assets above.
    if apk.read('META-INF/jsoup/LICENSE') != (root / 'assets/licenses/MIT-jsoup.txt').read_bytes():
        raise SystemExit('APK stripped or altered jsoup native MIT notice')
    native = [name for name in apk.namelist() if name.startswith('META-INF/') and
              any(word in name.upper() for word in ('LICENSE', 'NOTICE', 'COPYRIGHT'))]
    if not native:
        raise SystemExit('APK stripped all native licence/notice resources')
    print(f'APK carries {len(paths)} full notice assets, {len(cue_sounds)} credited cue sounds and {len(native)} native legal resources')
