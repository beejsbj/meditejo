# Meditejo rename audit

Scope: Android and iOS identity, branding, app strings and upstream credit. The Dart package is still `medito`. Implementation decisions are in [DECISIONS.md](DECISIONS.md).

## Identity

- Android: `android/app/build.gradle` defaults to `io.github.beejsbj.meditejo`; `android/keystore.properties.example` documents the same ID. No private properties file is required for identity. Without a signing file, release output is unsigned for separate durable-key signing.
- `dev` and `prod` share the base application ID and the launcher name **Meditejo**. Only dev's version has `-dev`. They replace each other when signed with the same key; they cannot coexist.
- Native Kotlin namespace, packages and source paths remain `meditofoundation.medito`. Manifest activity/service/widget components are fully qualified. File-provider and startup authorities already use `${applicationId}`. Audio intent actions use the new ID.
- Android widget providers stay in the internal namespace; widget picker labels include Meditejo. Widget launch URLs, Dart parsing, track/pack sharing and Siri shortcuts use `meditejo:`. The existing Stripe callback scheme follows the new app scheme until the service-removal worker deletes it. The native and Dart session-bell URIs also agree on `meditejo://session-bells`.
- Removed upstream HTTPS app-link intent filters/entitlements. The fork does not claim `medito.app`.
- iOS app/test/widget bundle identifiers, shared app-group identifiers, display names, scheme product names and fastlane defaults use Meditejo. App identity references in Android fastlane, launch scripts and CI/Maestro invocations are updated. iOS signing is not provisioned or verified; the old Foundation-specific export profile was replaced with automatic signing config.

## Mark

Original source: `assets/branding/placeholder.svg` (cream circle on muted sage).

```sh
uv run scripts/regenerate_icons.py
```

One source drives the Flutter logo/preview, Android raster/adaptive/monochrome/notification/widget resources, iOS Icon Composer bundle (explicit 1024-point layer size), AppIcon rasters and widget logo. The script pins its user-local rendering dependency and uses no fonts or third-party art.

Removed upstream root logo bundles/exports, alternate previews and native alternate assets/registries. The icon setting is now a static preview, with no switching sheet or `dynamic_app_icon_flutter_plus`. The generated native Pigeon icon interface stays compatible; its implementation reports only the primary icon. There is exactly one Android launcher.

## Remaining `medito` / `Medito` hits

Audited with `rg`, including hidden workflow/Maestro files, and a scan of tracked text files. Do not bulk-replace these strings.

| Category | Remaining references | Reason / owner |
| --- | --- | --- |
| Intended: internal code | `name: medito`, `package:medito/` imports, Medito-prefixed widget/API/type names, Kotlin packages/imports/resource namespace, Pigeon configs/channels, internal preference/cache/notification IDs, method channels (`medito.app/widget`, `com.medito.app/siri`) | Internal names are independent of the installed application identity. Keeping both ends unchanged avoids churn and preserves storage/channel compatibility. |
| Intended: native source names | `ios/MeditoWidget*`, `MeditoWidgetExtension` targets, `MeditoLogo` imageset name (its SVG is replaced), historical compiler/source paths | Internal file/target identifiers, not user-facing app branding. |
| Intended: credit/history | README and About credit, AGPL/upstream notices, fork research docs, historical release notes, upstream design/code documentation, original-bell attribution | Preserve provenance and distinguish upstream features from the fork. LICENSE is unchanged. |
| Left for de-medito: Foundation/content | Donation/shop/impact/Black Friday strings and fixtures, Medito Team mock artist credits, `the_medito_course.png`, Foundation/support/social URLs, catalogue references | Foundation content and the features being removed by the parallel worker. Those lines are intentionally unchanged. |
| Left for de-medito: services | Firebase files, analytics identifiers/channels, backend URLs, Stripe merchant IDs/names, auth mock identities, network errors that explicitly identify Medito's servers, matching tests | Parallel backend/service-removal slice. No Firebase/backend/Stripe/analytics code was removed here. |
| Left for build/integration: old release infrastructure | Upstream certificate-repository environment-variable names, absolute paths in historical fastlane scripts, Firebase deployment config, private CI signing variables | Inherited infrastructure, not this fork's default identity. The new Android build/signing route is documented by the build worker. iOS is config-only. |
| Genuinely missed | None found in the requested app identity/branding slice after the audit | Runtime native builds/phone checks remain unverified. |

No remaining upstream custom/deep-link scheme, upstream HTTPS track/pack sharing URL, `.dev` application suffix, or old application ID in fastlane/launch invocations was found. `meditofoundation.medito` remains only in internal packages, components, source paths and a historical Android comment.

## Verification

- `nice -n 10 flutter pub get`: passed; only dependency removal was `dynamic_app_icon_flutter_plus`.
- `nice -n 10 flutter gen-l10n`: passed; tracked generated localisations updated for English, German and Spanish.
- Pigeon: the README command initially failed with `Unable to deduce package name, and no package name supplied.` Adding `--package_name medito` succeeded. Tracked native generated files were unchanged.
- Python XML/plist checks: all Android resource/manifests and iOS plist/entitlement/scheme files parse; one Android launcher; all manifest icon references resolve; all locale app names are Meditejo; LICENSE unchanged.
- Placeholder raster visually inspected.
- `nice -n 10 dart run build_runner build --delete-conflicting-outputs`: passed, 135 outputs. Pigeon and tracked generated native files are unchanged. The runner warns that `--delete-conflicting-outputs` is now ignored and the pinned analyzer language version (3.11) trails Dart 3.13; no dependency upgrade was made in this slice.
- `nice -n 10 flutter analyze`: exit 1, **zero errors, zero warnings, one existing info lint** in an unchanged shop test. Exact diagnostic:

  ```text
     info • Use the null-aware marker '?' rather than a null check via an 'if'. Try using '?' • test/services/fourthwall_service_test.dart:130:21 • use_null_aware_elements

  1 issue found. (ran in 22.4s)
  ```

- A second `nice -n 10 uv run scripts/regenerate_icons.py` produced no diff in the generated brand assets/resources.
- `ruby -c` passed for changed fastlane files; shell syntax checks passed for the changed build scripts.
- `nice -n 10 flutter test --concurrency=2 --reporter expanded`: exit 1, **806 passed, 1 skipped, 10 failed** in 11:09. All failures are in unchanged `test/stats_manager_test.dart` / `test/stats_manager/` files; `lib/utils/stats_manager.dart` is also unchanged from the branch base. Updated rating-text assertions passed. No rename/UI tests failed. The native-build/phone checks above are still required.
- Focused UTC check: `env TZ=UTC nice -n 10 flutter test --no-pub --concurrency=2 --reporter expanded test/stats_manager_test.dart test/stats_manager/streak_parity_test.dart test/stats_manager/consistency_score_parity_test.dart test/stats_manager/consistency_score_test.dart` passed **all 82 tests** (`00:03 +82: All tests passed!`). All ten failures from the full run disappear in UTC. This demonstrates timezone-dependent fixture behaviour; it is not a full-suite UTC run. The fixture assumptions need follow-up during integration, rather than changing stats code in the rename slice.
- Gradle/APK and iOS builds were not run in this slice. Phone launch, widget pin/tap and upgrade behaviour need the integrated build.

### Exact failing test output (default America/Toronto environment)

```text
03:18 +535 -1: /home/admin/.t3/worktrees/meditejo/fork-rename-meditejo/test/stats_manager_test.dart: StatsManager Audio Completion Edge Cases StatsManager with Specific Timestamps Tests calculateStreak - with freeze on Feb 26 [E]
  Expected: <7>
    Actual: <3>

03:18 +535 -2: /home/admin/.t3/worktrees/meditejo/fork-rename-meditejo/test/stats_manager_test.dart: StatsManager Audio Completion Edge Cases StatsManager with Specific Timestamps Tests calculateStreak - with freezes on both Feb 21 and Feb 26 [E]
  Expected: <9>
    Actual: <3>

03:39 +583 -3: /home/admin/.t3/worktrees/meditejo/fork-rename-meditejo/test/stats_manager/streak_parity_test.dart: Streak parity fixture future_ignored [E]
  Expected: <1>
    Actual: <2>
  fixture case "future_ignored" expected streak 1

03:40 +585 -4: /home/admin/.t3/worktrees/meditejo/fork-rename-meditejo/test/stats_manager/streak_parity_test.dart: Streak parity fixture offset_excludes_session_pushed_past_shifted_today [E]
  Expected: <0>
    Actual: <1>
  fixture case "offset_excludes_session_pushed_past_shifted_today" expected streak 0

06:21 +604 -5: /home/admin/.t3/worktrees/meditejo/fork-rename-meditejo/test/stats_manager/consistency_score_parity_test.dart: Consistency score parity fixture thirty_days_perfect [E]
  Expected: <100>
    Actual: <97>
  fixture case "thirty_days_perfect" expected 100%

06:21 +605 -6: /home/admin/.t3/worktrees/meditejo/fork-rename-meditejo/test/stats_manager/consistency_score_parity_test.dart: Consistency score parity fixture gap_then_recovery [E]
  Expected: <48>
    Actual: <33>
  fixture case "gap_then_recovery" expected 48%

06:21 +607 -7: /home/admin/.t3/worktrees/meditejo/fork-rename-meditejo/test/stats_manager/consistency_score_parity_test.dart: Consistency score parity fixture ema_alternating_45_days [E]
  Expected: <72>
    Actual: <68>
  fixture case "ema_alternating_45_days" expected 72%

06:26 +632 -8: /home/admin/.t3/worktrees/meditejo/fork-rename-meditejo/test/stats_manager/consistency_score_test.dart: Consistency Score Tests calculateConsistencyScore - 30 days of perfect history then 10 days off, score starts recovering immediately on return [E]
  Expected: a value greater than <0.4>
    Actual: <0.3312445180950001>
     Which: is not a value greater than <0.4>

06:26 +642 -9: /home/admin/.t3/worktrees/meditejo/fork-rename-meditejo/test/stats_manager/consistency_score_test.dart: Consistency Score Tests calculateConsistencyScore - handles exactly 30 days of history [E]
  Expected: <1.0>
    Actual: <0.9689655172413794>

06:26 +645 -10: /home/admin/.t3/worktrees/meditejo/fork-rename-meditejo/test/stats_manager/consistency_score_test.dart: Consistency Score Tests calculateConsistencyScore - exactly 30 days of history [E]
  Expected: <1.0>
    Actual: <0.9689655172413794>
```
