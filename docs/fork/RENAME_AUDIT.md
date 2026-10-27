# Meditejo rename audit

Scope: Android and iOS identity, branding, app strings and upstream credit. The Dart package is still `medito`. Implementation decisions are in [DECISIONS.md](DECISIONS.md).

## Identity

- Android: `android/app/build.gradle` defaults to `io.github.beejsbj.meditejo`; `android/keystore.properties.example` documents the same ID. No private properties file is required for identity. Without a signing file, release output is unsigned for separate durable-key signing.
- `dev` and `prod` share the base application ID and the launcher name **Meditejo**. Only dev's version has `-dev`. They replace each other when signed with the same key; they cannot coexist.
- Native Kotlin namespace, packages and source paths remain `meditofoundation.medito`. Manifest activity/service/widget components are fully qualified. File-provider and startup authorities already use `${applicationId}`. Audio intent actions use the new ID.
- Android widget providers stay in the internal namespace; widget picker labels include Meditejo. Widget launch URLs, Dart parsing, track/pack sharing and Siri shortcuts use `meditejo:`. The native and Dart session-bell URIs also agree on `meditejo://session-bells`.
- Removed upstream HTTPS app-link intent filters/entitlements. The fork does not claim `medito.app`.
- iOS app/test/widget bundle identifiers, shared app-group identifiers, display names, scheme product names and fastlane defaults use Meditejo. App identity references in Android fastlane, launch scripts and CI/Maestro invocations are updated. iOS signing is not provisioned or verified; the old Foundation-specific export profile was replaced with automatic signing config.

## Mark

Original source: `assets/branding/placeholder.svg` (cream circle on muted sage). *Superseded 2026-10-26 by the shelter house mark (decision 21): the source is now `assets/branding/house_mark.json`, regenerated with `uv run tools/meditejo/branding/make_icons.py`; see DECISIONS.md, identity PR 1.*

One source drives the Flutter logo/preview, Android raster/adaptive/monochrome/notification/widget resources, iOS Icon Composer bundle (explicit 1024-point layer size), AppIcon rasters and widget logo. The script pins its user-local rendering dependency and uses no fonts or third-party art.

Removed upstream root logo bundles/exports, alternate previews and native alternate assets/registries. The icon setting is now a static preview, with no switching sheet or `dynamic_app_icon_flutter_plus`. The generated native Pigeon icon interface stays compatible; its implementation reports only the primary icon. There is exactly one Android launcher.

## Integration with PR #3

PR #2 merges de-Medito commit `37548a2543d875e27b8db7364b8ba3d78019999e` without a rebase. Merge order: **#3 → develop, then #2 → develop** (PR #2 targets `fork/remove-medito-backend` while stacked). The phone build must use PR #2's head so it contains both slices.

All 29 conflicts were resolved using the service-removal version as the base. All 186 files deleted by that branch stay absent, including the five modify/delete conflicts (mock documentation/data, Firebase notifications and sign-in Maestro flows). Local startup, local settings/navigation, workflow service removals and the reduced dependency set survive.

Non-mechanical resolutions:

- Localisations retain exactly PR #3's keys plus four About/credit keys; app wording and source-sharing copy change to Meditejo. Generated Dart files were regenerated, not hand-merged.
- Settings keeps the local advanced controls and restores the Meditejo credit row. The two rename-only widgets use the fixed brand name instead of the removed `appName` localisation getter. README explains the working offline timer and currently empty catalogue. Both decision histories remain in chronological order.
- The surviving deep-link parser keeps local readiness/deduplication and accepts the fork's custom scheme. Track/pack links and widget/Siri URLs agree with it; the new local-timer Maestro link was updated too. Quote-share cards now display Meditejo instead of an upstream domain. Stats sharing links to the fork source.
- `flutter pub get` starts from PR #3's lockfile and removes only the obsolete alternate-icon dependency; Widgetbook's lockfile is also reconciled. No backend dependency returns.
- **No CocoaPods executable is available.** `ios/Podfile.lock` is exactly PR #3's file, as requested. It still lists `dynamic_app_icon_flutter_plus`; `pubspec.yaml` no longer depends on it, and alternate icon resources/registries are removed. A future macOS `pod install` must reconcile that lockfile before iOS building.

## Remaining `medito` / `Medito` hits

Audited the worktree's tracked text (including hidden workflows and Maestro), using:

```sh
git grep -n -I -e medito -e Medito -- .
rg -n 'medito\.app|meditofoundation\.org|org\.meditofoundation' lib .maestro android ios
```

| Category | Remaining references | Reason / owner |
| --- | --- | --- |
| Intended: internal code | Dart package/imports, Medito-prefixed types/widgets, Kotlin namespace/packages/component paths, Pigeon APIs, preferences/cache/notification IDs and paired method channels (`medito.app/widget`, `com.medito.app/siri`) | Independent of installed identity; retain compatibility and avoid churn. |
| Intended: native/development names | `ios/MeditoWidget*`, `MeditoWidgetExtension`, `MeditoLogo` imageset name (replacement artwork), compiler paths, CI archive/cache/key filenames, Widgetbook package and preview seeds/test hosts | Internal source/resource/tool names. They are not app landing pages or share links. |
| Intended: credit/provenance/history | README/About and translations, fork research/decision history, historical release notes, original bell attribution, inherited developer docs/examples | Preserve upstream credit, the retained impact-card testimonial about Medito, and history; LICENSE unchanged. The remaining Foundation URL in app code opens the explicit upstream credit. |
| Left for de-medito/content follow-up | Unused `assets/images/the_medito_course.png` and its `assets/fonts/` duplicate; retained reusable impact-card localisation keys | Course artwork has no remaining code reference and is upstream content, not an app icon. Backend, mock, donation/account, Firebase, Stripe and analytics source/dependencies were removed by #3. Saved user download metadata may retain its source; no metadata is erased. |
| Deferred native/tooling follow-up | Obsolete alternate-icon entry in the retained iOS pod lock; inherited iOS signing certificate-repository configuration and absolute source paths | macOS tooling/signing and future release infrastructure. No iOS build was run. |
| Genuinely missed | None found in installed identity, runtime app wording, artwork, share links or deep-link registrations | Phone/native runtime checks remain unverified. |

No upstream custom scheme or HTTPS track/pack sharing URL remains. There is no `.dev` application-ID suffix or old ID in launch/fastlane/Maestro commands. The only `medito.app` occurrences in app/native source are paired internal method-channel names. Remaining `meditofoundation.org` app strings are About credit/provenance.

## Verification (integrated branch)

- `nice -n 10 flutter pub get` at root and in `widgetbook/`: passed. Each regenerated lock differs from #3 only by removing `dynamic_app_icon_flutter_plus`.
- `nice -n 10 flutter gen-l10n`: passed; all four tracked generated localisation files rebuilt. Key-set comparison confirms #3's keys plus four credit keys in every ARB, with the upstream testimonial unchanged.
- Pigeon: `for f in pigeon_conf.dart pigeons/*.dart; do [ -f "$f" ] || continue; nice -n 10 dart run pigeon --input "$f" --package_name=medito || exit; done` passed. No native/generated Pigeon differences from #3.
- `nice -n 10 dart run build_runner build --delete-conflicting-outputs`: exit 0, **81 outputs in 104s**. Non-fatal generator diagnostics: `--delete-conflicting-outputs` is ignored by this runner, the pinned analyzer supports Dart 3.11 while the SDK is 3.13, and `completionReceipts` has equivalent constructor/JsonKey defaults. No dependency upgrade was made for these diagnostics.
- `nice -n 10 dart format` on the six handwritten integration files: no changes required.
- `env TZ=America/Toronto nice -n 10 flutter analyze --no-pub`: **exit 0, no issues** (`No issues found! (ran in 7.7s)`). The first analysis caught two removed `appName` getter references; both were fixed before the final run.
- `env TZ=America/Toronto nice -n 10 flutter test --no-pub --concurrency=2 --reporter expanded`: **exit 0, all 467 passed**, no skips or failures (`02:11 +467: All tests passed!`). This includes all previously failing stats cases and the local home/timer flow. An earlier partial run was intentionally stopped to restore upstream testimonial wording; only this completed run is counted.
- Static checks: **45 Android XML files** parse, all manifest icon/resource references resolve, exactly one launcher exists, app-name resources and iOS display names are Meditejo, iOS XML/plists/entitlements/schemes parse, all **186 de-Medito deletions** stay absent, and no merge markers/unmerged index entries remain. `git diff --check` passes. LICENSE is byte-for-byte unchanged from `origin/develop`.
- Grep audit: runtime share/deep links use the fork; remaining app/native `medito.app` strings are paired internal channels and Foundation URLs are explicit upstream credits. See categories above, including the unused course-image follow-up.
- **Unverified:** Gradle/APK, CocoaPods resolution, iOS builds/signing and phone launch/widget/upgrade behavior. No Gradle or native builds were run on bjslab. The icon source/outputs are unchanged from the reviewed rename work; this integration did not redraw the placeholder.


## Timezone comparison with plain `origin/develop`

The baseline was checked out detached at `8d527429` in `/tmp/meditejo-rename-develop-baseline`. Its tracked tree remained clean after dependencies, Pigeon and build_runner generation. No stats source or fixture edits were made there.

```sh
env TZ=America/Toronto nice -n 10 flutter test --no-pub --concurrency=2 --reporter expanded \
  test/stats_manager_test.dart test/stats_manager/streak_parity_test.dart \
  test/stats_manager/consistency_score_parity_test.dart test/stats_manager/consistency_score_test.dart
```

Exit **1**, **72 passed, 10 failed** (`00:02 +72 -10: Some tests failed.`). These are the same ten failures seen before integration, proving they predate the rename. Exact failure diagnostics from the new baseline run:

```text
00:00 +32 -1: test/stats_manager_test.dart: StatsManager Audio Completion Edge Cases StatsManager with Specific Timestamps Tests calculateStreak - with freeze on Feb 26 [E]
  Expected: <7>
    Actual: <3>

00:00 +32 -2: test/stats_manager_test.dart: StatsManager Audio Completion Edge Cases StatsManager with Specific Timestamps Tests calculateStreak - with freezes on both Feb 21 and Feb 26 [E]
  Expected: <9>
    Actual: <3>

00:00 +47 -3: test/stats_manager/streak_parity_test.dart: Streak parity fixture future_ignored [E]
  Expected: <1>
    Actual: <2>

00:00 +49 -4: test/stats_manager/streak_parity_test.dart: Streak parity fixture offset_excludes_session_pushed_past_shifted_today [E]
  Expected: <0>
    Actual: <1>

00:01 +52 -5: test/stats_manager/consistency_score_parity_test.dart: Consistency score parity fixture thirty_days_perfect [E]
  Expected: <100>
    Actual: <97>

00:02 +53 -6: test/stats_manager/consistency_score_parity_test.dart: Consistency score parity fixture gap_then_recovery [E]
  Expected: <48>
    Actual: <33>

00:02 +55 -7: test/stats_manager/consistency_score_parity_test.dart: Consistency score parity fixture ema_alternating_45_days [E]
  Expected: <72>
    Actual: <68>

00:02 +58 -8: test/stats_manager/consistency_score_test.dart: Consistency Score Tests calculateConsistencyScore - 30 days of perfect history then 10 days off, score starts recovering immediately on return [E]
  Expected: a value greater than <0.4>
    Actual: <0.3312445180950001>

00:02 +68 -9: test/stats_manager/consistency_score_test.dart: Consistency Score Tests calculateConsistencyScore - handles exactly 30 days of history [E]
  Expected: <1.0>
    Actual: <0.9689655172413794>

00:02 +71 -10: test/stats_manager/consistency_score_test.dart: Consistency Score Tests calculateConsistencyScore - exactly 30 days of history [E]
  Expected: <1.0>
    Actual: <0.9689655172413794>
```

The merged stats source and fixtures match PR #3. Its calendar-date/DST fixes are kept without changing expected scores. Integrated Toronto result is recorded above.
