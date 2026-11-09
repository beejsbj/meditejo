# Worker brief — Meditejo ux-pass

You are implementing ONE GitHub issue (or a small named group) in beejsbj/meditejo, a Flutter fork of Medito. Default branch `develop`. Owner: Burooj. You work in your own git worktree.

## Read first
- The issue(s) on GitHub, body AND all comments (GitHub MCP tools; load via ToolSearch "+github issue"). Comments often contain the decided design.
- Triage notes for every issue: `docs/fork/agents/triage.md`
- Toolchain recipe: `docs/fork/agents/flutter-setup.md`
- Design record (branch `ux/pass`): `git show origin/ux/pass:docs/fork/ux/interaction-model.md`, `.../field-notes-0.1.4.md`.

## Owner decisions already made (apply where relevant; do not contradict)
- No Favourites anywhere. Only Pin, with a pin icon (never a heart). (#79)
- The 5th tab becomes **Settings**; stats/history ("You" stuff) become reachable from Home/Library/Settings (exact placement TBD — don't build it unless your issue is #78).
- Library has no "In progress" section (Home's Continue covers it). Library sections by form (Playlists · Courses · Sessions) with Practice/Talks filter chips (#80 — not yet scheduled).
- App always opens on Home, not the last tab (#92).
- The 5th tab is Settings. Stats/history live on a **You page**, opened from a top-right button on Home, Library and Settings (#78).
- **No "+"/Add on Home** (#62 revised): adding to Home = pinning, done from other pages (⋮ / long-press). The full-width Add pill on Home goes away. **Library** gets a "+" for import / new things (incl. new quick tiles/shortcuts).
- **Practice and Talks keep SEPARATE defaults** (#75 reversed): a talk may start differently from a sit, e.g. 1.5×/2× playback speed for talks but not practice. Per-kind settings stay; per-course overrides stay. Do not merge them into one set.
- **Playback speed is per kind** (owner, 2026-11-05): practice and talks each keep their own persisted speed (talks likely sped up, practice rarely); the speed menu opens on the current kind and can set the other. Sections inside one file marked practice/talk are a separate future idea.
- **Library (#80): option A** — sections by form (Playlists · Courses · Sessions), Practice/Talks chips filter by track (owner, 2026-11-09).
- **Home mark (#63):** quiet at rest; tap = one slow breath; first open of the day = yesterday's mark morphs into today's with its name. No pinning hint.
- **Sound controls (#71):** not user-customisable; curated, consistent controls built from one shared vocabulary.
- **Stats at other speeds:** owner wants to know both recording length and real time spent (to build).
- Lock-screen/car speed changes play but are not saved.
- A **YouTube channel is a teacher**, and can be saved to Library like a Dharma Seed teacher.
- Merge policy: simple UI/UX and bug fixes may merge to develop after review + green CI. Bigger UX/UI changes are HELD and collected on branch `apk/ux-pass` for the owner to test as an APK.
- PRs #49 (Extend) and #51 (Design your own bell) are PARKED. Do not merge, rebase onto, or replicate them.
- Which base to build on: bigger UX work is built on `apk/ux-pass` and its PR opens into `apk/ux-pass`. Simple UI fixes and bug fixes go to `develop`.

## Setup in your worktree
```
export PATH=/opt/flutter/bin:$PATH
# bigger UX work: base = apk/ux-pass ; simple UI fix or bug fix: base = develop
git fetch origin <base> && git checkout -b <your-branch> origin/<base>
flutter pub get
for f in pigeon_conf.dart pigeons/*.dart; do dart run pigeon --input "$f" --package_name=medito; done
dart run build_runner build --delete-conflicting-outputs
python3 -I tools/meditejo/catalogue.py fetch   # gitignored Dharma Seed catalogue; CI fetches it; without it test/services/categories fails
```
Branch name: `ux/<issue>-<short-slug>`. Never commit generated files (they are gitignored).

## Environment limits
No emulator / simulator. Verify with:
- Widget/unit tests for behaviour (add them under `test/`, mirroring existing tests; helpers in `test/helpers/` e.g. `dharma_seed_app.dart`, `library_app.dart`; fixtures `test/fixtures`).
- Screenshots for layout via the existing harness `test/screenshots/` (1080×2340 @2.625 = 411 dp = owner's Galaxy S23+). Run:
  `MEDITEJO_SCREENSHOTS=1 MEDITEJO_SHOT_DIR=<dir> flutter test test/screenshots/design_screenshots_test.dart --plain-name "<test name>"`
  If the screen you changed isn't covered, add a scenario to the harness. Use realistic fixtures: long real titles, large counts (e.g. "Practising the Jhānas", 32 sessions; Vervaeke course, 18 sessions). Short fixtures hide clipping bugs.
- Network images don't load in tests; generated art fallback is expected.
- Async UI actions: if an action changes the data that makes its own widget exist (unpin, clear, remove), the widget may unmount before the await finishes. Capture Navigator/ScaffoldMessenger/theme BEFORE the first await, and test with a delayed store, not only instantly-completing mocks.
- Snackbars with an action persist forever by default in this Flutter version — pass `persist: false` (or use the app's `showSnackBar` helper), and guard Undo against state having changed since.
- Things you cannot verify here (audio, motion feel, thumb scrolling) → list them in the PR under "Needs device check".

## Before/after screenshots (layout-affecting changes)
Take BEFORE shots on your base branch (origin/apk/ux-pass or origin/develop) and AFTER shots on your branch, light (+ dark if relevant). Publish them on the orphan branch `ux-shots` (create it if missing: `git switch --orphan ux-shots` in a scratch clone/worktree, initial commit). Put files under `pr-<issue>/before-*.png`, `pr-<issue>/after-*.png`. Push with fetch+merge retry (other workers push there concurrently); never rebase or force-push. Embed in the PR body as `![](https://github.com/beejsbj/meditejo/blob/ux-shots/pr-<issue>/<file>.png?raw=true)` in a before | after table. Do not commit PNGs to your feature branch unless they are harness goldens that already exist.

## Checks before pushing
`dart format` ONLY on files you changed (never `dart format lib` / `.` — the toolchain formatter rewrites unrelated files and breaks CI). Before pushing, `git diff --stat origin/<base>` must list only files your issue needs. `flutter analyze` must print "No issues found!" (CI fails on ANY issue, even info), `flutter test` for affected tests + your new tests. If l10n strings added: add en/de/es to `lib/l10n/app_*.arb` (de/es may be best-effort translations; say so in PR) and regenerate (`flutter gen-l10n` if the repo uses it — check `l10n.yaml`).
Look at `.github/workflows` to know what CI runs (`checks`, `focused`, `review-evidence`) and satisfy it — read what `review-evidence` requires and comply.

## Standing rules (owner)
- Run the FULL test suite (`flutter test`) before the final push, not only the affected tests.
- Revert the stray `widgetbook/analysis_options.yaml` edit that the toolchain makes (`git checkout -- widgetbook/analysis_options.yaml`) so it never lands in your diff.
- Merge commits only: never rebase or force-push your branch. To update from the base, `git merge origin/<base>`.
- CodeRabbit reviews only non-draft PRs; the integrator marks the PR ready, not you.
- Never publish a release without Burooj's go-ahead.
- Real-device checks (audio, motion feel, thumb scrolling, hearing) belong to Burooj. List them under "Needs device check"; do not claim them verified.

## PR
- Push: `git push -u origin <branch>`. Use ONLY GitHub MCP tools (ToolSearch "+github", e.g. create_pull_request) for GitHub operations — never `gh`/`gh api`/curl to the API (gh is allowed only for search). Open a **draft** PR into `apk/ux-pass` for bigger UX work, or into `develop` for simple UI fixes and bug fixes. Mirror the repo PR template if one exists (`.github/pull_request_template.md` etc). Body: what changed, `Closes #N`, before/after table, tests added, "Needs device check" list, any deviations from the issue and why.
- End the PR body with the "🤖 Generated with [Claude Code](https://claude.com/claude-code)" line, plus any session link the current session's instructions specify.
- Commit messages: use whatever attribution the current session's instructions specify (Co-Authored-By and session trailer lines). Do not hard-code a session URL.
- Do NOT merge. Do NOT comment on issues. Do NOT mark ready-for-review. The orchestrator handles review and merge.
- Never skip/disable tests to get green.

## If blocked on a genuine product decision
Don't guess on something the owner should decide. Implement the clearly-decided part, and report the open question precisely (with 2–3 options and your recommendation) in your final message.

## Final message to the orchestrator (keep it short)
PR number + URL, branch, what was done, tests run + results, screenshots link, "needs device check" list, open questions, anything that might conflict with other ux-pass issues.
