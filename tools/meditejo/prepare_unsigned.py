#!/usr/bin/env python3
"""Remove any CI/debug signatures and record the public artifact's provenance."""
import hashlib
import json
import os
from pathlib import Path
import sys
import zipfile

source, destination = map(Path, sys.argv[1:3])
destination.mkdir(parents=True, exist_ok=True)
output = destination / 'unsigned.apk'
# Rewriting the ZIP removes APK v2/v3 signing blocks as well as v1 entries.
with zipfile.ZipFile(source) as original, zipfile.ZipFile(output, 'w') as unsigned:
    if original.testzip() is not None:
        raise SystemExit('Built APK has a damaged ZIP entry')
    for entry in original.infolist():
        name = entry.filename.upper()
        if name.startswith('META-INF/') and (
            name.endswith(('.SF', '.RSA', '.DSA', '.EC'))
            or name == 'META-INF/MANIFEST.MF'
        ):
            continue
        unsigned.writestr(entry, original.read(entry))
metadata = {
    'sha': os.environ['GITHUB_SHA'],
    'flavor': os.environ['FLAVOR'],
    'mode': os.environ['MODE'],
    'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
    'bytes': output.stat().st_size,
}
(destination / 'build.json').write_text(json.dumps(metadata, indent=2) + '\n')
print(json.dumps(metadata))
