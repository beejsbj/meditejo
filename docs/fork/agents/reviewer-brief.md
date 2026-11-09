# Reviewer brief — Meditejo ux-pass

You independently review ONE PR in beejsbj/meditejo (Flutter). Review only: do NOT push, comment on GitHub, approve, or merge. (The orchestrator or integrator re-reviews fix commits with the same checklist.)

## Read
- The PR (body, diff, files) and the issue(s) it closes, including ALL comments (GitHub MCP tools; ToolSearch "+github"). Decided designs often live in comments.
- Owner decisions + conventions: `docs/fork/agents/worker-brief.md` (section "Owner decisions already made").
- Triage notes: `docs/fork/agents/triage.md`
- Screenshots: PR body links point at branch `ux-shots`; `git fetch origin ux-shots` and view PNGs with the Read tool (`git show origin/ux-shots:<path> > file.png`).

## Run
```
export PATH=/opt/flutter/bin:$PATH
cd /home/user/meditejo && git fetch origin <branch>
git worktree add <scratch-dir>/review-<PR> origin/<branch>
cd that dir; flutter pub get
for f in pigeon_conf.dart pigeons/*.dart; do dart run pigeon --input "$f" --package_name=medito; done
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test <dirs relevant to changed files + new tests>
```
Remove the worktree afterwards (`git worktree remove --force <dir>`).

## Check
1. Does it fully satisfy the issue (and decisions in comments)? Anything missing, or scope creep?
2. Correctness: state, persistence/migration of stored prefs, null/empty cases, lifecycle (dispose, async gaps, `mounted`), races.
3. Do tests actually assert behaviour (not just "renders")? Missing obvious cases?
4. Layout at 411 dp: clipping/overflow, dark mode, long real titles. Screenshots match claims?
5. l10n: no new hard-coded English in touched UI; en/de/es keys consistent; generated `app_localizations*.dart` consistent with arb.
6. Dead code left behind; conflicts with owner decisions; anything that will make sibling ux-pass issues harder.
7. PR body has `Closes #N` for each issue.

## Report (concise)
Findings list: severity (blocker / should-fix / nit), file:line, concrete failure scenario, suggested fix. Then verdict: `merge-ready` | `fix then merge` | `needs owner` (with the exact question). If clean, say so briefly.
