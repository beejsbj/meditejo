#!/usr/bin/env bash
# Runs only in a disposable Daytona sandbox. No durable credentials here.
set -euo pipefail
flavor=$1
app_id=$2
mode=$3
work=$PWD
export PUB_CACHE="$PWD/pub-cache"
export FLUTTER_SUPPRESS_ANALYTICS=true
export GRADLE_USER_HOME="$PWD/gradle-home"
export MEDITEJO_PORTAL_REPO="$PWD/portal-maven"
mkdir -p "$GRADLE_USER_HOME/init.d"
cp portal.init.gradle "$GRADLE_USER_HOME/init.d/meditejo-portal.gradle"
mkdir -p "$PUB_CACHE" outputs
cp source-revision.txt outputs/source-revision.txt
measure() { python3 "$work/footprint.py" "$1"; }
trap 'measure final || true' EXIT
measure uploaded
tar -xzf pub-packages.tgz -C "$PUB_CACHE"
rm pub-packages.tgz
measure pub-extracted
curl --fail --location --retry 3 https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.2-stable.tar.xz -o /tmp/flutter.tar.xz
echo '447878859d01ca9bfdb99a85f245af07ed8a15fedcd9d189c4749e8e92d1f185  /tmp/flutter.tar.xz' | sha256sum -c -
measure flutter-downloaded
# The Android profile has Python but no xz executable.
python3 - <<'PY'
import tarfile
with tarfile.open('/tmp/flutter.tar.xz', 'r:xz') as archive:
    archive.extractall('/tmp')
PY
rm /tmp/flutter.tar.xz
measure flutter-extracted
export PATH="/tmp/flutter/bin:$PATH"
git config --global --add safe.directory /tmp/flutter
# Flutter's universal-artifact check can resolve its own tools before it
# forwards --offline to app pub get. Populate that graph using Dart directly.
/tmp/flutter/bin/cache/dart-sdk/bin/dart pub get --offline --directory /tmp/flutter/packages/flutter_tools
flutter config --no-analytics
flutter precache --android --no-ios --no-web --no-linux --no-windows --no-macos --no-fuchsia
measure android-precached
# AGP installs its requested build-tools/CMake versions on demand. JNI (through
# path_provider_android) compiles C, so the pinned NDK really is required.
sdkmanager 'platforms;android-36' 'ndk;28.2.13676358'
measure sdk-installed
du -h --max-depth=2 "$ANDROID_HOME/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64" | sort -h | tail -12
# The account hard-caps disk at 10 GiB. Keep only APK tooling for this mode;
# retain arm64 and the host tools used by Flutter's compiler.
export MEDITEJO_BUILD_MODE="$mode"
python3 - <<'PY'
import os
from pathlib import Path
import shutil
flutter = Path('/tmp/flutter')
cache = flutter / 'bin/cache'
engine = cache / 'artifacts/engine'
paths = [flutter / '.pub-preload-cache', cache / 'flutter_web_sdk',
         flutter / 'dev', flutter / 'examples', flutter / 'docs', flutter / 'engine',
         cache / 'dart-sdk/bin/resources/devtools',
         ]
# JNI compiles against API 35, so that platform is not orphaned. Keep the
# profile's build-tools until AGP establishes which version it uses.
paths.extend(engine.glob('linux-*-release'))
selected = 'android-arm64' + ('' if os.environ['MEDITEJO_BUILD_MODE'] == 'debug' else '-release')
for directory in engine.glob('android-*'):
    if directory.name != selected:
        # Keep the small host AOT tools and cache directories Flutter checks.
        paths.extend(p for p in directory.iterdir() if p.name != 'linux-x64')
# Only aarch64 native code is compiled. Other target sysroot libraries are
# unused; keep host compiler executables and shared headers intact.
sysroot = Path(os.environ['ANDROID_HOME']) / 'ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib'
paths.extend(p for p in sysroot.iterdir() if p.name != 'aarch64-linux-android')
for pattern in ('analysis_server*', 'dartdevc*', 'dart2js*', 'dart2wasm*'):
    paths.extend((cache / 'dart-sdk/bin/snapshots').glob(pattern))
for path in paths:
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()
print('Pruned unused Flutter modes/ABIs/web/development files and non-arm64 NDK sysroot libraries')
PY
measure pruned
# Report reachability without making an unused Maven repository fatal.
curl -I --max-time 20 https://jitpack.io 2>&1 || true
cd app
# The runner rewrites only root-level Gradle projects. Flutter nests Android.
python3 - <<'PY'
from pathlib import Path
import re
p = Path('android/gradle/wrapper/gradle-wrapper.properties')
value = p.read_text()
if 'distributionSha256Sum' in value and '-all.zip' in value:
    raise SystemExit('Binary Gradle distribution needs its own checksum; update the sandbox routing policy')
value, count = re.subn(
    r'https(\\?:)//(?:services|downloads)\.gradle\.org/distributions/gradle-([0-9.]+)-(bin|all)\.zip',
    lambda m: f'https{m[1]}//github.com/gradle/gradle-distributions/releases/download/v{m[2]}/gradle-{m[2]}-bin.zip',
    value,
)
p.write_text(value)
print(f'Routed {count} nested Gradle wrapper URL(s) to the official GitHub binary release (no docs/sources)')
PY
flutter pub get --offline
measure app-resolved
keytool -genkeypair -keystore /tmp/disposable.p12 -storetype PKCS12 \
  -storepass disposable -keypass disposable -alias disposable \
  -keyalg RSA -keysize 2048 -validity 2 -dname 'CN=Disposable Daytona build'
cat > android/keystore.properties <<EOF
appId=$app_id
storeFile=/tmp/disposable.p12
storePassword=disposable
keyAlias=disposable
keyPassword=disposable
EOF
export MEDITEJO_SANDBOX_APP_ID="$app_id" MEDITEJO_SANDBOX_FLAVOR="$flavor"
python3 - <<'PY'
import json, os
from pathlib import Path
# Older checkouts need this placeholder; de-Medito does not apply the plugin.
if not any('com.google.gms.google-services' in p.read_text() for p in Path('android').glob('**/*.gradle')):
    raise SystemExit(0)
package = os.environ['MEDITEJO_SANDBOX_APP_ID']
if os.environ['MEDITEJO_SANDBOX_FLAVOR'] == 'dev':
    package += '.dev'
data = {
    'project_info': {'project_number': '123456789012', 'project_id': 'meditejo-placeholder', 'storage_bucket': 'meditejo-placeholder.invalid'},
    'client': [{'client_info': {'mobilesdk_app_id': '1:123456789012:android:0000000000000000000000', 'android_client_info': {'package_name': package}},
                'api_key': [{'current_key': 'placeholder-not-a-real-key'}]}],
    'configuration_version': '1',
}
with open('android/app/google-services.json', 'w') as f:
    json.dump(data, f)
PY
# Bound Gradle and Kotlin to the sandbox's 8 GiB allocation.
cat >> android/gradle.properties <<'EOF'

org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g
org.gradle.workers.max=2
org.gradle.parallel=false
org.gradle.daemon=false
org.gradle.caching=false
kotlin.compiler.execution.strategy=in-process
EOF
args=(build apk --no-pub --flavor "$flavor" "--$mode" --target-platform android-arm64 --no-android-gradle-daemon)
measure pre-gradle
set +e
flutter "${args[@]}" &
build_pid=$!
python3 "$work/footprint.py" --watch "$build_pid" &
monitor_pid=$!
wait "$build_pid"
build_status=$?
kill "$monitor_pid" 2>/dev/null
wait "$monitor_pid" 2>/dev/null
set -e
measure post-gradle
if ((build_status)); then exit "$build_status"; fi
mv "build/app/outputs/flutter-apk/app-$flavor-$mode.apk" ../outputs/daytona.apk
du -h ../outputs/daytona.apk
