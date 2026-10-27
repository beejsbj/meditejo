"""Offline tests for release.sh: python3 -I -m unittest discover -s tools/meditejo -p 'test_release.py'

Each test builds a throwaway repository whose `origin` is a local bare repository
(standing in for GitHub through a url.insteadOf rewrite) and puts a fake `gh` on
PATH. The fake `gh` records what it is asked and, for `pr merge`, really merges the
branch in the bare repository. Nothing here reaches the network or publishes.
"""
import json
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name('release.sh')
GITHUB_URL = 'https://github.com/beejsbj/meditejo.git'

FAKE_GH = textwrap.dedent('''\
    #!/usr/bin/env python3
    import json, os, subprocess, sys
    args = sys.argv[1:]
    home = os.environ['FAKE_HOME']
    with open(os.path.join(home, 'gh.log'), 'a') as log:
        log.write(' '.join(args) + '\\n')
    def sh(*cmd, cwd=None):
        return subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()
    def flag(name):
        return args[args.index(name) + 1] if name in args else None
    joined = ' '.join(args)
    if args[:2] == ['auth', 'status']:
        sys.exit(0)
    if args[0] == 'api':
        print(os.environ.get('FAKE_LATEST_TAG', 'v0.1.0')); sys.exit(0)
    if args[:2] == ['release', 'download']:
        print(json.dumps({'versionCode': int(os.environ.get('FAKE_LATEST_CODE', '26101701'))})); sys.exit(0)
    if args[:2] == ['release', 'view']:
        sys.exit(1)
    if args[:2] == ['pr', 'create']:
        print('https://github.com/beejsbj/meditejo/pull/77'); sys.exit(0)
    if args[:2] == ['pr', 'checks']:
        bucket = os.environ.get('FAKE_CHECK', 'pass')
        print('review-evidence=' + bucket); sys.exit(0)
    if args[:2] == ['pr', 'merge']:
        bare = os.path.join(home, 'origin.git')
        work = os.path.join(home, 'merger')
        sh('git', 'clone', '-q', bare, work)
        sh('git', 'config', 'user.email', 'bot@example.org', cwd=work)
        sh('git', 'config', 'user.name', 'bot', cwd=work)
        head = sh('git', 'rev-parse', 'origin/' + os.environ['FAKE_RELEASE_BRANCH'], cwd=work)
        if flag('--match-head-commit') != head:
            print('head moved', file=sys.stderr); sys.exit(1)
        sh('git', 'merge', '-q', '--no-ff', '-m', 'Merge pull request #77', head, cwd=work)
        sh('git', 'push', '-q', 'origin', 'HEAD:develop', cwd=work)
        open(os.path.join(home, 'merged'), 'w').write(sh('git', 'rev-parse', 'HEAD', cwd=work))
        sys.exit(0)
    if args[:2] == ['pr', 'view']:
        print(open(os.path.join(home, 'merged')).read()); sys.exit(0)
    sys.exit(0)
''')


def git(*args, cwd, env=None):
    return subprocess.run(
        ['git', *args], cwd=cwd, check=True, capture_output=True, text=True, env=env
    ).stdout.strip()


class ReleaseScriptTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix='release-test.'))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.bare = self.home / 'origin.git'
        self.repo = self.home / 'repo'
        git('init', '-q', '--bare', '-b', 'develop', str(self.bare), cwd=self.home)
        self.repo.mkdir()
        git('init', '-q', '-b', 'develop', cwd=self.repo)
        git('config', 'user.email', 'dev@example.org', cwd=self.repo)
        git('config', 'user.name', 'dev', cwd=self.repo)
        git('remote', 'add', 'origin', GITHUB_URL, cwd=self.repo)
        git('config', f'url.{self.bare}.insteadOf', GITHUB_URL, cwd=self.repo)

        tools = self.repo / 'tools' / 'meditejo'
        tools.mkdir(parents=True)
        shutil.copy(SCRIPT, tools / 'release.sh')
        # The checks release.sh makes before a build, stubbed to succeed; the
        # build itself records the commit it was asked to build and stops.
        (tools / 'catalogue.py').write_text('import sys\nsys.exit(0)\n')
        (tools / 'build_apk.sh').write_text(
            '#!/usr/bin/env bash\n'
            f'echo "$1" > {self.home}/built\n'
            f'echo "$(git rev-parse HEAD)" > {self.home}/built_head\n'
            'echo "stub build stops the release here" >&2\n'
            'exit 7\n'
        )
        (tools / 'build_apk.sh').chmod(0o755)
        self.write_pubspec('0.1.0+26101701')
        self.commit_and_push('initial')

        bin_dir = self.home / 'bin'
        bin_dir.mkdir()
        (bin_dir / 'gh').write_text(FAKE_GH)
        (bin_dir / 'gh').chmod(0o755)
        self.env = {
            **os.environ,
            'PATH': f'{bin_dir}:{os.environ["PATH"]}',
            'FAKE_HOME': str(self.home),
            'MEDITEJO_RELEASE_DATE': '261027',
            'MEDITEJO_RELEASE_CHECKS_TIMEOUT': '1',
            'MEDITEJO_RELEASE_CHECKS_INTERVAL': '1',
            'GIT_CONFIG_GLOBAL': '/dev/null',
        }
        self.notes = self.home / 'notes.md'
        self.notes.write_text('Meditejo 0.2.0\n\n- A thing.\n')

    def write_pubspec(self, version):
        (self.repo / 'pubspec.yaml').write_text(f'name: medito\nversion: {version}\n')

    def commit_and_push(self, message):
        git('add', '-A', cwd=self.repo)
        git('commit', '-q', '-m', message, cwd=self.repo)
        git('push', '-q', 'origin', 'HEAD:refs/heads/develop', cwd=self.repo)

    def release(self, *extra, version='0.2.0', **env):
        proc = subprocess.run(
            [str(self.repo / 'tools/meditejo/release.sh'), version,
             '--notes', str(self.notes), '--skip-snapshot', *extra],
            cwd=self.repo, env={**self.env, **env}, capture_output=True, text=True, stdin=subprocess.DEVNULL,
        )
        return proc

    def gh_log(self):
        path = self.home / 'gh.log'
        return path.read_text().splitlines() if path.exists() else []

    # ------------------------------------------------------------- dry run

    def test_dry_run_plans_a_pr_then_builds_the_merged_commit(self):
        proc = self.release('--dry-run')
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn('WOULD REFUSE', proc.stdout + proc.stderr)
        plan = [line[2:] for line in proc.stdout.splitlines() if line.startswith('+ ')]
        wanted = [
            'git switch -q -c release/v0.2.0',
            'sed -i',
            'git commit -q -m',
            'git push --set-upstream origin release/v0.2.0',
            'gh pr create --repo beejsbj/meditejo --base develop --head release/v0.2.0',
            'gh pr checks <pr>',
            'gh pr merge <pr> --repo beejsbj/meditejo --merge',
            'env MEDITEJO_APK_DIR=',
            'gh release create v0.2.0 --repo beejsbj/meditejo --target \\<merged\\ commit\\>',
            'gh release edit v0.2.0',
        ]
        at = -1
        for fragment in wanted:
            found = next((i for i, line in enumerate(plan) if i > at and fragment in line), None)
            self.assertIsNotNone(found, f'{fragment!r} missing or out of order in:\n' + '\n'.join(plan))
            at = found
        text = '\n'.join(plan)
        self.assertIn('build_apk.sh \\<merged\\ commit\\> --flavor prod', text)
        self.assertNotIn('HEAD:refs/heads/develop', text, 'nothing is pushed to develop directly')
        self.assertEqual(git('rev-parse', 'HEAD', cwd=self.repo), git('rev-parse', 'develop', cwd=self.bare))
        self.assertEqual(git('branch', '--list', 'release/*', cwd=self.repo), '', 'a dry run makes no branch')

    def test_dry_run_refuses_off_develop(self):
        git('switch', '-q', '-c', 'feature', cwd=self.repo)
        git('push', '-q', 'origin', 'feature', cwd=self.repo)
        proc = self.release('--dry-run')
        self.assertIn("WOULD REFUSE: on branch 'feature', not develop", proc.stderr)

    def test_refuses_when_the_release_branch_exists_on_origin(self):
        git('push', '-q', 'origin', 'HEAD:refs/heads/release/v0.2.0', cwd=self.repo)
        proc = self.release('--dry-run')
        self.assertIn('WOULD REFUSE: release/v0.2.0 already exists on origin', proc.stderr)

    def test_refuses_a_dirty_tree_and_a_stale_checkout(self):
        (self.repo / 'stray.txt').write_text('x')
        self.assertIn('the working tree is not clean', self.release('--dry-run').stderr)
        (self.repo / 'stray.txt').unlink()
        (self.repo / 'pubspec.yaml').write_text('name: medito\nversion: 0.1.0+26101701\n# local\n')
        git('commit', '-qam', 'local only', cwd=self.repo)
        self.assertIn('differs from origin/develop', self.release('--dry-run').stderr)

    # ----------------------------------------------------------- live path

    def test_live_run_merges_through_the_pr_and_builds_the_merged_commit(self):
        bump_branch = 'release/v0.2.0'
        proc = self.release('--yes', FAKE_RELEASE_BRANCH=bump_branch)
        # The stub build exits 7, so the run stops there: everything before it is the subject.
        self.assertEqual(proc.returncode, 7, proc.stdout + proc.stderr)

        calls = self.gh_log()
        create = next(c for c in calls if c.startswith('pr create'))
        self.assertIn('--base develop', create)
        self.assertIn(f'--head {bump_branch}', create)
        self.assertIn('--title release: Meditejo 0.2.0 (26102701)', create)
        merge = next(c for c in calls if c.startswith('pr merge'))
        self.assertIn('--merge', merge)
        self.assertNotIn('--admin', merge)
        self.assertLess(
            next(i for i, c in enumerate(calls) if c.startswith('pr checks')),
            next(i for i, c in enumerate(calls) if c.startswith('pr merge')),
            'the checks are read before the merge',
        )

        merged = (self.home / 'merged').read_text()
        self.assertEqual((self.home / 'built').read_text().strip(), merged, 'built from the merge commit')
        self.assertEqual(git('rev-parse', 'HEAD', cwd=self.repo), merged, 'local develop is at the merge commit')
        self.assertEqual(git('rev-parse', 'develop', cwd=self.bare), merged)
        self.assertEqual(git('rev-parse', '--abbrev-ref', 'HEAD', cwd=self.repo), 'develop')
        pubspec = (self.repo / 'pubspec.yaml').read_text()
        self.assertIn('version: 0.2.0+26102701', pubspec)
        self.assertIn(
            'release: Meditejo 0.2.0 (26102701)', git('log', '--format=%s', '--no-merges', cwd=self.repo).splitlines()
        )
        self.assertEqual(git('branch', '--list', bump_branch, cwd=self.repo), '', 'local release branch removed')
        self.assertEqual(git('branch', '--list', bump_branch, cwd=self.bare), '', 'remote release branch removed')

    def test_a_failed_required_check_leaves_the_pr_open_and_unmerged(self):
        proc = self.release('--yes', FAKE_CHECK='fail', FAKE_RELEASE_BRANCH='release/v0.2.0')
        self.assertEqual(proc.returncode, 1)
        self.assertIn('A required check failed on #77', proc.stderr)
        self.assertFalse(any(c.startswith('pr merge') for c in self.gh_log()))
        self.assertFalse((self.home / 'built').exists())
        self.assertNotIn('0.2.0', git('show', 'develop:pubspec.yaml', cwd=self.bare), 'develop never got the bump')

    def test_checks_that_never_finish_are_not_merged(self):
        proc = self.release('--yes', FAKE_CHECK='pending', FAKE_RELEASE_BRANCH='release/v0.2.0')
        self.assertEqual(proc.returncode, 1)
        self.assertIn('did not finish within 1s', proc.stderr)
        self.assertFalse(any(c.startswith('pr merge') for c in self.gh_log()))

    def test_a_rerun_after_a_merged_bump_builds_develop_without_a_second_pr(self):
        self.write_pubspec('0.2.0+26102701')
        self.commit_and_push('release: Meditejo 0.2.0 (26102701)')
        proc = self.release('--yes')
        self.assertEqual(proc.returncode, 7, proc.stdout + proc.stderr)
        self.assertIn('resuming', proc.stdout)
        self.assertFalse(any(c.startswith('pr ') for c in self.gh_log()), self.gh_log())
        self.assertEqual((self.home / 'built').read_text().strip(), git('rev-parse', 'HEAD', cwd=self.repo))
        self.assertEqual(git('branch', '--list', 'release/*', cwd=self.repo), '')


if __name__ == '__main__':
    unittest.main()
