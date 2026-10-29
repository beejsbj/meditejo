# Android build route

GitHub Actions builds an **unsigned APK targeting arm64**; bjslab aligns and signs it.
No phone install is performed by this route. The orchestrator owns installation.
The Daytona route is retired; its failures and measurements remain below.

## Prerequisites on bjslab

- Git, GitHub CLI (`gh auth status`), Python 3, Bash, Java/keytool.
- Push/actions access to `beejsbj/meditejo`. No new GitHub secret is needed.
- The existing durable key and password under `~/.config/meditejo/signing/`.
- User Android build-tools 36.0.0 at
  `~/.local/share/android-sdk/build-tools/36.0.0`, already installed. Override
  with `MEDITEJO_BUILD_TOOLS`. Only zipalign/apksigner run locally; never Gradle.
- A committed ref containing `.github/workflows/meditejo-apk.yml` and the
  backend removal/rename stack. Uncommitted source is not uploaded.

## One command

```bash
tools/meditejo/build_apk.sh origin/develop --name meditejo
```

Defaults: current committed HEAD, flavor `dev`, mode `release`, Flutter target arm64.
Options: `--flavor dev|prod`, `--mode release|debug`, `--name OUTPUT_PREFIX`.
Defaults can be changed through `MEDITEJO_FLAVOR`, `MEDITEJO_BUILD_MODE` and
`MEDITEJO_APK_DIR`. Application ID comes from the selected checkout's Gradle
configuration; the script does not override identity.

The script finds a matching run for the exact commit, flavor and mode. If none
exists, it pushes that commit to `apk/build/<flavor>/<mode>/<fullsha>` without
force and waits for the push workflow. Existing `apk/**` push runs default to
dev/release. This works before PR #1 merges. `workflow_dispatch` is also
available once the workflow is on the default branch, with flavor and mode
inputs. See [GitHub's trigger documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows).

Before the push, it checks that the Dharma Seed snapshot pinned by the ref's
`catalogue.json` is downloadable (see the catalogue section below). It uses `gh run watch --exit-status` and `gh run download`, verifies artifact
metadata against the requested commit/configuration and APK SHA-256, aligns
16 KiB native libraries, signs locally and verifies both alignment and signing
certificate. Expired artifacts trigger a rerun of the same commit (or a fresh uniquely
named push run when the original is too old to rerun). A failed
build stops before signing; inspect the printed run URL and use
`gh run view RUN_ID --repo beejsbj/meditejo --log-failed`.

Outputs go to `~/.local/share/meditejo/apk/<prefix>-<shortsha>.apk`, with
`.build.json` provenance and `.certificate.txt` verification beside the APK.
The command prints the path, bytes and certificate digest. Generic default
prefix: `meditejo-<flavor>-<mode>`.

## The Dharma Seed catalogue (fetch before building or testing locally)

The bundled catalogue snapshot (`assets/dharma_seed/catalogue.sqlite.gz`, 13 MiB)
is **not in git**: `catalogue.json`, which is, pins it, and it is a release
asset on a `catalogue-YYYYMMDD` prerelease of `beejsbj/meditejo`. CI fetches it
itself. In a fresh checkout or worktree, before a local build or a full
`flutter test`, run:

```bash
python3 -I tools/meditejo/catalogue.py fetch
```

It downloads the pinned asset (no login or token), checks its size and SHA-256
against the manifest, and does nothing when the file is already the right one.
Without it, `test/services/dharma_seed/dharma_seed_snapshot_test.dart` fails
with this command in its message, and the app would build with no catalogue.
Tool tests: `python3 -I -m unittest discover -s tools/meditejo -p 'test_catalogue.py'`.
See ARCHITECTURE.md ("The bundled catalogue") for the rest.

## The dhammatalks.org snapshot (in git)

`assets/dhammatalks/catalogue.json.gz` (313 KB, 9,311 talks) and `manifest.json`
are **committed**: unlike the Dharma Seed catalogue they are well under 1 MB, so
there is no fetch step. Titles, dates and file addresses only, never audio. The
app bridges the snapshot to today with the site's two RSS feeds (50 items each),
so a snapshot more than 45 days old leaves a gap. The calendar must not turn CI
red, so past 45 days `dhammatalks_snapshot_test.dart` prints a warning and
reports itself skipped, and a CI step annotates the run with a warning;
`release.sh` is the hard rule and refuses a snapshot more than 14 days old (users
open a release for weeks). Refresh and commit:

```bash
python3 -I tools/meditejo/dhammatalks.py build      # about 47 requests, 4 s apart (~4 min); refuses to drop IDs
python3 -I tools/meditejo/dhammatalks.py check --max-age-days 14
python3 -I -m unittest discover -s tools/meditejo -p 'test_dhammatalks.py'
```

The builder reads `robots.txt` first, refuses what it disallows, makes serial
requests at least 3 s apart and identifies itself in its User-Agent.

## Publishing a release

`tools/meditejo/release.sh <version>` wraps this route (`build_apk.sh --flavor prod`) and publishes the signed APK as a GitHub release for the in-app updater; see [UPDATES.md](UPDATES.md). The build on GitHub fetches the catalogue snapshot that `catalogue.json` pins; `build_apk.sh` and `release.sh` check it is downloadable first.

## GitHub build and signing boundary

`.github/workflows/meditejo-apk.yml` uses ubuntu-latest, Java 17 and
`subosito/flutter-action@v2.12.0` with Flutter 3.47.2, matching existing CI.
It fetches pub.dev dependencies, runs the guarded Pigeon loop with
`--package_name=medito`, then build_runner, and builds with:

```bash
flutter build apk --flavor dev --release --target-platform android-arm64
```

The guard skips absent `pigeons/*.dart`; PR #3 removed that directory. The first
step fetches the pinned Dharma Seed snapshot (SHA-256 checked), and after the
build `catalogue.py verify-apk` confirms the APK carries exactly it. Normal
runner SDK/NDK installation remains enabled: `path_provider_android` uses JNI
and compiles C, so the NDK is required. The JVM is bounded to 4 GiB/two workers.
Unrelated preinstalled tools are removed to provide disk space.

Release is unsigned when `android/keystore.properties` is absent. The tracked
Gradle change only makes the missing keystore optional and selects release
signing when a store file is supplied, matching PR #2's existing behavior.
No throwaway release key, service configuration, private environment file or
phone signing credential is needed. The artifact preparation step removes any
Android debug signature as well, so both supported modes upload unsigned APKs.
Artifact metadata includes the full source SHA, parameters, APK hash and bytes.
The artifact is `meditejo-<flavor>-<mode>-<shortsha>`, retained for **7 days**.
No release is published and no signed APK is uploaded.

## Durable local identity

- Directory: `~/.config/meditejo/signing/` (0700).
- Key: `meditejo.p12` (0600), alias `meditejo`, RSA-4096.
- Password: `password` (0600), passed by file to keytool/apksigner, never printed.
- Certificate SHA-256:
  `07:87:EC:F8:50:D8:DF:93:F9:02:DB:09:A9:8D:C6:1E:9C:E4:0F:E1:39:BF:54:35:A5:35:A6:2E:18:5A:50:31`.

The key must **never change**, and it must leave bjslab only as the encrypted BWS backup. Android requires the same key to
update the installed app; replacing it would require an uninstall and lose
local practice data. The script pins this digest before signing and checks it
again on the signed APK. It refuses missing/partial keys or loose permissions
and never generates a replacement.

**Backup (approved 2026-10-16):** BWS infrastructure project, as secrets
`MEDITEJO_SIGNING_P12_B64` (the PKCS12 key, base64) and `MEDITEJO_SIGNING_PASSWORD`.
To restore on a fresh host, without printing either value:

```bash
umask 077; mkdir -p ~/.config/meditejo/signing && cd ~/.config/meditejo/signing
bjs-bws secret get 7f6bf3b5-d598-47a0-9409-b4e501382952 | python3 -c "import json,sys; sys.stdout.write(json.load(sys.stdin)['value'])" | base64 -d > meditejo.p12
bjs-bws secret get fecd3cc8-1ce1-4256-bc32-b4e5013829a1 | python3 -c "import json,sys; print(json.load(sys.stdin)['value'])" > password
chmod 700 . && chmod 600 meditejo.p12 password
```

Then check that `keytool -list -keystore meditejo.p12 -storepass:file password` shows the pinned digest above.


## Installing on the S23+

The phone's remote-control MCP refuses plain-HTTP downloads and has no uninstall tool. The route used on 2026-10-15:

1. Serve the signed APK from a directory containing only that file. Bind it to bjslab's Tailscale address on a free port, for example `python3 -m http.server 8791 --bind 100.88.219.36`. Expose it tailnet-only over HTTPS with `tailscale serve --bg --https=8792 http://100.88.219.36:8791`.
2. `android_download_from_url` into `builtin:downloads`. Over the relay, 42 MB takes a few minutes. Poll `android_list_files` until the full size appears; don't re-download.
3. Open My Files → Downloads → the APK → Package installer → Update.
   - Play Protect blocks an unknown developer. Use "More details" → "Install anyway", and never "Send for scanning".
   - "Install unknown apps" must be on for My Files. Burooj can switch it off between installs.
4. Tear down: `tailscale serve --https=8792 off`, stop the server, and delete the staging directory.

Updates keep app data only because every build is signed with the same key.

## GitHub verification record (2026-10-15)

- **First phone build:** run [38758895926](https://github.com/beejsbj/meditejo/actions/runs/38758895926), commit `9f7b3055`, 11 min 26 s wall time, 533 s of it Gradle. Produced a 41,875,546-byte arm64 dev/release APK. The certificate pin matched, and the APK was installed on the S23+.
- **Launcher fix:** commit `8bdcf44a`, which merges PR #2's `d7951052` (release and profile manifests no longer strip MAIN/LAUNCHER). `aapt2 dump badging` shows a `launchable-activity`. Installed as an update; the app-drawer icon launches Meditejo.

## Routes tried

- **Daytona** (`cockpit compute run --profile android`): retired.
  - The plugin portal (`plugins.gradle.org`) resets TLS from the sandbox, so the portal-only artifacts were staged over HTTPS from bjslab and resolved.
  - JitPack and JCenter are blocked too, so those repositories were dropped inside the sandbox.
  - The account caps sandboxes at 10 GiB; a 25 GiB request was rejected.
  - Even a lean arm64 debug build of the de-Medito tree peaked at about 10 GiB: Gradle home 5.26, Android SDK with NDK 2.81 (the NDK is 1.98 of that, and is required for `jni`), Flutter 1.13, pub cache 0.42, build outputs 0.36. Gradle then failed with `No space left on device`.
  - Jobs: `meditejo-20261015-111134-26058` through `meditejo-20261015-123057-23399`; the records are under `~/.local/state/daytona-run/`.
- **Build on bjslab:** rejected. The host is memory-bound, with about 4 GB free and swap full.
- **Mac:** not tried. It has no Flutter or Android SDK, and it's Burooj's live machine.
