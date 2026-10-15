#!/usr/bin/env bash
# Build remotely, then sign locally. This command never installs an APK.
set -euo pipefail
umask 077
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
flavor=${MEDITEJO_FLAVOR:-dev}
app_id=${MEDITEJO_APP_ID:-io.github.beejsbj.meditejo}
mode=debug
mock=false
dry_run=false
while (($#)); do
  case $1 in
    --flavor) flavor=${2:?Missing flavor}; shift 2 ;;
    --app-id) app_id=${2:?Missing app ID}; shift 2 ;;
    --mock) mock=true; shift ;;
    --release) mode=release; shift ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) echo 'build_apk.sh [--flavor dev|prod] [--app-id ID] [--mock] [--release] [--dry-run]'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ $flavor == dev || $flavor == prod ]] || { echo 'Flavor must be dev or prod' >&2; exit 2; }
[[ $app_id =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$ ]] || { echo 'Invalid application ID' >&2; exit 2; }
cache=${PUB_CACHE:-$HOME/.pub-cache}
[[ -d $cache/hosted ]] || { echo 'Run flutter pub get on bjslab first' >&2; exit 1; }
stage=$(mktemp -d /tmp/meditejo-apk.XXXXXXXX)
trap 'rm -rf "$stage"' EXIT
python3 "$root/tools/meditejo/stage_build.py" "$root" "$stage" "$cache"
job="meditejo-$(date -u +%Y%m%d-%H%M%S)-$RANDOM"
compute=(cockpit compute run --cwd "$stage" --profile android --disk 25
  --timeout 3600 --max-input-mb 1024 --max-output-mb 512
  --collect 'outputs/**' --job "$job")
if $dry_run; then compute+=(--dry-run); fi
"${compute[@]}" -- bash daytona_build.sh "$flavor" "$app_id" "$mode" "$mock"
if $dry_run; then exit 0; fi
state=${DAYTONA_RUN_STATE:-$HOME/.local/state/daytona-run}
apk="$state/$job/artifacts/outputs/daytona.apk"
[[ -s $apk ]] || { echo "No APK collected for $job" >&2; exit 1; }
signing="$HOME/.config/meditejo/signing"
mkdir -p "$signing"
chmod 700 "$signing"
# Refuse partial key state: never silently replace an existing signing identity.
if [[ ! -e $signing/meditejo.p12 && ! -e $signing/password ]]; then
  python3 - "$signing/password" <<'PY'
import os, secrets, sys
fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as f:
    f.write(secrets.token_urlsafe(48) + '\n')
PY
  keytool -genkeypair -keystore "$signing/meditejo.p12" -storetype PKCS12 \
    -storepass:file "$signing/password" -keypass:file "$signing/password" \
    -alias meditejo -keyalg RSA -keysize 4096 -validity 36500 \
    -dname 'CN=Meditejo, OU=Personal Android signing'
fi
[[ -s $signing/meditejo.p12 && -s $signing/password ]] || { echo 'Incomplete signing key state; recover the original key/password' >&2; exit 1; }
chmod 600 "$signing/meditejo.p12" "$signing/password"
build_tools=${MEDITEJO_BUILD_TOOLS:-$HOME/.local/share/android-sdk/build-tools/36.0.0}
output_dir=${MEDITEJO_APK_DIR:-$HOME/.local/share/meditejo/apks}
mkdir -p "$output_dir"
output="$output_dir/$job-$flavor-$mode.apk"
"$build_tools/zipalign" -P 16 -f 4 "$apk" "$stage/aligned.apk"
"$build_tools/apksigner" sign --ks "$signing/meditejo.p12" --ks-key-alias meditejo \
  --ks-pass "file:$signing/password" --key-pass "file:$signing/password" \
  --out "$output" "$stage/aligned.apk"
"$build_tools/zipalign" -c -P 16 4 "$output"
"$build_tools/apksigner" verify --print-certs "$output"
printf 'APK: %s\nDaytona job: %s\n' "$output" "$job"
