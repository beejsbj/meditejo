#!/usr/bin/env bash
# Publish a Meditejo release on GitHub: bump the version through a pull request,
# build and sign the merged commit on bjslab, and attach the APK to a release the
# app's updater can find. See docs/fork/UPDATES.md. Publishing is the last step;
# --dry-run prints every command and changes nothing.
set -euo pipefail
umask 077
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"

# The whole script is one brace group, so bash has read all of it before the
# first command runs: the run switches branches, which may rewrite this file.
{

repo=beejsbj/meditejo
base=develop # releases are built from, and bump PRs merge into, this branch
flavor=prod
# SHA-256 of the durable signing certificate (docs/fork/BUILD.md); the same
# digest build_apk.sh pins and the app's Kotlin side checks.
pinned=0787ecf850d8df93f902db09a98dc61e9ce40fe139bf5435a535a62e185a5031
min_code=302473 # Medito's last build; every Meditejo code must exceed it.

usage() {
  cat <<'EOF'
release.sh <version> [--notes FILE] [--dry-run] [--yes] [--allow-branch]
           [--refresh-catalogue] [--skip-snapshot]

  <version>      MAJOR.MINOR.PATCH, e.g. 0.1.0. The tag is v<version>.
  --notes FILE   Release notes (Markdown). Default: commit subjects since the
                 previous release.
  --dry-run      Print the plan and every command; change nothing.
  --yes          Publish without the confirmation prompt.
  --allow-branch Start from a branch other than develop. Refused unless every
                 commit on it is already on origin/develop, since the bump PR
                 merges whatever the branch holds. The build is of the merged
                 commit on develop.
  --refresh-catalogue
                 Refresh the bundled Dharma Seed catalogue even though the
                 pinned snapshot is under 30 days old.
  --skip-snapshot
                 Never refresh the catalogue; the release carries whatever
                 snapshot catalogue.json already pins.

versionCode is chosen automatically as YYMMDDnn (build date plus a counter for
the day) and is always above the highest code already released.

Nothing is pushed to develop directly. The version bump (and a catalogue
refresh, when one is due) is committed on release/v<version>, opened as a pull
request against develop, and merged with a merge commit once the required checks
pass (review-evidence). The APK is built and signed from that merged commit, and
the release is tagged on it. If a run fails after the merge, run it again with
the same version: develop already carries the bump, so the script skips the PR
and builds from develop.

Before the version bump the release refreshes the Dharma Seed catalogue shipped
inside the app (assets/dharma_seed), but only when the pinned snapshot is
more than 30 days old (its asOf date in catalogue.json) or --refresh-catalogue
is given. The snapshot is not in git: it is an asset on a catalogue-YYYYMMDD
prerelease, which catalogue.json pins by SHA-256 and the CI build fetches. A
refresh fetches the pinned snapshot, takes a delta from it (a few requests),
and only when Dharma Seed changed something uploads the result as a new
prerelease and commits the manifest alone (tools/meditejo/catalogue.py). The
app catches up on its own with a delta sync when Search or Explore opens.
EOF
}

version=
notes_file=
dry=0
yes=0
allow_branch=0
skip_snapshot=0
force_snapshot=0
snapshot_max_days=30
while (($#)); do
  case $1 in
    --notes) notes_file=${2:?Missing notes file}; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --yes) yes=1; shift ;;
    --allow-branch) allow_branch=1; shift ;;
    --refresh-catalogue) force_snapshot=1; shift ;;
    --skip-snapshot) skip_snapshot=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    *) [[ -z $version ]] || { echo 'Only one version, please.' >&2; exit 2; }
       version=$1; shift ;;
  esac
done
[[ -n $version ]] || { usage >&2; exit 2; }
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Version must look like 0.1.0 (got: $version)" >&2; exit 2; }
((! (skip_snapshot && force_snapshot))) || {
  echo '--skip-snapshot and --refresh-catalogue contradict each other.' >&2; exit 2; }
tag=v$version
release_branch=release/$tag
checks_timeout=${MEDITEJO_RELEASE_CHECKS_TIMEOUT:-1800} # seconds to wait for the required checks
checks_interval=${MEDITEJO_RELEASE_CHECKS_INTERVAL:-15} # seconds between looks at them

problems=0
problem() {
  problems=$((problems + 1))
  if ((dry)); then echo "WOULD REFUSE: $*" >&2; else echo "Refusing: $*" >&2; exit 1; fi
}
run() {
  if ((dry)); then printf '+'; printf ' %q' "$@"; printf '\n'; else "$@"; fi
}
step() { printf '\n== %s\n' "$*"; }

stage=$(mktemp -d /tmp/meditejo-release.XXXXXXXX)
trap 'rm -rf "$stage"' EXIT

# ---------------------------------------------------------------- preflight
step "Preflight ($([[ $dry == 1 ]] && echo dry run || echo live))"
for tool in git gh python3 sha256sum; do
  command -v "$tool" >/dev/null || problem "$tool is not installed"
done
origin_url=$(git config --get remote.origin.url 2>/dev/null || true)
[[ $origin_url == "https://github.com/$repo.git" || $origin_url == "git@github.com:$repo.git" ]] ||
  problem "origin is not $repo"
branch=$(git symbolic-ref --short -q HEAD || true)
[[ -n $branch ]] || problem 'HEAD is detached'
if [[ $branch != "$base" ]] && ((! allow_branch)); then
  problem "on branch '$branch', not $base (use --allow-branch to release from it)"
fi
[[ -z $(git status --porcelain) ]] || problem 'the working tree is not clean'
# The build takes minutes: refuse early unless this commit is exactly what
# origin has, so the bump PR is based on what is reviewed and merged.
if git fetch --quiet origin "$branch" 2>/dev/null; then
  [[ $(git rev-parse HEAD) == "$(git rev-parse FETCH_HEAD)" ]] ||
    problem "local $branch differs from origin/$branch (pull or push first)"
else
  problem "could not fetch origin/$branch"
fi
# The bump PR is cut from this commit and merged into develop, and the only
# required check passes on a PR with no review threads. So a branch other than
# develop may only be released once everything on it is already on origin/develop.
if [[ $branch != "$base" ]]; then
  if git fetch --quiet origin "$base" 2>/dev/null; then
    git merge-base --is-ancestor HEAD FETCH_HEAD ||
      problem "'$branch' has commits that are not on origin/$base; merge them through their own PR first"
  else
    problem "could not fetch origin/$base"
  fi
fi
[[ -z $notes_file || -s $notes_file ]] || problem "notes file '$notes_file' is missing or empty"
# Decide whether this release refreshes the bundled catalogue: only when the
# pinned snapshot is older than 30 days (by its asOf date, which travels with
# the commit; file times do not) or when forced. A missing or unreadable
# manifest counts as stale. MEDITEJO_SNAPSHOT_NOW (ISO date) fakes "now" for tests.
snapshot_dir=assets/dharma_seed
refresh_snapshot=0
snapshot_why=
if ((skip_snapshot)); then
  snapshot_why='skipped (--skip-snapshot): the release carries the pinned snapshot'
elif ((force_snapshot)); then
  refresh_snapshot=1
  snapshot_why='forced (--refresh-catalogue)'
else
  if age=$(python3 -I - "$snapshot_dir/catalogue.json" "$snapshot_max_days" "${MEDITEJO_SNAPSHOT_NOW:-}" <<'PY'
import datetime as dt, json, sys
path, limit, now = sys.argv[1], int(sys.argv[2]), sys.argv[3]
now = dt.datetime.fromisoformat(now.replace("Z", "+00:00")) if now else dt.datetime.now(dt.timezone.utc)
if now.tzinfo is None:
    now = now.replace(tzinfo=dt.timezone.utc)
try:
    as_of = dt.datetime.fromisoformat(json.load(open(path))["asOf"].replace("Z", "+00:00"))
except (OSError, KeyError, ValueError):
    print("unreadable"); sys.exit(0)
days = (now - as_of).days
print(f"{days} {'stale' if days > limit else 'fresh'}")
PY
  ); then :; else age=unreadable; fi
  case $age in
    unreadable) refresh_snapshot=1; snapshot_why='no readable snapshot manifest' ;;
    *stale) refresh_snapshot=1; snapshot_why="pinned snapshot is ${age% *} days old (limit $snapshot_max_days)" ;;
    *) snapshot_why="skipped: pinned snapshot is ${age% *} days old (limit $snapshot_max_days); --refresh-catalogue forces it" ;;
  esac
fi

if ((refresh_snapshot)); then
  command -v flutter >/dev/null || problem 'flutter is not installed (needed to refresh the Dharma Seed snapshot; --skip-snapshot to bypass)'
  [[ -f lib/services/dharma_seed/dharma_seed_database.g.dart ]] ||
    problem 'generated code is missing; run the codegen loop in docs/fork/BUILD.md (or --skip-snapshot)'
  [[ -f $snapshot_dir/catalogue.json ]] ||
    echo 'note: no snapshot is pinned yet; the refresh will be a full sync (about six minutes)'
fi
echo "catalogue snapshot: $snapshot_why"
# The build on GitHub fetches the snapshot the manifest pins; a missing asset
# would fail it after minutes, so check now (a HEAD request, read-only).
python3 -I tools/meditejo/catalogue.py check ||
  problem 'the pinned Dharma Seed catalogue is not downloadable (tools/meditejo/catalogue.py check)'

echo "branch: ${branch:-?}   commit: $(git rev-parse --short HEAD)   tag: $tag"

online=1
if ! gh auth status >/dev/null 2>&1; then
  online=0
  if ((dry)); then echo 'note: gh is not authenticated; remote checks skipped'
  else problem 'gh is not authenticated (gh auth login)'; fi
fi

# Latest published versionCode, read from the release manifest the app reads.
remote_code=0
remote_tag=
if ((online)); then
  if out=$(gh api "repos/$repo/releases/latest" --jq .tag_name 2>&1); then
    remote_tag=$out
    if manifest=$(gh release download "$remote_tag" --repo "$repo" \
        --pattern meditejo-release.json --output - 2>/dev/null); then
      remote_code=$(python3 -I -c 'import json,sys; print(int(json.load(sys.stdin)["versionCode"]))' <<<"$manifest") ||
        problem "release $remote_tag has an unreadable manifest"
    else
      problem "release $remote_tag has no meditejo-release.json"
    fi
    echo "latest published: $remote_tag (versionCode $remote_code)"
  elif [[ $out == *"Not Found"* || $out == *"404"* ]]; then
    echo 'latest published: none yet'
  else
    if ((dry)); then echo "note: could not read the latest release ($out); assuming none"
    else problem "could not read the latest release: $out"; fi
  fi
  if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1 ||
     gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
    problem "$tag already exists on GitHub"
  fi
fi
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && problem "$tag already exists locally"

# ------------------------------------------------------------- versionCode
step 'Version'
current=$(sed -n 's/^version: [^+]*+\([0-9][0-9]*\)$/\1/p' pubspec.yaml)
current_name=$(sed -n 's/^version: \([^+]*\)+[0-9][0-9]*$/\1/p' pubspec.yaml)
[[ -n $current ]] || problem 'pubspec.yaml has no version: name+code line'
today=${MEDITEJO_RELEASE_DATE:-$(date +%y%m%d)}
[[ $today =~ ^[0-9]{6}$ ]] || problem "bad MEDITEJO_RELEASE_DATE '$today'"
floor=$((10#$today * 100 + 1))
highest=$current
((remote_code > highest)) && highest=$remote_code
if ((highest >= floor)); then code=$((highest + 1)); else code=$floor; fi
# A run that merged its bump and then failed leaves develop already at this
# version with a code nobody has published: build that, with no second bump.
resumed=0
if [[ $current_name == "$version" ]] && ((current > remote_code)); then
  resumed=1
  code=$current
fi
((code % 100 != 0)) || problem "more than 99 releases dated $today; wait for tomorrow"
((code > min_code && code < 2147483647)) || problem "versionCode $code is out of range"
echo "versionName $version   versionCode $code   (pubspec had $current, GitHub $remote_code)"
if ((resumed)); then
  echo "resuming: $base already carries $version+$code from an earlier run; no bump or PR, build from $base"
elif ((online)); then
  if git ls-remote --exit-code --heads origin "refs/heads/$release_branch" >/dev/null 2>&1; then
    problem "$release_branch already exists on origin (an open release PR? merge or close it and delete the branch)"
  fi
fi
git rev-parse -q --verify "refs/heads/$release_branch" >/dev/null &&
  ((! resumed)) && problem "$release_branch already exists locally (delete it first)"
if ((resumed)) && [[ $branch != "$base" ]]; then
  problem "resuming needs $base checked out (on '$branch')"
fi

# ------------------------------------------------------------------- notes
notes="$stage/notes.md"
if [[ -n $notes_file ]]; then
  cp "$notes_file" "$notes"
else
  prev=$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || true)
  {
    echo "Meditejo $version"
    echo
    if [[ -n $prev ]]; then
      git log --no-merges --pretty='- %s' "$prev..HEAD" | head -40
    else
      echo '- First published build.'
    fi
  } >"$notes"
fi

# --------------------------------------------------------------------- plan
if ((! dry)); then
  echo
  if ((resumed)); then
    echo "About to build $tag (versionCode $code) from $(git rev-parse --short HEAD) and publish the release."
  else
    echo "About to open a PR from $release_branch into $base, merge it, build $tag (versionCode $code) from the merged commit and publish the release."
  fi
  if ((! yes)); then
    [[ -t 0 ]] || { echo 'Not a terminal; pass --yes to publish.' >&2; exit 1; }
    read -r -p 'Publish? [y/N] ' answer
    [[ $answer == y || $answer == Y ]] || { echo 'Cancelled.'; exit 1; }
  fi
fi

# ------------------------------------------------------------ release branch
# Every commit this run makes goes on this branch and reaches develop only by
# the pull request below.
step 'Release branch'
if ((resumed)); then
  echo "skipped: $base already has the bump"
else
  run git switch -q -c "$release_branch"
fi

# ----------------------------------------------------------------- catalogue
# The Dharma Seed catalogue ships inside the app (docs/fork/ARCHITECTURE.md) but
# not in git: catalogue.json pins a snapshot that lives as an asset on a
# catalogue-YYYYMMDD prerelease, and the CI build fetches it by hash. A release
# refreshes it only when the pinned one is over 30 days old or on request; the
# app's own delta sync covers the gap. The tool starts from the pinned snapshot
# and asks Dharma Seed only for what changed (a few requests, politely paced);
# it leaves the files alone when nothing did. Catalogue text only. A changed
# snapshot is uploaded first and the manifest committed second, so a commit
# never pins an asset that is not there.
step 'Refresh the bundled Dharma Seed catalogue'
if ((resumed)); then
  echo "skipped: resuming a release whose bump is already merged"
elif ((! refresh_snapshot)); then
  echo "$snapshot_why"
else
  run python3 -I tools/meditejo/catalogue.py fetch
  run timeout 2400 nice -n 10 flutter test tools/meditejo/dharma_seed_snapshot.dart
  if ((dry)); then
    echo "+ python3 -I tools/meditejo/catalogue.py publish   # only if the snapshot changed"
    echo "+ git add $snapshot_dir/catalogue.json && git commit   # the manifest alone"
  elif [[ -n $(git status --porcelain -- "$snapshot_dir") ]]; then
    python3 -I tools/meditejo/catalogue.py publish
    git add -- "$snapshot_dir/catalogue.json"
    release_tag=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["asset"]["release"])' "$snapshot_dir/catalogue.json")
    git commit -q -m 'chore(release): refresh the bundled Dharma Seed catalogue' \
      -m "Catalogue text only, built by tools/meditejo/dharma_seed_snapshot.dart and uploaded as the $release_tag prerelease; the manifest pins it."
    python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1])); print("pinned %s: %d talks as of %s" % (m["asset"]["release"], m["counts"]["talks"], m["asOf"]))' \
      "$snapshot_dir/catalogue.json"
  else
    echo 'unchanged: Dharma Seed has nothing new since the pinned snapshot'
  fi
fi

# --------------------------------------------------------------------- bump
step 'Bump version'
if ((resumed)); then
  echo "skipped: $base is already at $version+$code"
else
  run sed -i "s/^version: .*/version: $version+$code/" pubspec.yaml
  run git add pubspec.yaml
  run git commit -q -m "release: Meditejo $version ($code)"
fi

# ------------------------------------------------------------- pull request
# develop requires the review-evidence check, so the bump goes through a PR
# like any other change; the script waits for the required checks and merges
# with a merge commit (the history's usual shape). It never uses --admin, so a
# red check stops the release with the PR left open.
step "Pull request into $base, required checks, merge"
if ((resumed)); then
  echo 'skipped: nothing to merge'
  sha=$(git rev-parse HEAD)
elif ((dry)); then
  echo "+ git push --set-upstream origin $release_branch"
  echo "+ gh pr create --repo $repo --base $base --head $release_branch --title 'release: Meditejo $version ($code)' --body-file <notes>"
  echo "+ gh pr checks <pr> --repo $repo --required   # poll until every required check passes; refuse on a failure or after ${checks_timeout}s"
  echo "+ gh pr merge <pr> --repo $repo --merge --match-head-commit <bump commit>"
  echo "+ git fetch origin $base && git switch $base && git merge --ff-only <merged commit>"
  echo "+ git branch -d $release_branch && git push origin --delete $release_branch"
  sha='<merged commit>'
else
  bump=$(git rev-parse HEAD)
  git push --set-upstream origin "$release_branch"
  {
    echo "Release Meditejo $version (versionCode $code)."
    echo
    echo 'Opened by tools/meditejo/release.sh. The app is built and signed from the merge commit of this PR, so the tag and the APK match what develop holds.'
    echo
    echo '## Notes'
    echo
    cat "$notes"
  } >"$stage/pr-body.md"
  pr_url=$(gh pr create --repo "$repo" --base "$base" --head "$release_branch" \
    --title "release: Meditejo $version ($code)" --body-file "$stage/pr-body.md")
  pr=${pr_url##*/}
  [[ $pr =~ ^[0-9]+$ ]] || { echo "Could not read the PR number from: $pr_url" >&2; exit 1; }
  echo "PR #$pr: $pr_url"
  # Wait for every required check to pass. Right after the PR opens GitHub may
  # report none yet; that is waited out, and a PR that never shows one is not merged.
  deadline=$((SECONDS + checks_timeout))
  while :; do
    states=$(gh pr checks "$pr" --repo "$repo" --required --json name,bucket \
      --jq '[.[] | "\(.name)=\(.bucket)"] | join(" ")' 2>/dev/null || true)
    case " $states " in
      *=fail*|*=cancel*) echo "A required check failed on #$pr ($states). The PR is left open: $pr_url" >&2; exit 1 ;;
    esac
    if [[ -n $states && $states != *=pending* ]]; then echo "required checks: $states"; break; fi
    ((SECONDS < deadline)) || {
      echo "Required checks did not finish within ${checks_timeout}s on #$pr (${states:-none reported}). The PR is left open: $pr_url" >&2; exit 1; }
    sleep "$checks_interval"
  done
  gh pr merge "$pr" --repo "$repo" --merge --match-head-commit "$bump"
  sha=$(gh pr view "$pr" --repo "$repo" --json mergeCommit --jq .mergeCommit.oid)
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || { echo "Merged #$pr but could not read its merge commit ($sha)." >&2; exit 1; }
  git fetch -q origin "$base"
  git cat-file -e "$sha^{commit}" || { echo "Merge commit $sha is not in the fetched $base." >&2; exit 1; }
  git switch -q "$base" 2>/dev/null || git switch -q -c "$base" "$sha"
  git merge --ff-only -q "$sha" || { echo "Local $base cannot fast-forward to $sha." >&2; exit 1; }
  git branch -q -d "$release_branch" || true
  git push -q origin --delete "$release_branch" 2>/dev/null || true # GitHub may have deleted it already
  echo "merged: $sha"
fi
# What gets built must carry the bump it will be tagged with.
if ((! dry)); then
  grep -qx "version: $version+$code" pubspec.yaml || {
    echo "The commit to build does not say version: $version+$code." >&2; exit 1; }
fi

# -------------------------------------------------------------------- build
step 'Build on GitHub Actions, align and sign on bjslab'
mkdir -p "$stage/build"
run env MEDITEJO_APK_DIR="$stage/build" \
  tools/meditejo/build_apk.sh "$sha" --flavor "$flavor" --name "meditejo-$version"

if ((dry)); then
  apk="$stage/build/meditejo-$version-<sha8>.apk"
else
  apk=$(ls "$stage"/build/meditejo-"$version"-*.apk | head -1)
  [[ -f $apk ]] || { echo 'build_apk.sh produced no APK' >&2; exit 1; }
fi

# ------------------------------------------------------------------- verify
step 'Verify the signed APK'
build_tools=${MEDITEJO_BUILD_TOOLS:-$HOME/.local/share/android-sdk/build-tools/36.0.0}
if ((dry)); then
  echo "+ $build_tools/apksigner verify --print-certs <apk>   # digest must equal the pin ($pinned)"
  echo "+ $build_tools/aapt2 dump badging <apk>   # versionName='$version' versionCode='$code'"
else
  certs=$("$build_tools/apksigner" verify --print-certs "$apk")
  # apksigner prints several "Signer #N ..." lines per signer (DN and digests);
  # count distinct signers by their DN line.
  signers=$(grep -cE '^Signer #[0-9]+ certificate DN:' <<<"$certs" || true)
  [[ $signers == 1 ]] ||
    { echo "The APK must have exactly one signer (found $signers)." >&2; exit 1; }
  digest=$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' <<<"$certs" | tr -d ':' | tr 'A-F' 'a-f')
  [[ $digest == "$pinned" ]] || { echo "Signing certificate $digest is not the pinned one." >&2; exit 1; }
  badging=$("$build_tools/aapt2" dump badging "$apk" | sed -n 's/^package: //p')
  [[ $badging == *"versionCode='$code'"* && $badging == *"versionName='$version'"* ]] || {
    echo "APK version does not match: $badging" >&2; exit 1; }
  echo "certificate $digest (pinned); $badging"
fi

# ------------------------------------------------------------------- assets
step 'Assets'
asset_apk="$stage/meditejo-$version.apk"
if ((dry)); then
  echo "+ cp <apk> $asset_apk"
  echo "+ sha256sum meditejo-$version.apk > meditejo-$version.apk.sha256"
  echo "+ write meditejo-release.json {schema:1, versionName:$version, versionCode:$code, apk, size, sha256, certificateSha256}"
else
  cp "$apk" "$asset_apk"
  (cd "$stage" && sha256sum "meditejo-$version.apk" >"meditejo-$version.apk.sha256")
  python3 -I - "$stage" "$version" "$code" "$pinned" <<'PY'
import hashlib, json, os, sys
stage, version, code, pinned = sys.argv[1:5]
apk = os.path.join(stage, f"meditejo-{version}.apk")
digest = hashlib.sha256(open(apk, "rb").read()).hexdigest()
manifest = {
    "schema": 1,
    "versionName": version,
    "versionCode": int(code),
    "apk": f"meditejo-{version}.apk",
    "size": os.path.getsize(apk),
    "sha256": digest,
    "certificateSha256": pinned,
}
with open(os.path.join(stage, "meditejo-release.json"), "w") as out:
    json.dump(manifest, out, indent=2)
    out.write("\n")
PY
  cat "$stage/meditejo-release.json"
fi

# ------------------------------------------------------------------ publish
step 'Publish'
# A draft first: the app only ever sees a release whose assets are all there.
run gh release create "$tag" --repo "$repo" --target "$sha" --draft \
  --title "Meditejo $version" --notes-file "$notes" \
  "$asset_apk" "$asset_apk.sha256" "$stage/meditejo-release.json"
if ((dry)); then
  echo "+ gh release view $tag --repo $repo --json assets   # expect the APK, .sha256 and meditejo-release.json"
  echo "+ gh release edit $tag --repo $repo --draft=false --latest"
else
  assets=$(gh release view "$tag" --repo "$repo" --json assets --jq '[.assets[].name] | sort | join(" ")')
  expected="meditejo-$version.apk meditejo-$version.apk.sha256 meditejo-release.json"
  [[ $assets == "$expected" ]] || { echo "Draft has unexpected assets: $assets" >&2; exit 1; }
  gh release edit "$tag" --repo "$repo" --draft=false --latest
  git fetch -q origin "refs/tags/$tag:refs/tags/$tag" || true
  gh release view "$tag" --repo "$repo" --json url --jq .url
fi

step 'Done'
if ((dry)); then
  echo "Dry run: nothing was changed. $problems problem(s) would stop a live run."
else
  echo "Released $tag (versionCode $code). Report it to Burooj with its notes."
fi
}
exit
