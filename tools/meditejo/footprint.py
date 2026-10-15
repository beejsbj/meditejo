#!/usr/bin/env python3
"""Record allocated bytes with du at each stage and during the remote build."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

root = Path(__file__).resolve().parent


def size(path):
    if not path.exists():
        return 0
    result = subprocess.run(['du', '-s', '-B1', str(path)], capture_output=True, text=True)
    # Transient transform files may disappear while du walks a running build.
    return int(result.stdout.split()[0]) if result.stdout else 0


def measure(stage):
    sdk = Path(os.environ['ANDROID_HOME'])
    sdk_total = size(sdk)
    ndk = size(sdk / 'ndk')
    stat = os.statvfs(root)
    row = dict(stage=stage, time=time.time(),
               disk_used=(stat.f_blocks - stat.f_bfree) * stat.f_frsize,
               disk_available=stat.f_bavail * stat.f_frsize,
               flutter=size(Path('/tmp/flutter')), android_sdk=sdk_total,
               ndk=ndk, android_sdk_without_ndk=max(0, sdk_total - ndk),
               gradle=size(root / 'gradle-home'), pub=size(root / 'pub-cache'),
               build=size(root / 'app/build'),
               flutter_archive=size(Path('/tmp/flutter.tar.xz')))
    output = root / 'outputs/footprint.jsonl'
    with output.open('a') as stream:
        stream.write(json.dumps(row) + '\n')
    print('FOOTPRINT ' + json.dumps(row), flush=True)


if __name__ == '__main__':
    if sys.argv[1] == '--watch':
        pid = int(sys.argv[2])
        while True:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            measure('gradle-periodic')
            time.sleep(15)
    else:
        measure(sys.argv[1])
