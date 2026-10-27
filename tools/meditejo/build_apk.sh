#!/usr/bin/env bash
# Build a committed ref on GitHub, then sign only on bjslab. Never installs.
set -euo pipefail
umask 077
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
ref=HEAD
flavor=${MEDITEJO_FLAVOR:-dev}
mode=${MEDITEJO_BUILD_MODE:-release}
name=
while (($#)); do
  case $1 in
    --flavor) flavor=${2:?Missing flavor}; shift 2 ;;
    --mode) mode=${2:?Missing mode}; shift 2 ;;
    --release) mode=release; shift ;;
    --name) name=${2:?Missing output name}; shift 2 ;;
    -h|--help)
      echo 'build_apk.sh [REF] [--flavor dev|prod] [--mode release|debug] [--name PREFIX]'
      echo 'REF must contain the APK workflow. Defaults: HEAD, dev, release.'
      exit 0 ;;
    -*) echo "Unknown argument: $1" >&2; exit 2 ;;
    *) ref=$1; shift ;;
  esac
done
[[ $flavor == dev || $flavor == prod ]] || { echo 'Flavor must be dev or prod' >&2; exit 2; }
[[ $mode == release || $mode == debug ]] || { echo 'Mode must be release or debug' >&2; exit 2; }
name=${name:-meditejo-$flavor-$mode}
[[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo 'Invalid output name' >&2; exit 2; }
for executable in gh git python3 keytool sha256sum; do command -v "$executable" >/dev/null; done
signing="$HOME/.config/meditejo/signing"
[[ -s $signing/meditejo.p12 && -s $signing/password ]] || {
  echo 'Recover the original Meditejo key/password under ~/.config/meditejo/signing; never generate a replacement.' >&2
  exit 1
}
[[ $(stat -c %a "$signing") == 700 && $(stat -c %a "$signing/meditejo.p12") == 600 && $(stat -c %a "$signing/password") == 600 ]] || {
  echo 'Signing directory must be 0700 and key/password files 0600.' >&2; exit 1;
}
expected=0787ecf850d8df93f902db09a98dc61e9ce40fe139bf5435a535a62e185a5031
actual=$(keytool -exportcert -keystore "$signing/meditejo.p12" -alias meditejo \
  -storepass:file "$signing/password" | sha256sum | cut -d ' ' -f 1)
[[ $actual == "$expected" ]] || { echo "Wrong signing identity: $actual" >&2; exit 1; }
build_tools=${MEDITEJO_BUILD_TOOLS:-$HOME/.local/share/android-sdk/build-tools/36.0.0}
[[ -x $build_tools/zipalign && -x $build_tools/apksigner ]] || {
  echo "Install user build-tools 36.0.0 or set MEDITEJO_BUILD_TOOLS; missing: $build_tools" >&2; exit 1;
}
stage=$(mktemp -d /tmp/meditejo-apk.XXXXXXXX)
trap 'rm -rf "$stage"' EXIT
# The CI build fetches the Dharma Seed snapshot that REF's catalogue.json pins
# (a release asset, not a file in git). Check it is there now rather than after
# the run. A ref from before the move still commits the snapshot itself.
if ! git cat-file -e "$ref:assets/dharma_seed/catalogue.sqlite.gz" 2>/dev/null; then
  git show "$ref:assets/dharma_seed/catalogue.json" >"$stage/catalogue.json"
  python3 -I "$root/tools/meditejo/catalogue.py" check --manifest "$stage/catalogue.json"
fi
# The app downloads the rest of the sounds from the pack release that REF's
# sounds.json pins; a build that points at a missing pack must not ship.
# A ref from before the sound pack has no pack to check.
git show "$ref:assets/sounds/sounds.json" >"$stage/sounds.json"
if grep -q '"bundled"' "$stage/sounds.json"; then
  python3 -I "$root/tools/meditejo/sound_pack.py" check --library "$stage/sounds.json"
fi
python3 "$root/tools/meditejo/github_run.py" "$ref" "$flavor" "$mode" "$stage/artifact"
apk="$stage/artifact/unsigned.apk"
if "$build_tools/apksigner" verify "$apk" >/dev/null 2>&1; then
  echo 'Refusing an artifact that already has a valid signature; inspect the workflow.' >&2; exit 1;
fi
sha=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha"])' "$stage/artifact/result.json")
output_dir=${MEDITEJO_APK_DIR:-$HOME/.local/share/meditejo/apk}
mkdir -p "$output_dir"
output="$output_dir/$name-${sha:0:8}.apk"
"$build_tools/zipalign" -P 16 -f 4 "$apk" "$stage/aligned.apk"
"$build_tools/apksigner" sign --ks "$signing/meditejo.p12" --ks-key-alias meditejo \
  --ks-pass "file:$signing/password" \
  --out "$stage/signed.apk" "$stage/aligned.apk" </dev/null
"$build_tools/zipalign" -c -P 16 4 "$stage/signed.apk"
"$build_tools/apksigner" verify --print-certs "$stage/signed.apk" | tee "$stage/certificate.txt"
signed_digest=$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' "$stage/certificate.txt" | tr '[:upper:]' '[:lower:]' | tr -d ':')
[[ $signed_digest == "$expected" ]] || { echo 'Signed APK certificate mismatch' >&2; exit 1; }
mv "$stage/signed.apk" "$output"
cp "$stage/artifact/result.json" "$output.build.json"
cp "$stage/certificate.txt" "$output.certificate.txt"
printf 'APK: %s\nSize: %s bytes\nCertificate SHA-256: %s\n' "$output" "$(stat -c %s "$output")" "$signed_digest"
