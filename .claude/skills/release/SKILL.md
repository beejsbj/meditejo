---
name: release
description: Publishes a Meditejo release on GitHub (beejsbj/meditejo) so the app can update itself. Use when the user says "release", "cut a release", "ship a new version" or "publish an update". Runs tools/meditejo/release.sh. Never publish without the user's go-ahead.
argument-hint: "[version]"
---

Meditejo releases go to **GitHub Releases on `beejsbj/meditejo`**; the app checks there and updates itself. Medito's store pipeline (`prepare_release.sh`, fastlane, Play and App Store) is not used for this. Read `docs/fork/UPDATES.md` first.

## 1. Choose the version

`versionName` is `MAJOR.MINOR.PATCH` (for example `0.1.1`); ask Burooj if it isn't given. The `versionCode` (`YYMMDDnn`) is picked by the script.

## 2. Dry run

Work from a clean `develop` with the changes merged and pushed.

```bash
tools/meditejo/release.sh <version> --notes <notes.md> --dry-run
```

Read the plan: the chosen `versionCode`, the commands, and any `WOULD REFUSE` line. Write notes in plain, user-facing language (they appear in the app's About page); without `--notes` the script lists commit subjects since the previous release.

## 3. Publish

Publishing is outward-facing and cannot be taken back cleanly (the app may already have fetched the release). Show Burooj the dry run and notes; publish only on his go-ahead, or where he has standing approval for routine releases (BRIEF decision 12).

```bash
tools/meditejo/release.sh <version> --notes <notes.md> --yes
```

The script builds on GitHub Actions, signs on bjslab with the durable key and refuses any other certificate, then creates a draft release, checks its assets and publishes it. Never move or print the signing key.

## 4. Report

Give Burooj the release URL, `versionName (versionCode)` and the notes.
