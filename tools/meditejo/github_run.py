#!/usr/bin/env python3
"""Find/build a committed SHA on GitHub; download and check its unsigned APK."""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

REPO = 'beejsbj/meditejo'
WORKFLOW = '.github/workflows/meditejo-apk.yml'


def command(*args, capture=True):
    result = subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def api(endpoint, **fields):
    args = ['gh', 'api', '--method', 'GET', f'repos/{REPO}/{endpoint}']
    for key, value in fields.items():
        args.extend(['-f', f'{key}={value}'])
    return json.loads(command(*args))


def parameters(run):
    if run['event'] == 'push':
        match = re.fullmatch(r'apk/build/(dev|prod)/(release|debug)/[0-9a-f]{40}(?:-[0-9]+)?', run['head_branch'])
        return match.groups() if match else ('dev', 'release')
    match = re.match(r'APK (dev|prod) (release|debug) ', run['display_title'])
    return match.groups() if match else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ref')
    parser.add_argument('flavor', choices=['dev', 'prod'])
    parser.add_argument('mode', choices=['release', 'debug'])
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    sha = command('git', 'rev-parse', '--verify', f'{args.ref}^{{commit}}')
    command('git', 'cat-file', '-e', f'{sha}:{WORKFLOW}')
    options = (args.flavor, args.mode)

    def find_run():
        runs = api('actions/runs', head_sha=sha, per_page=100)['workflow_runs']
        candidates = [run for run in runs if run['head_sha'] == sha
                      and run['path'] == WORKFLOW and parameters(run) == options]
        return max(candidates, key=lambda run: run['id']) if candidates else None

    def trigger(previous_id=0):
        suffix = f'-{time.time_ns()}' if previous_id else ''
        branch = f'apk/build/{args.flavor}/{args.mode}/{sha}{suffix}'
        # Explicit remote URL prevents an upstream remote from receiving a push.
        command('git', 'push', f'https://github.com/{REPO}.git', f'{sha}:refs/heads/{branch}', capture=False)
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            candidate = find_run()
            if candidate is not None and candidate['id'] > previous_id:
                return candidate
            time.sleep(3)
        raise SystemExit(f'No new workflow appeared for {sha}; inspect https://github.com/{REPO}/actions')

    def watch(candidate):
        print(f"Run: {candidate['html_url']}", flush=True)
        command('gh', 'run', 'watch', str(candidate['id']), '--repo', REPO,
                '--exit-status', '--compact', '--interval', '10', capture=False)

    run = find_run() or trigger()
    watch(run)
    run_id = str(run['id'])
    artifact_name = f'meditejo-{args.flavor}-{args.mode}-{sha[:8]}'
    artifacts = api(f'actions/runs/{run_id}/artifacts')['artifacts']
    if not any(item['name'] == artifact_name and not item['expired'] for item in artifacts):
        # GitHub permits reruns only within 30 days of the original run.
        created = datetime.fromisoformat(run['created_at'].replace('Z', '+00:00'))
        if datetime.now(timezone.utc) - created >= timedelta(days=29):
            run = trigger(run['id'])
        else:
            previous_attempt = api(f'actions/runs/{run_id}')['run_attempt']
            command('gh', 'run', 'rerun', run_id, '--repo', REPO, capture=False)
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                state = api(f'actions/runs/{run_id}')
                if state['status'] != 'completed' or state['run_attempt'] > previous_attempt:
                    run = state
                    break
                time.sleep(3)
            else:
                raise SystemExit(f'Rerun {run_id} did not start within 120 seconds')
        watch(run)
        run_id = str(run['id'])
    args.destination.mkdir(parents=True, exist_ok=True)
    command('gh', 'run', 'download', run_id, '--repo', REPO, '--name', artifact_name, '--dir', str(args.destination), capture=False)
    metadata = json.loads((args.destination / 'build.json').read_text())
    if (metadata['sha'], metadata['flavor'], metadata['mode']) != (sha, *options):
        raise SystemExit('Downloaded artifact does not match requested SHA/flavor/mode')
    apk = args.destination / 'unsigned.apk'
    if apk.stat().st_size != metadata['bytes'] or hashlib.sha256(apk.read_bytes()).hexdigest() != metadata['sha256']:
        raise SystemExit('Downloaded APK does not match build.json')
    metadata.update(run_url=run['html_url'], run_id=run_id)
    (args.destination / 'result.json').write_text(json.dumps(metadata, indent=2) + '\n')


if __name__ == '__main__':
    main()
