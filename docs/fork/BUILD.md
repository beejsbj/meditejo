# Android build route

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

Debug is the default; add `--release` for release. Choose `--flavor prod` for
the flavor without the `.dev` application ID suffix. `--app-id` is the base
ID, before that suffix. Defaults can be changed with `MEDITEJO_FLAVOR` and
`MEDITEJO_APP_ID`. The build script supplies the ID through sandbox-only
`keystore.properties`; it does not rename native packages, labels or icons.

Use the same command with `--dry-run` to pack inputs and inspect the printed
Daytona manifest without contacting Daytona or signing anything. The upload
contains selected source plus `pub-packages.tgz` (only resolved pub.dev package
sources and hashes from `${PUB_CACHE:-$HOME/.pub-cache}`, selected through
`.dart_tool/package_config.json`; Git and external path dependencies are
rejected until explicitly supported). It includes ignored generated
Dart files, which a normal Git-based runner upload omits. No host signing key,
password, Firebase configuration or private environment JSON is staged.

The sandbox downloads a checksum-pinned Flutter 3.47.2 archive from Google,
extracts the supplied pub cache, runs `flutter pub get --offline`, and installs
API 36, build-tools 36.0.0 and NDK 28.2.13676358. It creates a disposable key
and placeholder Google Services JSON there. These placeholders prove the build;
they provide no working Firebase services.

The Android profile requests 4 CPUs, 8 GiB RAM and 10 GiB disk, with a 3,600
second command limit. Input/output limits
are 1,024/512 MiB. In the sandbox copy only, Gradle uses a 4 GiB heap, at most
two workers, and Kotlin compiles in process. The sandbox script changes the
nested Android Gradle distribution URL to the official GitHub release host
because `services.gradle.org` is blocked. The runner's automatic rewrite only
handles root-level Gradle projects. The script preserves the Gradle version.

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

Public certificate SHA-256:

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

Starting commit: `8d527429`. Results and cloud evidence are recorded below
after the build attempt.

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
