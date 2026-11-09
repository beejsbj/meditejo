# Per-kind defaults (Practice vs Talks): code audit
Source: origin/develop 9781a2d7; PR #108 = ux/72-customize-regroup 5522278b. Paths under lib/. Read-only.

## 1. What is per kind today
Storage is one JSON blob per scope: `cues.v1.<kind>` and `cues.v1.<kind>.course.<id>` (providers/cues/cue_settings_provider.dart:19-21). A read falls back course -> kind (:25-26). `update()` writes the kind unless `courseOverride` is set (:60-64). `CueKind {practice, talks}` is at models/cues/cue_settings.dart:6.
Everything in `CueSettings` therefore follows the kind/course split:
- Bells (start/end/interval, interval timing, bellVolume), countdown, rhythm (pulse*), extend/ending silence (extendMinutes), duration: cue_settings.dart:35-58, toJson :147-171.
- Autoplay, interludeSeconds (the pause), hideBeforePractice: also in the blob (:55-57), so per kind and per course.
- Sound: `backgroundEnabled`, `backgroundSoundId`, `backgroundVolume`, `soundscape` (:51-54). The only kind-dependent code default is `backgroundEnabled` (`defaults(kind)`, :64-65). Decision 17 made both kinds start silent, but Practice still defaults to enabled here.
- The Sounds mixer keeps its own parallel per-kind state: `sessionDefaults` keyed by `SoundscapeSessionKind` (providers/soundscape/soundscape_provider.dart:92,113) with a per-kind volume (:359). That is a second per-kind store, separate from `cues.v1`.
Truly global: none of the cue settings. Playback speed is not stored anywhere (see 2).
Kind resolution at session start: timer => practice; else the course's library group, else `hasBackgroundSound` (cue_settings_provider.dart:80-98).
Settings already shows two entries, "Practice sounds & cues" and "Talks sounds & cues" (`CueDefaultsTile`, views/settings/widgets/practice_default_tiles.dart:47-90; mounted at views/settings/settings_sections.dart:123-130). Each opens `CustomizeSheet(scope: CueScope(kind))`.

## 2. Playback speed
Not per kind, not per course, not per track, not persisted. It is a transient engine value.
- Set: the player's action-bar chip opens `showSpeedSheet` (views/player/widgets/bottom_actions/player_action_bar.dart:82-91) -> `PlayerNotifier.setSpeed` (providers/player/player_provider.dart:290-296) -> Android `_api.setSpeed` / iOS `iosAudioHandler.setSpeed` (ios_audio_handler.dart:507).
- Read: `audioStateProvider.speed` mirrors the engine (audio_state_provider.dart:94). The chip and sheet read it (audio_speed_widget.dart:16, speed_sheet.dart:22).
- Reset: every session start forces `setSpeed(1.0)` (player_provider.dart:168 Android, :179 iOS). The comment at :121-124 says this is deliberate ("a slowed-down speed doesn't carry over").
- Range: `playbackSpeedOptions = [0.6 ... 1.0]` (speed_sheet.dart:8-9) "only ever slowed down". 1.5x/2x are impossible today. The timer hides the control (player_action_bar.dart:35-37).
- Already speed-aware: `finishesAt(speed)` (cue_settings.dart:260-275), Customize's "Finishes at" (customize_sheet.dart:89-114), `cue_schedule.dart:186-193`, `session_bell_schedule.dart:10-41` (end lead scales by speed). The native Kotlin/Swift cue engines were not audited for speed > 1.
To make it per kind with a per-course override (rides the existing mechanism):
1. Add `playbackSpeed` (double, default 1.0, clamp ~0.5-2.0) to `CueSettings`: field, ctor, copyWith, toJson, fromJson. No version bump is needed, because a missing key reads as 1.0 and `formatVersion` stays 1. `nativeConfiguration` spreads toJson, so confirm native ignores the unknown key.
2. player_provider.dart:168/179: `setSpeed(_cues!.playbackSpeed)` instead of 1.0 (`_cues` is already resolved there). Practice and timer stay 1.0 by default; keep the timer pinned to 1.0.
3. Widen `playbackSpeedOptions` for talks (e.g. 0.6-2.0 with 1.25/1.5/1.75/2). Practice can keep a capped list or the same list, since the owner's rule is "default never faster for practice".
4. Choose the sheet's write path: (a) session-only tweak, with a "Make default for talks / this course" action, or (b) every change saves via `cueSettingsProvider(scope).update(..., courseOverride)`. Recommend (a) so a one-off tweak does not rewrite defaults.
5. Add a "Playback speed" row to Customize (Time or a Player group) and "Finishes at" already honours speed; tests for model round trip, provider fallback, and player start applying the speed.
Size: medium, about 150-250 lines plus tests, 1 PR. Main risk is bells and the end lead at 2x on the native side (needs a device check), not the data model.

## 3. Issue #75 under the new decision
#75 (no comments) proposes one `cues.v1`, a Practice-set-wins migration, and a BRIEF note. All of that is dropped. Still worth doing:
a. Close or retitle #75, and record in DECISIONS/BRIEF that Practice and Talks keep separate defaults (refining decisions 8 and 17). Docs only, no conflict. DECISIONS.md is touched by #108 (+12 lines), so expect a trivial merge.
b. Make the split legible in Settings: rename the tiles to "Practice defaults" / "Talks defaults", with a caption naming what they cover (bells, sound, autoplay, speed). Files: settings_sections.dart:123-130, the l10n keys `settingsPracticeCues`/`settingsTalksCues` (+ de/es). Small. Conflict: l10n files are heavily edited in #108 (app_en.arb 168 lines, generated app_localizations*). Rebase after #108 to avoid regenerating twice.
c. Customize title or subtitle states its scope when opened from Settings ("Talks defaults", "Practice defaults") and shows "For all talks / For all practice / For this course" on every setting, the way Autoplay already does (autoplay_control.dart on 5522278b:89-96; `_scopeCard` in #108's customize_sheet). Touches customize_sheet.dart, which #108 rewrites (+690/-1012). Do this after #108 merges; do not start it before.
d. Per-kind speed (section 2). Mostly player/model files, so it does not conflict with #108 except cue_settings.dart (#108 changes ~20 lines around autoplay/hideBeforePractice/interlude) and the Customize row. Build after #108 merges for the UI, but the model and player_provider parts are independent and can start now.
e. A "Reset to <kind> defaults" or "Copy Practice settings to Talks" affordance in Customize: optional, small, post-#108.
f. Align the default sound: `defaults(kind)` still sets `backgroundEnabled` true for Practice only (cue_settings.dart:64-65) despite decision 17. Separate small cleanup; decide whether it is intentional.

## 4. Merge-assuming code to back out
None found. No `cues.v1` single-default key, no Talks-to-override migration, and no branch/commit for #75 exist (remote heads checked; no `ux/75-*`). The only migration-like code is the one-off practice-only carry-over of `timerMinutes` into duration (cue_settings_provider.dart:28-34), which is fine and kind-specific. `CueKind` is used consistently (player_view.dart:288,389-391 branch on it). #108 keeps the per-kind model (its docs say "defaults for the scope's kind", its `_scopeCard` compares a course to its kind's defaults). Nothing to revert; only the issue text and the docs plan are stale.
