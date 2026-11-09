# Agent briefs for the ux-pass work

Snapshot from 2026-11-09. These files were written during a cloud orchestration session so a local Claude Code thread can pick the work up. Current state lives in the handoff issue: https://github.com/beejsbj/meditejo/issues/136. If this folder and the issue disagree, the issue wins.

## Files

- `worker-brief.md`: instructions for the agent that implements one issue. Owner decisions, setup, test and screenshot rules, PR rules.
- `reviewer-brief.md`: instructions for an independent reviewer of one PR. Review only; no pushing or merging.
- `merger-brief.md`: instructions for the integrator who takes a reviewed PR to merged (CI, CodeRabbit, conflicts, merge).
- `triage.md`: per-issue triage of the ux-pass issues (size, files, dependencies, how to verify), plus the "Integration notes (apk/ux-pass)" section at the end.
- `per-kind-defaults.md`: notes on Practice and Talks keeping separate defaults and per-kind playback speed.
- `flutter-setup.md`: the Flutter toolchain recipe the briefs point to.

## Workflow

1. A worker implements one issue on its own branch. Bigger UX work is built on `apk/ux-pass` and its draft PR opens into `apk/ux-pass`. Simple UI fixes and bug fixes go to `develop`.
2. An independent reviewer reviews the PR. When the worker pushes fix commits, a reviewer checks those commits again.
3. An integrator merges the reviewed PR into `apk/ux-pass` and updates the tracking issue #115. Merge commits only; never rebase or force-push.

Real-device checks and release decisions stay with Burooj.
