# In-app updates

Meditejo updates itself from **GitHub Releases on the public `beejsbj/meditejo`**
(Android only; iOS has no updater and hides the UI). The release script builds and signs
on bjslab and publishes; the app finds the release, downloads the APK, checks it twice and hands
it to Android's installer.

## Versioning

| | Scheme | Example |
| --- | --- | --- |
| `versionName` | `MAJOR.MINOR.PATCH`, chosen by hand | `0.1.0` |
| `versionCode` | `YYMMDDnn`: build date plus a two-digit counter for that day, starting at `01` | `26101701` |
| Tag / release | `v<versionName>` | `v0.1.0` |
| APK | `meditejo-<versionName>.apk` | `meditejo-0.1.0.apk` |
| `pubspec.yaml` | `version: <versionName>+<versionCode>` | `0.1.0+26101701` |

- Android refuses a lower `versionCode`, and Medito's last build was `302473`. Every
  `YYMMDDnn` code is above it (`26101701` is about 87 times larger) and the code only grows,
  because `nn` counts up within a day and the date counts up across days. Eight digits fit an
  `int` until the year 2147.
- The code is never chosen by hand. `release.sh` takes the later of "today's first code" and
  "the highest code so far plus one". Two releases on one day get `…01`, `…02`. It refuses to
  go past `99` in a day.
- The `versionName` is what Burooj reads; the updater compares only `versionCode`. A release
  that re-uses an old `versionName` with a higher code still updates.
- **The first Meditejo version is `0.1.0`.** The branch's `pubspec.yaml` already says
  `0.1.0+26101701`, so the test APK built from this branch is the *installed* build and the
  first published release (`0.1.0`, code `26101702` or later) is something to update *to*.
  (The dev flavor shows it as `0.1.0-dev`.)
- **Releases use the `prod` flavor.** Both flavors install as `io.github.beejsbj.meditejo`,
  so either would update the other. `dev` adds a `-dev` name suffix and a different launcher
  icon; `prod` is the plain, durable app. Installing the first `prod` release over the dev
  build therefore changes the icon, which is the intent. `dev` stays for test builds
  (`build_apk.sh` default).

## The channel

Each release carries four assets:

| Asset | Purpose |
| --- | --- |
| `meditejo-<version>.apk` | the signed APK |
| `meditejo-<version>.apk.sha256` | `sha256sum` line, for people |
| `meditejo-release.json` | what the app reads (below) |
| (release body) | the notes, shown in About |

```json
{
  "schema": 1,
  "versionName": "0.1.0",
  "versionCode": 26101702,
  "apk": "meditejo-0.1.0.apk",
  "size": 41875546,
  "sha256": "<64 hex>",
  "certificateSha256": "<64 hex>"
}
```

`meditejo-release.json` is how the app learns the `versionCode` (a tag or asset-name
convention would have to be parsed back out of a string; this is explicit and also carries the
hash and size). The APK URL comes from the API's own asset list, not from the JSON, and must
sit under `https://github.com/beejsbj/meditejo/releases/download/`.

## Releasing

```bash
tools/meditejo/release.sh 0.1.0 --notes notes.md --dry-run   # print the plan
tools/meditejo/release.sh 0.1.0 --notes notes.md --yes       # publish
```

Steps: preflight (clean tree matching origin, `gh` auth, tag unused, `release/v<version>` unused) → pick
the next `versionCode` → **create `release/v<version>`** → **refresh the bundled Dharma Seed catalogue only if
the pinned one is over 30 days old**
(`tools/meditejo/dharma_seed_snapshot.dart`, a delta from the pinned snapshot; if it changed, the new
snapshot is uploaded as a `catalogue-YYYYMMDD` prerelease and a commit on the release branch pins it in
`catalogue.json`, the manifest alone; `--refresh-catalogue` forces it, `--skip-snapshot` never does; the
app's search-time delta covers the gap; see ARCHITECTURE.md) → bump `pubspec.yaml` and commit it on the
release branch → push the branch and **`gh pr create` against `develop`** → **wait for the required checks**
(`review-evidence`; polled for up to 30 minutes, `MEDITEJO_RELEASE_CHECKS_TIMEOUT` seconds) →
**`gh pr merge --merge`** (pinned to the commit that was pushed, never `--admin`) → fast-forward local
`develop` to the **merge commit**, delete the release branch → `build_apk.sh <merge commit> --flavor prod`
(GitHub Actions builds unsigned, bjslab aligns and signs with the durable key and checks the pinned
digest) → independently re-verify the pinned digest on the staged APK → write the `.sha256`
and `meditejo-release.json` → `gh release create v<version> --target <merge commit> --repo beejsbj/meditejo`.

Nothing is pushed to `develop` directly. The required check passes on a PR with no review threads, so on a bump PR it is a CI gate rather than a human read; `--allow-branch` is therefore refused unless the branch points exactly at `origin/develop`. Before this, the script committed the bump and pushed it straight to
`develop`, which skipped the `review-evidence` required check (Burooj: "Go through a PR please"). The APK and
the tag now come from the commit `develop` actually holds, so what ships is what was merged.

If a run fails part-way:

- **Before the merge** (the build has not started): the PR is left open and `develop` is untouched. A failed
  required check or a timeout says so and stops. Close the PR, delete `release/v<version>` on origin and
  locally (`git switch develop && git branch -D release/v<version>`), fix the cause, and run again. An uploaded
  `catalogue-…` prerelease stays; it is harmless and a re-run reuses it.
- **After the merge** (the build, signing or publish failed): `develop` already carries the bump. Run the same
  version again: the script sees `pubspec.yaml` at `<version>+<code>` with a code nobody has published,
  skips the branch, catalogue and PR, and builds `develop` as it stands.
- **After the draft release exists**: `gh release delete v<version> --repo beejsbj/meditejo --yes` first.

`--dry-run` prints every command (including the PR, the wait for checks, the merge and the build from the merge
commit), changes nothing and contacts nothing except a `git fetch`, read-only `gh` lookups for the latest
published code (skipped when offline) and a HEAD request for the pinned catalogue. The script is tested offline
by `python3 -I -m unittest discover -s tools/meditejo -p 'test_release.py'` (a fake `gh` and a local bare
`origin`: the dry-run plan, the refusals, a live run through the merge up to the build, a failed check, and the
resume).

Medito's `prepare_release.sh` and its `release` skill drove the App Store / Play pipeline
(date-based names, `release_notes.txt`, fastlane). The skill is replaced by one that points at
`release.sh`; `prepare_release.sh` stays untouched, since the iOS fastlane and
`release.yml` still reference it.

## Catalogue releases are not app releases

The same repository also holds `catalogue-YYYYMMDD` releases, the bundled Dharma Seed snapshot (see
ARCHITECTURE.md, "The bundled catalogue"). They are **prereleases**, they have no `meditejo-release.json`,
and the updater never offers them:

- `releases/latest`, the only endpoint the app reads, returns the newest published release that is not a
  draft or prerelease. Checked 2026-10-26: with `catalogue-20261019` created, it still answered `v0.1.3`.
- If one were ever published without the flag, `ReleaseListing.fromApi` still refuses it, because only
  `v<MAJOR.MINOR.PATCH>` tags are app releases. The user would see "unavailable" in About, not an update;
  fix it by marking the release a prerelease again.
- Never make a catalogue release "latest" (`gh release create` for it passes `--prerelease --latest=false`).

## The updater

Dart in `lib/services/updates/`, state in `lib/providers/updates/`, UI in
`lib/views/settings/widgets/update_section.dart` (the About group on the You/Settings page, which carries the version
and Check for updates inline) and `lib/views/home/widgets/update_notice.dart`,
Android in `ApkUpdaterBridge.kt`.

1. **Check** (at most daily, 10 s after launch, and at once on the first launch of a new build, so
   About's "Last checked" is never older than the update; or "Check for updates"): `GET
   /repos/beejsbj/meditejo/releases/latest` with `If-None-Match`. A `304` reuses the cached
   release and saves bandwidth (it still counts against the unauthenticated limit, which one
   request a day cannot reach). A new release also
   fetches `meditejo-release.json`.
2. **Compare** its `versionCode` with the installed one.
3. **Download** to app storage (`files/updates/`) with progress, hashing as it streams; refuse
   unless the SHA-256 equals the published one.
4. **Inspect and pin** in Kotlin: read the APK's signing certificate and compare its SHA-256
   with the pinned digest; also require our package name and the expected `versionCode`.
5. **Install** through a `PackageInstaller` session, after sending the user to "Install unknown
   apps" once if needed. Stale APKs are deleted on the next launch.

### Signature check

`getPackageArchiveInfo(path, GET_SIGNING_CERTIFICATES)` returns the APK's current signers.
`UpdateSignaturePolicy.signersMatchPin` (pure, JVM-tested) accepts only **exactly one** signer
whose certificate SHA-256 equals the digest pinned in code:
`07:87:EC:F8:50:D8:DF:93:F9:02:DB:09:A9:8D:C6:1E:9C:E4:0F:E1:39:BF:54:35:A5:35:A6:2E:18:5A:50:31`.
Android would also reject an APK signed with another key at install time; this check comes
first so the user gets a plain message and nothing is handed to the installer. A signing-key
rotation would need a new pin shipped in an update signed by the old key.

### Why `PackageInstaller` sessions

Sessions report the outcome (success, user cancelled, blocked, conflict) back to the app, work
without exposing a file URI, and are the supported path on Android 14 and 15, where
`ACTION_VIEW`/`ACTION_INSTALL_PACKAGE` on a `content://` URI is deprecated and gives no result.
The APK is streamed into the session from the app's private directory, so no FileProvider
paths are added. Every update shows Android's own confirmation prompt: skipping it
(`USER_ACTION_NOT_REQUIRED`) needs the `UPDATE_PACKAGES_WITHOUT_USER_ACTION` permission, which
the app does not declare. If the receiver cannot open that prompt (for example the app was sent
to the background), the "Installing" state gives up after three minutes and offers Update again.
