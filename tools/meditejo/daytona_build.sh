#!/usr/bin/env bash
# Runs only in a disposable Daytona sandbox. No durable credentials here.
set -euo pipefail
flavor=$1
app_id=$2
mode=$3
mock=$4
export PUB_CACHE="$PWD/pub-cache"
export FLUTTER_SUPPRESS_ANALYTICS=true
mkdir -p "$PUB_CACHE" outputs
tar -xzf pub-packages.tgz -C "$PUB_CACHE"
rm pub-packages.tgz
curl --fail --location --retry 3 https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.2-stable.tar.xz -o /tmp/flutter.tar.xz
echo '447878859d01ca9bfdb99a85f245af07ed8a15fedcd9d189c4749e8e92d1f185  /tmp/flutter.tar.xz' | sha256sum -c -
# The Android profile has Python but no xz executable.
python3 - <<'PY'
import tarfile
with tarfile.open('/tmp/flutter.tar.xz', 'r:xz') as archive:
    archive.extractall('/tmp')
PY
rm /tmp/flutter.tar.xz
export PATH="/tmp/flutter/bin:$PATH"
git config --global --add safe.directory /tmp/flutter
# Flutter's universal-artifact check can resolve its own tools before it
# forwards --offline to app pub get. Populate that graph using Dart directly.
/tmp/flutter/bin/cache/dart-sdk/bin/dart pub get --offline --directory /tmp/flutter/packages/flutter_tools
flutter config --no-analytics
sdkmanager 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358'
# Report reachability without making an unused Maven repository fatal.
curl -I --max-time 20 https://jitpack.io 2>&1 || true
cd app
# The runner rewrites only root-level Gradle projects. Flutter nests Android.
python3 - <<'PY'
from pathlib import Path
import re
p = Path('android/gradle/wrapper/gradle-wrapper.properties')
value = p.read_text()
value, count = re.subn(
    r'https(\\?:)//(?:services|downloads)\.gradle\.org/distributions/gradle-([0-9.]+)-(bin|all)\.zip',
    lambda m: f'https{m[1]}//github.com/gradle/gradle-distributions/releases/download/v{m[2]}/gradle-{m[2]}-{m[3]}.zip',
    value,
)
p.write_text(value)
print(f'Routed {count} nested Gradle wrapper URL(s) to the official GitHub release')
PY
flutter pub get --offline
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
kotlin.compiler.execution.strategy=in-process
EOF
args=(build apk --no-pub --flavor "$flavor" "--$mode")
if [[ $mock == true ]]; then args+=(--dart-define=MOCK_MODE=true); fi
flutter "${args[@]}"
cp "build/app/outputs/flutter-apk/app-$flavor-$mode.apk" ../outputs/daytona.apk
du -h ../outputs/daytona.apk
