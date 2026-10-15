#!/usr/bin/env python3
"""Fetch an explicit Maven artifact list over HTTP; never runs Gradle."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('destination', type=Path)
parser.add_argument('--list', type=Path, default=Path(__file__).with_name('portal-artifacts.txt'))
args = parser.parse_args()
base = 'https://plugins.gradle.org/m2/'
records = {}


def fetch(relative, optional=False):
    target = args.destination / relative
    try:
        with urllib.request.urlopen(base + relative, timeout=60) as response:
            data = response.read()
    except urllib.error.HTTPError as error:
        if optional and error.code == 404:
            return None
        raise
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    records[relative] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    return data


for line in args.list.read_text().splitlines():
    coordinate = line.split('#', 1)[0].strip()
    if not coordinate:
        continue
    if not re.fullmatch(r'[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+', coordinate):
        raise SystemExit(f'Invalid coordinate: {coordinate}')
    group, artifact, version = coordinate.split(':')
    directory = f'{group.replace(".", "/")}/{artifact}/{version}/'
    stem = f'{artifact}-{version}'
    pom = fetch(directory + stem + '.pom')
    packaging = ET.fromstring(pom).findtext('{*}packaging', 'jar')
    if packaging != 'pom':
        fetch(directory + stem + '.jar')
    module = fetch(directory + stem + '.module', optional=True)
    if module:
        for variant in json.loads(module).get('variants', []):
            for file in variant.get('files', []):
                name = file['url']
                if '/' in name or name in ('.', '..'):
                    raise SystemExit(f'Unexpected artifact filename: {name}')
                relative = directory + name
                if relative not in records:
                    fetch(relative)
                expected = file.get('sha256')
                if expected and records[relative]['sha256'] != expected:
                    raise SystemExit(f'Checksum mismatch: {relative}')
    print(f'Fetched {coordinate}', flush=True)
args.destination.mkdir(parents=True, exist_ok=True)
(args.destination / 'manifest.json').write_text(json.dumps(records, indent=2) + '\n')
print(f'Portal repository: {len(records)} files, {sum(x["bytes"] for x in records.values())} bytes')
