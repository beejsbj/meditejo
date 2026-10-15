<!-- Scout report, 2026-10-15 (Sonnet subagent; source read via gh api). Mindra has NO LICENSE file despite README claiming MIT: do not lift code without asking the author. -->

## Mindra (gonewx/mindra) as design input

Everything below is verified in code unless marked *(inferred)*. Paths are relative to the repo root. I did not view README screenshots because there are none. I read sources via `gh api` only. One stray listing file was left at `/tmp/mindra_tree.tsv`, which is outside the cockpit repo.

### 1. Architecture and vitality
- **Layout:** feature-first Clean Architecture under `lib/features/{home,media,meditation,player,goals,settings,onboarding}`, with `lib/core` and `lib/shared`.
- **Size:** about 28.4k lines of Dart in `lib/` (95 files) and 2.3k lines of tests. `global_player_service.dart` is one 86 KB file, and `app_localizations.dart` is a hand-written 64 KB file.
- **State:** `flutter_bloc` (MediaBloc) plus `provider` (ThemeProvider). Session and statistics logic lives in *static* classes such as `MeditationSessionManager`, with `get_it` for DI. It is mixed and inconsistent.
- **Persistence:** raw `sqflite` in `lib/core/database/database_helper.dart`, with a hand-rolled web storage fallback.
  - There are three tables: `media_items`, `meditation_sessions` and `user_preferences`.
  - The code around them is heavy on health-checker and repair machinery (`database_health_checker.dart`, `database_repair.dart`).
- **Audio:** `audioplayers` (`lib/core/audio/audio_player.dart`) plus `audio_service` (`lib/features/player/services/audio_handler.dart`). It is not `just_audio`.
- **YouTube:** `youtube_explode_dart` is in `pubspec.yaml`, but no file in `lib/` references YouTube, RSS, podcast or playlist feeds. The README's "YouTubeExplode – network video parsing" is vapourware.
- **Platforms:** Android and Linux are tested. iOS, web, Windows and macOS are claimed.
- **Liveness:** 136 commits, all from one author. The last push was 2026-08-28, and the last release was v0.5.6 on 2025-09-03. The repo has 1 star, 0 forks and 0 issues. Most recent commits are release-site and App Store docs.
- **Licence caveat:** the README claims MIT, but there is **no LICENSE file** in the tree and GitHub reports a null licence. Treat any code lift as unlicensed until you ask the author.

### 2. Import flow
- **What the user does:** Library, then the top-right add button, which opens `lib/features/media/presentation/widgets/add_media_dialog.dart` (about 1,200 lines). The dialog has a Local/URL toggle and then a form: title (required), description, category (required), duration in seconds, and a thumbnail URL.
- **URL mode:** a single `TextField` with no `onChanged` and no resolver. The title is never fetched. A direct media URL is assumed, and the media type is guessed from the file extension (`mp4/mov/avi/mkv/webm` means video, anything else means audio).
- **File mode:** `FilePicker` accepts mp3, aac, wav, flac, m4a, ogg, mp4, mov, avi, mkv and webm. The title is prefilled from the filename.
- **Duration:** auto-detected only for picked files, via `MindraAudioPlayer.getMediaDuration`, which opens a throwaway `audioplayers` player. For URLs it is typed in by hand. An empty duration saves as 0.
- **Cover:** manual URL, otherwise one of 5 bundled stock JPGs chosen at random.
- **Failures:** the only checks are required-field SnackBars. A bad or unplayable URL is accepted silently and fails at playback with a generic error. `setUrl` has one special case, for `gst-resource-error` on Linux.
- **Why it hurts:** the user has to know a raw media URL, fill about 5 fields, and look up the duration themselves. There is no preview, no validation, no page or feed or YouTube resolution, and no batch add.
- **Better flow:** paste any link, then classify it (feed, YouTube, page or media). Resolve it (RSS parse, YouTube Explode, or a HEAD request plus `og:` tags). Show a preview with title, cover, count and total duration, and offer "Add as course" or "Add single". Failures should explain why, and metadata should stay editable afterwards.

### 3. Progress and session tracking
This is the strongest part.
- **`meditation_sessions`:** `media_item_id`, `duration`, `actual_duration`, `start_time`, `end_time`, `type`, `sound_effects` (list of the effects in use), `rating`, `notes`, `is_completed`.
- **`MeditationSessionManager`:** a session is written to the DB at start with `is_completed=0`, so a crash loses nothing. Pause time is tracked separately. It force-saves on app background, and `stopSession` keeps partial progress.
- **Seek protection:** progress backward-jumps and jumps over 10 s are ignored (it adds a conservative 5 s instead), so scrubbing doesn't inflate minutes (`updateSessionProgress`).
- **Streak:** `_calculateStreakDays` in `meditation_statistics_service.dart` groups sessions by date and anchors on today or yesterday. A streak resets after more than 1 day missed.
- **Counted sessions:** `isCompleted || actualDuration > 0`.
- **`MeditationStatistics`:** `streakDays`, `weeklyMinutes`, `totalSessions`, `totalMinutes` (rounded up per session), `averageRating`, `weeklyData[7]` and `monthlyRecords`. There are 6 achievements: `first_meditation`, `week_streak`, `focus_master` (a 30-minute session), `meditation_expert` (600 minutes), `consistency_champion` (30-day streak) and `variety_seeker`.
- **Goals:** `UserGoal` holds a daily goal (minutes or hours) and a weekly goal (sessions), plus reminder days and time.
- **Resume:** a single global last-played media id and position stored in `user_preferences` (`last_played_media_id`, `last_played_position`), restored paused on launch. There is no per-item resume position and no per-item completion, so "N of M" needs to be built.
- **Screens:** the home `daily_goal_card`, the history pages (`enhanced_meditation_history_page.dart`, 38 KB), and the bottom-nav tabs Home, Library, Play, Progress and Profile.

### 4. Organisation
- **Categories:** a fixed 10-value `MediaCategory` enum (meditation, sleep, focus and so on) with tab chips in the library.
- **Other fields on `media_items`:** `tags` (stored but no UI evidence), `is_favorite`, `sort_index` (drag-reorder mode), `play_count` and `last_played_at`.
- **Playlist:** the player just uses the currently filtered list with shuffle and repeat modes. There is no course, sequence or collection entity.
- **Search:** the library search field has `// TODO: Implement search` in its `onChanged`, even though `MediaBloc` has a `SearchMediaItems` event.
- **Roadmap (README):** cloud sync, "professional course content", community, AI recommendations and VR/AR are all unchecked. There are no issues.

### 5. Ambient overlay and timer
- **Sound effects:** `lib/features/player/services/sound_effects_player.dart` uses **one** `AudioPlayer` in loop mode, and `toggleEffect` zeroes every other effect.
  - So it is a single-slot ambient selector, not a mixer.
  - It has 4 bundled mp3s (rain 0.4 MB, ocean 5.8 MB, wind chimes 7.4 MB, birds 7.9 MB), a master volume, and per-effect volume persisted in `SharedPreferences`.
  - Effect names are hard-coded Chinese in `sound_effect.dart`.
- **Timer:** a sleep timer only, with presets 5/10/15/30/45/60 min (`lib/shared/widgets/timer_dialog.dart`). It is a plain `Timer` in `global_player_service.dart` that ends the session. There are no bells or interval cues, no silent timer without media, and no fade-out.

### 6. UX/UI flaws
- **Empty state:** the library shows an icon and "click the top-right button". There is no default content.
- **Dead code:** `RecommendedContent` is dead code with hard-coded Unsplash links and is not used anywhere.
- **Onboarding:** 4 swipe pages with **hard-coded Chinese strings** (`'欢迎来到 Mindra'`, `'开始使用'`), so the English locale breaks there.
- **Density and hierarchy:** the add dialog is a tall form with a repeated hand-built dark/light colour ternary. The home screen is a stack of goal card, quick actions and recent sessions, with the greeting duplicating the settings icon. User-adjustable card spacing and padding in settings *(inferred: this is a sign of unresolved layout decisions)*.
- **Player:** a nav tab with its own empty state that sends you back to the library.

### 7. Takeaways

**Borrow**
1. Create the session row at start with `is_completed=0` and update it on pause, background and stop, so crashes lose nothing.
2. Track `actual_duration` separately from item duration, and ignore seek jumps when accumulating time.
3. Keep the streak rule of anchoring on today or yesterday, and count a day if `actual_duration > 0`.
4. Keep `sound_effects` on each session as a list.
5. Use a weekly-minutes bar plus a monthly day-record view, with a small set of earned achievements, one of them a 30-day streak.
6. Resume the last item paused on launch, and store the position per item rather than only globally.
7. Add a minimum viable "empty library" bundle (a starter pack or the Dharma Seed catalogue) so the first launch isn't blank.

**Avoid**
1. Don't build a manual metadata form for imports.
2. Don't claim a feature in the README that has no code behind it (YouTube, search).
3. Don't use static singleton managers with parallel "enhanced" duplicates (`MeditationSessionManager` and the enhanced services).
4. Don't hard-code strings in onboarding or sound names.
5. Don't ship a single-slot "mixer"; use one player per layer with its own volume.
6. Don't ship a sleep timer as the only timer; add intervals, bells and a pre-roll.
7. Don't put the add action as a hidden top-right icon; make it a primary action in the empty state.
8. Don't build one 86 KB player service.

### Reusable code
- `lib/features/meditation/domain/entities/meditation_session.dart` and the `_calculateStreakDays` and `updateSessionProgress` logic. These are lift-and-adapt only, after clearing the licence question above.
- There is no URL resolver to lift. The logic worth porting is `getMediaDuration` in `lib/core/audio/audio_player.dart`, which is small.
- For a resolver, Medito and `youtube_explode_dart` are better sources than anything here.
