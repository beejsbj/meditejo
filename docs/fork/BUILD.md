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
tools/meditejo/build_apk.sh apk/m1-phone --name meditejo-m1
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

It uses `gh run watch --exit-status` and `gh run download`, verifies artifact
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

## GitHub build and signing boundary

`.github/workflows/meditejo-apk.yml` uses ubuntu-latest, Java 17 and
`subosito/flutter-action@v2.12.0` with Flutter 3.47.2, matching existing CI.
It fetches pub.dev dependencies, runs the guarded Pigeon loop with
`--package_name=medito`, then build_runner, and builds with:

```bash
flutter build apk --flavor dev --release --target-platform android-arm64
```

The guard skips absent `pigeons/*.dart`; PR #3 removed that directory. Normal
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

The key must **never leave bjslab or change**: Android requires the same key to
update the installed app; replacing it would require an uninstall and lose
local practice data. The script pins this digest before signing and checks it
again on the signed APK. It refuses missing/partial keys or loose permissions
and never generates a replacement. Backup policy remains Burooj's decision.

## GitHub verification record (2026-10-15)

**Verified:** the one command reused the successful Actions run, downloaded its
artifact, checked its metadata/hash, aligned it, signed it on bjslab and verified
the pinned certificate (exit 0). No key upload, local Gradle or phone operation.

Source: exact PR #2 head `b7c3f8ec2c3f52676fc7da4c0b59cb3df7984e30` (includes
PR #3), merged with build-route commit `50b5d925` on throwaway `apk/m1-phone`.
Integration SHA: `9f7b3055a9d510a386d116f4a55a608dbe055d41`. The integration's
`android/app/build.gradle` and `lib/` are identical to PR #2's head. Keep PR #2's
Gradle version when resolving the initial merge conflict (it already has the
unsigned-signing changes), and retain both workers' decision entries. No PR was
opened for the integration branch.

| Run | Result | Workflow wall | Gradle |
| --- | --- | ---: | ---: |
| [38757148462](https://github.com/beejsbj/meditejo/actions/runs/38757148462) (`7721e19b`) | failed, registrant mismatch below | 621 s (10m21s) | 448.0 s |
| [38758895926](https://github.com/beejsbj/meditejo/actions/runs/38758895926) (`9f7b3055`) | **success**, dev/release | **686 s (11m26s)** | **532.8 s** |

Workflow wall is API `created_at` through `updated_at` at completion, including
queue/setup/upload/cleanup. The successful job itself took 11m22s. Pigeon and
build_runner passed; build_runner wrote 81 outputs in 37 s. The unoptimized
cold runner downloaded the required NDK 28.2, API 31 (a dependency request), and
CMake 3.22.1 normally. End-of-job usage: Flutter including pub cache 3.0 GiB,
Gradle 5.9 GiB, Android SDK 14 GiB, outputs 635 MiB; filesystem **81 GiB free**.
These are final samples, not a continuously measured peak.

Artifact: `meditejo-dev-release-9f7b3055`, unsigned APK **41,524,201 bytes**
(artifact ZIP 41,524,648 bytes), expires 2026-10-22. Public build metadata has
unsigned APK SHA-256 `73c2a2262d11225d94bdc3d67835bb62b432f626859bf9efeac3dbea163fa2b8`.
The workflow confirmed the unsigned APK does not verify as signed before upload.

Signed APK on bjslab:

```text
/home/admin/.local/share/meditejo/apk/meditejo-m1-9f7b3055.apk
41,875,546 bytes (41.9 MB / 39.94 MiB)
APK SHA-256: e5c7814c7fa1795620f87db48cb693ee8e1287cc924ebfd9f94f36b79861706c
```

`aapt2 dump badging` confirms label **Meditejo**, application ID
`io.github.beejsbj.meditejo`, versionCode `302473`, versionName `2610.6.3-dev`,
compile/target SDK 36 and no debuggable flag. Flutter engine/AOT libraries are
arm64 only. Native dependency helpers also contain armeabi-v7a/x86_64 copies
(~214 KB uncompressed in total); `--target-platform android-arm64` does not
filter those transitive AAR/JNI contents. The target phone is arm64.
`zipalign -c -P 16 4` passed (exit 0).

`apksigner verify --print-certs` passed (exit 0):

```text
Signer #1 certificate DN: CN=Meditejo, OU=Personal Android signing
Signer #1 certificate SHA-256 digest: 0787ecf850d8df93f902db09a98dc61e9ce40fe139bf5435a535a62e185a5031
Signer #1 certificate SHA-1 digest: 3560f7ccd14d47414ed43b09ab72dff2e693a978
Signer #1 certificate MD5 digest: 7740557f2d5ec09ccf9fa2fce13b6cc8
```

The first local signing invocation supplied the same single-line password file
for both `--ks-pass` and `--key-pass`. apksigner consumes those as successive
lines and failed with `end of file reached`. Fix: supply only `--ks-pass file:...`;
it reuses that password for the PKCS12 private key. No password or key changed.
The command then reused/downloaded the existing artifact and completed signing.

Unverified: prod/debug variants, workflow_dispatch, automatic bootstrap pushes,
expired-artifact recovery and phone installation/launch/update. This run proves
the dev/release path and reuse of an existing run. Independent review found the
30-day rerun limit; older artifacts now use a fresh uniquely named push ref.
That recovery path is implemented but has not been exercised against expiration.

First run [38757148462](https://github.com/beejsbj/meditejo/actions/runs/38757148462)
used integration SHA `7721e19b` and failed after Gradle ran 448.0 s:

```text
GeneratedPluginRegistrant.java:69: error: package dev.flutter.plugins.integration_test does not exist
Execution failed for task ':app:compileDevReleaseJavaWithJavac'.
BUILD FAILED in 7m 27s
```

Cause/fix: do **not** pass `--no-pub` to `flutter build apk`. Flutter 3.47.2's
`regeneratePlatformSpecificToolingIfApplicable` returns early with that flag;
the initial pub get generates a debug registrant containing integration_test,
while release Gradle correctly excludes dev-only plugins. The normal build
command regenerates the release registrant. No app or dependency change.
At failure: Flutter (including its pub cache) 3.0 GiB, Gradle 5.9 GiB,
Android SDK 14 GiB, outputs 396 MiB; filesystem 82 GiB free.

PR #1's existing CI at route commit `41806a0d` passed in 2m53s:
[38757519645](https://github.com/beejsbj/meditejo/actions/runs/38757519645),
816 tests passed, 1 skipped. After the command fix, checks also passed at
`50b5d925` in 3m08s ([38758898694](https://github.com/beejsbj/meditejo/actions/runs/38758898694)). Analyze: one existing info (16.3 s), tolerated by
that CI's `--no-fatal-infos`. This is the build branch's baseline suite, distinct
from PR #2/#3's 467-test de-Medito suite.

## Routes tried

### Daytona (retired)

Historical commands below describe the attempts, not the current rebuild route.
The Daytona-only staging/build/portal scripts have been removed; their source
remains in Git history (last Daytona-route commit `e866fe89`). The account's
10 GiB per-sandbox cap prevented even the lean de-Medito debug build from
finishing. No Daytona APK was produced.

### Verification record (2026-10-15)

Starting commit: `8d527429`. Results and cloud evidence from the build attempts:

- `flutter pub get`: exit 0; one discontinued package and 144 packages with
  newer versions outside the current constraints. The lockfile did not change.
- `dart run build_runner build --delete-conflicting-outputs`: exit 0, 135
  outputs in 131 seconds. Both Pigeon inputs (`pigeon_conf.dart` and
  `pigeons/watch_presence.dart`) passed with `--package_name=medito`, exit 0.
  No tracked generated files changed, so none needed committing.
- Unchanged tree before codegen: `flutter analyze --no-pub`, exit 1,
  1,197 issues in 17.4 seconds, including missing generated types.
- After codegen: `flutter analyze --no-pub`, exit 1, **one info**, zero errors
  and zero warnings in 23.2 seconds:

  ```text
  info • Use the null-aware marker '?' rather than a null check via an 'if'. Try using '?' • test/services/fourthwall_service_test.dart:130:21 • use_null_aware_elements
  1 issue found. (ran in 23.2s)
  ```

  This is also the unchanged tree's result: the build worker changed no tracked
  Dart/app files, lockfile or Pigeon outputs. The difference from the initial
  run is generated files, not source changes.
- `flutter test --no-pub --concurrency=1 --reporter expanded` on
  `test/utils/duration_extensions_test.dart`, `test/utils/day_boundary_test.dart`,
  `test/services/audio/session_bell_schedule_test.dart` and
  `test/models/timer_session_test.dart`: exit 0, **38 tests passed**. The test
  reporter measured 6 seconds (initial compiler startup took additional time).
  The full suite was not run on this memory-constrained shared host.
- The README Pigeon command initially exited 255:

  ```text
  Exception: Unable to deduce package name, and no package name supplied.
  Add a `dartPackageName` property to your `PigeonOptions` config,
  or add --package_name={name_of_package} to your command line pigeon call.
  ```

- build_runner reports that `--delete-conflicting-outputs` has been removed
  and is ignored. It also warns that SDK language 3.13 exceeds the pinned
  analyzer's 3.11 support; dependency upgrades are outside this build slice.

#### Daytona preparation and resource limit

- Dry-run `meditejo-20261015-110659-5959`: exit 0, 632 files,
  391,004,151 input bytes, 377,359,896 compressed bytes. This preliminary
  manifest used the shared hosted cache and preceded completed codegen.
- First real job `meditejo-20261015-111134-26058`: runner exit 1 before
  sandbox creation, 712 files, 411,077,989 input bytes, 396,809,123 compressed
  bytes. The API rejected the requested 25 GiB:

  ```text
  create sandbox: HTTP 400 (Disk request 25GB exceeds maximum allowed per sandbox (10GB).
  Need higher resource limits per-sandbox? Contact us at support@daytona.io and let us know about your use case.)
  ```

  `doctor` showed a 30 GiB account quota but did not expose the container's
  10 GiB per-sandbox cap. The command now requests 10 GiB. Dependency staging
  was also narrowed to the app's resolved pub.dev packages, avoiding unrelated
  cache contents and future shared-cache growth. Public package sources are
  the only contents allowed in that archive; the signing directory is never
  part of it.
- Supported-size job `meditejo-20261015-111316-28609`: exit 2 after
  94.5 seconds from sandbox create to verified deletion. Input: 184,716,759
  bytes (171,224,072 compressed), 712 files and 226 resolved pub.dev packages.
  Flutter's 1,501 MiB archive downloaded in about 6 seconds and passed its
  SHA-256 check, but extraction failed because the Android profile has no
  `xz` executable:

  ```text
  /tmp/flutter.tar.xz: OK
  tar (child): xz: Cannot exec: No such file or directory
  tar (child): Error is not recoverable: exiting now
  tar: Child returned status 2
  tar: Error is not recoverable: exiting now
  ```

  The sandbox script now uses Python's standard `tarfile`/`lzma` support to
  extract the verified archive; no additional package installation is needed.
- Job `meditejo-20261015-111652-7667`: exit 69 after 339.9 seconds from sandbox
  create to verified deletion. The checksum, Python extraction, API 36,
  build-tools 36.0.0 and NDK installation passed. JitPack was unreachable:

  ```text
  curl: (35) OpenSSL SSL_connect: Connection reset by peer in connection to jitpack.io:443
  ```

  The first Flutter app pub command stopped before Gradle:

  ```text
  Got socket error trying to find package json_annotation at https://pub.dev.
  Failed to update packages.
  ```

  The app-only cache selection omitted Flutter tooling's own graph (the app
  uses `json_annotation` 4.11.0; Flutter tooling requires 4.12.0). Flutter's
  universal-artifact preparation can run tooling pub resolution before
  forwarding the app's `--offline` flag. The upload now includes the union of
  both resolved graphs, and the script runs the SDK's Dart binary to resolve
  Flutter tooling offline before invoking Flutter. This corrects the cache
  selection without allowing unrelated hosted packages or Git dependencies.

#### Initial stopping point: Gradle plugin resolution

Job `meditejo-20261015-112548-15828` ran with 4 CPUs, 8 GiB RAM and 10 GiB
disk. It uploaded 712 files, including 263 resolved pub.dev package versions:
204,655,947 bytes before runner compression, 190,536,380 bytes uploaded.
The sandbox lifecycle (creation through verified deletion) took **159.5
seconds**, including **26.4 seconds** in `assembleDevDebug`. Runner exit: **1**.
This excludes local staging and runner packaging time.

Verified in this sandbox:

- Flutter 3.47.2 archive download, checksum and Python extraction.
- Flutter tooling's direct `dart pub get --offline`: `Got dependencies`.
- API 36, build-tools 36.0.0 and NDK 28.2.13676358 installation.
- App `flutter pub get --offline`: `Got dependencies!`.
- Disposable key and Google Services placeholder generation.
- Gradle invocation with the requested dev/mock/debug flags.

Gradle failed before producing an APK:

```text
* Where:
Build file '/tmp/flutter/packages/flutter_tools/gradle/build.gradle.kts' line: 7

* What went wrong:
Plugin [id: 'org.gradle.kotlin.kotlin-dsl', version: '5.2.0'] was not found in any of the following sources:

- Gradle Core Plugins (plugin is not in 'org.gradle' namespace)
- Included Builds (No included builds contain this plugin)
- Plugin Repositories (could not resolve plugin artifact 'org.gradle.kotlin.kotlin-dsl:org.gradle.kotlin.kotlin-dsl.gradle.plugin:5.2.0')
  Searched in the following repositories:
    Gradle Central Plugin Repository

BUILD FAILED in 26s
```

The log then prints a misleading Java/Gradle incompatibility suggestion:
Flutter parses the GitHub distribution path as a version. The actual Gradle
exception is plugin resolution, not demonstrated Java incompatibility. No
Java or Gradle version was changed in response. The log does not establish
the HTTP failure behind the plugin resolution error; JitPack's independent
connection reset above is verified, but is not proven to cause this error.

All created sandboxes were deleted and no APK was collected. The durable key
and user build-tools are ready; local alignment/signing and certificate
verification against an APK remain unverified. No phone installation, Gradle
execution on bjslab or toolchain installation on the Mac occurred.

At that stopping point, plugin access/cache handoff needed resolution. The
continuation below resolves it and establishes the next blocker. No tracked
Gradle files or app code were changed;
wrapper routing, heap/worker limits and placeholders affect sandbox copies only.

| Job | Lifecycle | Result | APK |
| --- | ---: | --- | --- |
| `meditejo-20261015-111134-26058` | 0.2 s rejection | 25 GiB exceeds 10 GiB limit | none |
| `meditejo-20261015-111316-28609` | 94.5 s | exit 2, missing xz | none |
| `meditejo-20261015-111652-7667` | 339.9 s | exit 69, SDK tooling cache omitted | none |
| `meditejo-20261015-112548-15828` | 159.5 s | exit 1, Gradle Kotlin DSL plugin unresolved | none |

### Plugin portal continuation (2026-10-15)

The cheap probe confirmed host-specific access:

- bjslab `curl -sSI --max-time 20 https://plugins.gradle.org/m2/`: exit 0,
  HTTP 200.
- Daytona job `meditejo-portal-probe-20261015`: probe runner exit 0; the
  portal curl itself exited 35 with `OpenSSL SSL_connect: Connection reset
  by peer`. Maven Central's curl exited 0 with HTTP 200. Sandbox deleted.

The missing marker's POM names the implementation dependency. Initial list:

```text
org.gradle.kotlin.kotlin-dsl:org.gradle.kotlin.kotlin-dsl.gradle.plugin:5.2.0
org.gradle.kotlin:gradle-kotlin-dsl-plugins:5.2.0
```

HTTP fetch on bjslab passed: six files, 77,054 bytes, including marker and
implementation POMs, implementation module metadata/JAR and its published
source/Javadoc variants. Module artifact SHA-256 checks passed. A manifest
inside the staged repository records each file's size and SHA-256.

Build attempt `meditejo-20261015-113808-16333` confirmed the init callback in
both settings instances:

```text
Meditejo staged plugin repository for .../work/app/android
Meditejo staged plugin repository for /tmp/flutter/packages/flutter_tools/gradle
```

Before Gradle, the 10 GiB filesystem used 5.8 GiB with 4.3 GiB available.
Observed directory sizes: Flutter 2.5 GiB, Android SDK/NDK 2.9 GiB, resolved pub
cache 476 MiB and portal repository 100 KiB allocated. Flutter's downloaded
archive and the uploaded pub archive were already deleted after extraction;
no iOS/web precache ran.

The portal workaround passed: Gradle advanced beyond the previous Kotlin DSL
failure and reached the app's Android configuration. No additional portal-only
coordinate was reported. The attempt then failed while resolving `:health`'s
buildscript dependencies because the 10 GiB disk was full:

```text
A problem occurred configuring project ':health'.
> Could not resolve all artifacts for configuration 'classpath'.
  > Could not download protos-31.13.0.jar (com.android.tools.analytics-library:protos:31.13.0)
    > Could not get resource 'https://dl.google.com/dl/android/maven2/com/android/tools/analytics-library/protos/31.13.0/protos-31.13.0.jar'.
      > No space left on device
```

The first Gradle attempt took 379.8 seconds and Flutter's automatic retry took
6.5 seconds. After failure: filesystem 100% full with 68 KiB free; Flutter
2.5 GiB, SDK/NDK 2.9 GiB, pub cache 476 MiB, Gradle home 4.3 GiB and app build
only 24 KiB. Gradle home contained 707 MiB of wrapper distributions, 2.5 GiB
of version-specific caches and 1.1 GiB of downloaded modules. This was a disk
failure, not a missing portal coordinate or proven Java incompatibility.

The helper did not reach a terminal status record after disk exhaustion.
Read-only process inspection found no remaining Java processes. The bundled
pub preload (216 MiB) was removed to recover space for inspection, then the
sandbox was canceled and its deletion verified. Total sandbox lifecycle was
765.7 seconds; no APK/artifact was collected. The local runner exited 2 during
concurrent cleanup, while its retained Gradle log proves the disk failure.

The next attempt pruned the bundled pub preload, Flutter web/profile/opposite
Android-mode caches, SDK development examples/docs/engine source, Dart web/
analysis/DevTools tooling, and SDK 35. It kept all Android ABIs, the selected
debug/release mode and the host compiler tools. Gradle used the same version's
binary distribution. All pruning affected only the disposable sandbox.

#### Final retry: disk exhausted after pruning

Job `meditejo-20261015-115252-22616` uploaded 720 files: 204,736,780 input
bytes / 190,596,061 compressed bytes. The sandbox command and build wrapper
both exited **1**. Gradle took **428.6 seconds**; sandbox creation through
verified deletion took **562.7 seconds** (9 minutes 22.7 seconds).

Pruning reduced pre-Gradle usage from 5.8 GiB to **4.7 GiB**, leaving **5.4
GiB available**. Flutter was 1.4 GiB, Android SDK/NDK 2.7 GiB, pub cache 476
MiB and the portal repository 100 KiB allocated. The binary Gradle wrapper
occupied 277 MiB instead of 707 MiB. Flutter restored six small Android AOT
host-tool directories during its artifact check; its final size was 1.5 GiB.
No iOS/web precache ran, and download archives were deleted after extraction.

The staged repository callback again ran for both Android and Flutter's
included build. App configuration passed the previous plugin-resolution
point. Gradle then exhausted disk while writing its transform caches:

```text
org.gradle.api.UncheckedIOException: Could not add entry '.../gradle-home/caches/8.14.3/transforms/087b6d876711743e64f394c9ad3b1252' to cache file-access.bin (.../gradle-home/caches/journal-1/file-access.bin).
Caused by: java.io.IOException: No space left on device

Failed to notify root build lifecycle listener.
> Could not update .../gradle-home/caches/8.14.3/file-changes/last-build.bin

BUILD FAILED in 7m 8s
```

Final filesystem usage was **100%, with 316 KiB free**: Flutter 1.5 GiB,
Android SDK/NDK 2.7 GiB, pub cache 476 MiB, Gradle home **5.3 GiB**, and app
build only 24 KiB. The artifact collection contained zero files. Runner state
records `exit_code: 1`, `phase: cleaned`, `cleanup_verified: true`.

| Continuation job | Sandbox lifecycle | Result | APK |
| --- | ---: | --- | --- |
| `meditejo-portal-probe-20261015` | 8.5 s | probe completed; portal curl 35, Central HTTP 200 | none |
| `meditejo-20261015-113808-16333` | 765.7 s including inspection/cleanup | portal workaround passed; disk full; canceled | none |
| `meditejo-20261015-115252-22616` | 562.7 s | exit 1; disk full after pruning | none |

Stopped at this second blocker as instructed. The portal mirror is proven;
the complete APK route is not. All sandboxes are deleted. No APK path, size
or APK certificate verification exists, so the PR remains draft. The durable
key is unchanged on bjslab. No Gradle ran on bjslab, and no phone operation
or Mac toolchain installation occurred. The orchestrator needs a capacity
resolution or an explicitly revised route before another build attempt.

Local checks for the continuation: Bash syntax, Python compilation and
`git diff --check` passed. The portal scripts also received a bounded
independent review with no material issues. The original Flutter analysis
and 38-test results above remain the local toolchain evidence; they were not
rerun for script/documentation changes.

### De-Medito arm64 continuation (2026-10-15)

The target changed to `origin/fork/remove-medito-backend` (PR #3), commit
`37548a2543d875e27b8db7364b8ba3d78019999e`, in a detached temporary worktree:

```bash
git fetch origin fork/remove-medito-backend
git worktree add --detach /tmp/meditejo-demeditized-build origin/fork/remove-medito-backend
# Resolve/codegen in that checkout as described above, then from this branch:
tools/meditejo/build_apk.sh --source /tmp/meditejo-demeditized-build \
  --flavor dev --app-id io.github.beejsbj.meditejo
```

This builds PR #3's current native identity/labels with a parameterized base app
ID; it does not integrate rename PR #2 and must not be installed yet. The dev
flavor's final package ID is `io.github.beejsbj.meditejo.dev`. No mock define is
passed, and no Firebase placeholder is needed on this source.

Preparation on bjslab, under `nice -n 10`, sequentially:

- `flutter pub get`: exit 0; no tracked source/lockfile changes.
- `dart run pigeon --input pigeon_conf.dart --package_name=medito`: exit 0.
  PR #3 removed `pigeons/`; the old unguarded wildcard command exited 255 on
  literal `pigeons/*.dart`. The documented loop now skips nonexistent inputs.
- `dart run build_runner build --delete-conflicting-outputs`: exit 0, 81
  outputs in 109 seconds; no tracked generated changes.
- `flutter analyze --no-pub`: exit 0, **no issues**, 12.3 seconds.
- No new Flutter test run; PR #3's worker owns its test evidence. The original
  build worker's 38 tests apply to the earlier source only.
- Dry run `meditejo-20261015-121415-14836`: exit 0, 581 files, 230 resolved
  pub package versions, 194,021,776 input bytes / 181,462,528 compressed bytes.
  Inspected manifest: no key/password, keystore/local properties, Firebase JSON
  or credential files. It includes the source revision and footprint helper.

Remaining plugin inspection established that `path_provider_android 2.3.1`
depends on `jni 1.0.0` and `jni_flutter 1.0.1`. JNI's `externalNativeBuild`
uses `src/CMakeLists.txt` to compile `dartjni.c` and support C files, with NDK
28.2.13676358 and compileSdk 35. Dropping the NDK is therefore invalid.
The sandbox retains API 35 and shared NDK headers/host tools, and prunes other
target sysroot libraries. Flutter artifacts retain the selected arm64 mode and
small host AOT tools. No other platform precache or doctor runs.

A bounded independent review caught that Flutter's `--target-platform` does
not limit JNI's library module. The init script now applies an explicit
`arm64-v8a` ABI filter to Android library modules before their configuration.
The first launch, `meditejo-20261015-121516-21207`, was canceled before Gradle;
its lifecycle was 33.0 seconds and deletion was verified. Its controlling runner exited 2 with HTTP 502 during
upload concurrent with cancellation. It provides no compilation evidence.

#### Arm64 attempt: capacity held through Java compilation; blocked metadata

Job `meditejo-20261015-121643-21037` used the corrected ABI filter and the
source above. Input: 581 files, 194,022,165 bytes / 181,462,820 compressed.
The source revision and footprint JSONL were collected. Exit **1**, Gradle
**631.4 seconds**, sandbox lifecycle **769.8 seconds**, deletion verified.

| Stage | Filesystem used | Available | Flutter | SDK incl. NDK | Gradle | Build |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Flutter extracted; archive deleted | 3.249 GiB | 6.751 GiB | 2.456 GiB | 0.462 GiB | negligible | 0 |
| API 36 + NDK installed | 5.541 GiB | 4.459 GiB | 2.456 GiB | 2.749 GiB | negligible | 0 |
| Pruned, before Gradle | 4.033 GiB | 5.967 GiB | 1.127 GiB | 2.570 GiB | negligible | negligible |
| Largest observed sample | **9.467 GiB** | **0.533 GiB** | **1.130 GiB** | **2.809 GiB** | **4.789 GiB** | **0.294 GiB** |

At that peak, the SDK comprises **1.977 GiB NDK** and **0.833 GiB other SDK
packages**. Pub is another **0.421 GiB**. These allocated-byte measurements use
GiB (2^30 bytes), unlike Flutter's APK display size. Gradle requested API 34
in addition to 35/36; it was installed on demand. No build-tools 36 package
was preinstalled. The distribution archive removal was confirmed in the log.

This attempt did **not** exhaust disk. It reached plugin Java compilation,
then failed because the dynamic AndroidX runner version searches all project
repositories, including blocked JitPack and JCenter:

```text
Execution failed for task ':integration_test:compileDebugJavaWithJavac'.
> Could not resolve all files for configuration ':integration_test:debugCompileClasspath'.
   > Could not resolve androidx.test:runner:1.2+.
      > Failed to list versions for androidx.test:runner.
         > Unable to load Maven meta-data from https://jitpack.io/androidx/test/runner/maven-metadata.xml.
            > Connection reset
         > Unable to load Maven meta-data from https://jcenter.bintray.com/androidx/test/runner/maven-metadata.xml.
            > Connection reset
```

The init script now omits those two blocked project repository hosts after
project configuration. Google Maven/Maven Central remain; no version is
pinned or changed, and tracked Gradle files remain unchanged. Artifact handoff
uses `mv` to avoid another APK copy in the constrained sandbox.

#### Final arm64 retry: disk exhausted

Job `meditejo-20261015-123057-23399` used the same PR #3 source without mock
mode. Input: 581 files, 194,022,810 bytes / 181,463,232 compressed bytes.
Both the sandbox command and wrapper exited **1**. Gradle took **580.6
seconds**; creation through verified deletion took **717.5 seconds** (11 minutes
57.5 seconds). The source revision and footprint JSONL were collected; no APK
was produced. `phase: cleaned`, `cleanup_verified: true`.

The log confirms JitPack/JCenter removal, including `:integration_test`.
Resolution advanced beyond the prior AndroidX runner metadata error. The
failure was disk space during Gradle transforms and compilation:

```text
java.io.IOException: No space left on device

Failed to notify root build lifecycle listener.
> Could not update .../gradle-home/caches/8.14.3/file-changes/last-build.bin

BUILD FAILED in 9m 40s
```

Flutter again emitted a Java/Gradle incompatibility suggestion because it
misparsed the routed GitHub distribution URL. The explicit exception above
establishes disk exhaustion; it does not establish Java incompatibility.

Largest observed sample, at exit:

| Component | Allocated bytes | GiB |
| --- | ---: | ---: |
| Filesystem used | 10,736,771,072 | 9.999 |
| Filesystem available | **647,168** | 0.0006 |
| Flutter SDK | 1,212,907,520 | 1.130 |
| Gradle home, including dependency/transform caches | **5,643,100,160** | **5.256** |
| Android SDK including NDK | 3,016,290,304 | 2.809 |
| ↳ NDK (already included above) | 2,122,350,592 | 1.977 |
| ↳ Other SDK packages | 893,939,712 | 0.833 |
| App/plugin build outputs | 385,626,112 | 0.359 |
| Resolved pub cache | 452,042,752 | 0.421 |

Applied levers: arm64 app and native-library filters, debug mode, Android-only
precache, unused Flutter/NDK target files pruned, download archives deleted,
Gradle build cache off, explicit `--no-daemon`, binary wrapper with its ZIP
deleted after extraction, and SDK/build-tools packages installed only when
required. NDK removal is ruled out by JNI's CMake source inspection. Native
JNI compilation and APK packaging were not proven before failure. CMake was
not explicitly preinstalled. Dependency/transform caches still grew even with
Gradle's task build cache disabled.

Retained evidence on bjslab:

```text
~/.local/state/daytona-run/meditejo-20261015-123057-23399/output.log
~/.local/state/daytona-run/meditejo-20261015-123057-23399/artifacts/outputs/footprint.jsonl
~/.local/state/daytona-run/meditejo-20261015-123057-23399/artifacts/outputs/source-revision.txt
```

Stopped as requested; no further build or alternative runner was set up. All
three sandboxes from this continuation are deleted. The durable signing key
remains on bjslab, unchanged; there is no APK path/size or APK certificate
verification, and PR #1 stays draft. The orchestrator/Burooj own the alternative
route decision. There was no local Gradle build, phone operation or Mac setup.

Final local checks: Bash syntax, Python compilation and `git diff --check`
passed. The ABI filter correction received independent static review. No
tracked Gradle files, app code, app identity, lockfile or generated outputs
were changed by this worker.
