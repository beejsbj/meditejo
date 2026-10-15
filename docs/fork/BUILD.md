# Android build route

**Status: blocked by Daytona's 10 GiB disk cap, including after pruning.** Both
offline pub steps and the staged plugin-portal workaround passed. Two attempts
reached app configuration but exhausted disk before producing an APK. APK signing,
release/prod builds and phone updates remain unverified. The command below is
the attempted route; continuation evidence is at the end.

Build on Daytona; sign on bjslab. Never run Gradle on bjslab. This baseline is
still Medito branded and must not be installed on the phone. The orchestrator
does the first install after the rename is integrated.

## Prerequisites on bjslab

- Flutter 3.47.2 / Dart 3.13.2 (`~/.local/share/flutter`, already on PATH).
- `cockpit compute` with its existing BWS authentication. See
  `cockpit handbook bjslab/capabilities/daytona` and `cockpit compute doctor`.
- Python 3, Bash, Git, Java/keytool and tar.
- User Android build-tools 36.0.0, already installed at
  `~/.local/share/android-sdk/build-tools/36.0.0`. Only `apksigner` and `zipalign`
  run locally. Override with `MEDITEJO_BUILD_TOOLS` if needed. If absent,
  install only `build-tools;36.0.0` with a user SDK's `sdkmanager`, never a
  system package or a full local Gradle build.
- Resolve and generate locally, one command at a time:

  ```bash
  nice -n 10 flutter pub get
  for f in pigeon_conf.dart pigeons/*.dart; do
    nice -n 10 dart run pigeon --input "$f" --package_name=medito || break
  done
  nice -n 10 dart run build_runner build --delete-conflicting-outputs
  ```

  `--package_name=medito` is needed when Pigeon cannot deduce the package name
  from an output directory that has not yet been created. The Dart package
  name remains `medito` by decision; it is independent of the Android app ID.
  Do this again when dependencies or generated models change.

## One command

```bash
tools/meditejo/build_apk.sh --flavor dev --app-id io.github.beejsbj.meditejo --mock
```

The command also runs `tools/meditejo/fetch_portal.py` on bjslab, using plain
HTTPS to stage the coordinates in `tools/meditejo/portal-artifacts.txt` as a
small Maven repository. It fetches required POMs/JARs and optional module
metadata, follows module artifact filenames and checks their published SHA-256
when available. It never invokes Gradle locally. To inspect this step alone:

```bash
python3 tools/meditejo/fetch_portal.py /tmp/meditejo-portal-maven
```

The sandbox installs `portal.init.gradle` under its private
`GRADLE_USER_HOME/init.d`. Its `beforeSettings` callback adds the staged repo,
Google Maven and Maven Central before the portal. This also runs for Flutter's
included Gradle build and plugins resolved during settings evaluation. Tracked
Gradle files remain unchanged. Add exact missing coordinates to the list when
a Gradle failure establishes that another portal artifact is needed.

Debug is the default; add `--release` for release. Choose `--flavor prod` for
the flavor without the `.dev` application ID suffix. `--app-id` is the base
ID, before that suffix. Defaults can be changed with `MEDITEJO_FLAVOR` and
`MEDITEJO_APP_ID`. The build script supplies the ID through sandbox-only
`keystore.properties`; it does not rename native packages, labels or icons.

Use the same command with `--dry-run` to pack inputs and inspect the printed
Daytona manifest without contacting Daytona or signing anything. The upload
contains selected source plus `pub-packages.tgz` (only resolved pub.dev package
sources and hashes from `${PUB_CACHE:-$HOME/.pub-cache}`, selected through
the app's and Flutter tooling's `.dart_tool/package_config.json`; Git and external path dependencies are
rejected until explicitly supported). It includes ignored generated
Dart files, which a normal Git-based runner upload omits. No host signing key,
password, Firebase configuration or private environment JSON is staged.

The sandbox downloads a checksum-pinned Flutter 3.47.2 archive from Google,
extracts the supplied pub cache, resolves Flutter tooling first with its Dart
binary and `pub get --offline`, runs `flutter pub get --offline`, and installs
API 36, build-tools 36.0.0 and NDK 28.2.13676358. It creates a disposable key
and placeholder Google Services JSON there. These placeholders prove the build;
they provide no working Firebase services.

The Android profile requests 4 CPUs, 8 GiB RAM and 10 GiB disk, with a 3,600
second command limit. Input/output limits
are 1,024/512 MiB. In the sandbox copy only, Gradle uses a 4 GiB heap, at most
two workers, and Kotlin compiles in process. The sandbox script changes the
nested Android Gradle distribution URL to the official GitHub binary release host
because `services.gradle.org` is blocked. The runner's automatic rewrite only
handles root-level Gradle projects. The script preserves the Gradle version
and selects `-bin` instead of `-all` to omit docs/sources. If an all-distribution
checksum is present it stops rather than reuse that checksum for different bytes.

## Signing and outputs

The durable identity is stored only on bjslab:

- `~/.config/meditejo/signing/` — mode 0700.
- `meditejo.p12` — RSA 4096, alias `meditejo`, mode 0600.
- `password` — shared store/key password, mode 0600; never print it.

Every phone install must use this key. Changing it requires uninstalling the
app and losing its local data. Never copy it into the worktree, staging
directory or Daytona. Backing it up to BWS remains Burooj's decision.
The script creates an identity only when both files are absent and refuses
partial state; recover the original key/password instead of replacing either.

Public certificate SHA-256 (verified with `keytool -list -v`; no APK exists
yet for `apksigner verify --print-certs`):

```text
07:87:EC:F8:50:D8:DF:93:F9:02:DB:09:A9:8D:C6:1E:9C:E4:0F:E1:39:BF:54:35:A5:35:A6:2E:18:5A:50:31
```

Collected cloud artifacts and logs stay in
`~/.local/state/daytona-run/<job>/`. The script aligns the APK for 16 KiB pages,
re-signs locally, verifies alignment and certificate, and prints the final path
under `~/.local/share/meditejo/apks/` (override `MEDITEJO_APK_DIR`). It never
installs an APK. Daytona removes each completed sandbox. Use
`cockpit compute status <job>` after interruption, and `collect`/`cancel` as
appropriate before its expiry.

## Verification record (2026-10-15)

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

### Daytona preparation and resource limit

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

### Initial stopping point: Gradle plugin resolution

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

## Plugin portal continuation (2026-10-15)

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

### Final retry: disk exhausted after pruning

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
