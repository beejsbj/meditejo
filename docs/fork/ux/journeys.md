# Journeys: the main paths through the app

The UX pass (BRIEF decision 23), tracked in #88. `interaction-model.md` lists every control as `develop` stood before the pass; `field-notes-0.1.4.md` is Burooj's phone pass on 0.1.4. This file walks the main journeys **as the app stands on `apk/ux-pass`** (PR #115, head `a44ef9ec`: `develop` at `1b30cb2c` plus the held PRs #107, #108, #111, #113, #117, #120–#126), and says where friction remains. `friction.md` ranks the friction; `v1-done.md` says what blocks v1.

**What "as it stands" means.** Read from the PR descriptions and checked by widget tests and headless screenshots (1080×2340 @2.625, the S23+). **None of the held changes has been tested on a device yet.** Where a step depends on feel (motion, audio, thumb scrolling, real network), it says "device check". Status words are those of `friction.md`: *on develop*, *on apk*, *open*, *waiting on owner*.

Decisions behind the steps (2026-10-28 on): Pin, never Favourites; the 5th tab is Settings and the You page opens from a top-right button; no Add on Home, Library gets the "+"; Practice and Talks keep separate defaults; a YouTube channel is a teacher; the app always opens on Home.

## 1. First launch to Home

1. Fresh install: one skippable intro, "What Meditejo is", with Start. No questionnaire. (#125, on apk)
2. Start lands on Home. An upgrade from an existing install goes straight to Home. (#125, on apk)
3. Every later launch opens on Home, whatever tab was last used. (#109, on develop)
4. The battery-optimisation page is now a Settings row, with a one-time offer after the first reminder is set. (#125, on apk)

Home, top to bottom: the mark; Continue (up to 3); Timer and Sounds tiles and up to two preset tiles; Pinned (three shown, the rest under "See all"). No Add pill. The You button sits top-right.

Friction that remains:
- The intro has no tour button yet. #87 stays open for the tour, which waited on #61 (on develop) and #63 (waiting on owner).
- The mark does nothing on touch, and its long-press (pin sheet) has no hint. #63 waits on Burooj saying what "alive" means.
- The preset tiles on Home start a Timer with that mix only; they are not sits. #64.
- A fresh install has nothing to Continue or Pin, so Home is mostly tiles. Not looked at yet; it is the first thing a new person sees after the intro.

## 2. Continue a course

1. Home › Continue card. Tap plays the next session. Long-press or ⋮ opens Open course · Restart · Remove from Continue. (#106, on develop)
2. "Next session" is the same everywhere: the most recently left partway session, else the first unfinished one. The label reads "Resume: Lesson 2". (#105, on develop)
3. Open course lands on the course page. The header has a full-width Play / Resume naming the next session; under it Library · Pin · Share · ⋮. (#120, on apk)
4. The bottom bar is Back only; Resume joins it once the header's Play has scrolled away. (#120, on apk)

Friction that remains:
- The Play row on long real titles ("Practising the Jhānas", 32 sessions) and the bottom-bar Resume on fast flings are device checks.
- Progress is hidden until the first play; a finished course shows "Play again". These are owner-default choices, open to overruling after the test.
- The header ⋮ still lists Save to Library, which the header row also shows. Open question in #115.
- Library has no "In progress" section by decision (Continue covers it). A course dropped with Remove from Continue is found by name only.

## 3. Open a course or an episode

1. From any row, tap opens the page; ⋮ or long-press opens one shared actions sheet: Play · Add to playlist · Save · Download · Mark as played · Go to teacher · Share, with what does not apply hidden. (#107, on apk)
2. Course rows carry the recording date ("Mar 5", with the year when the course spans years). A retreat's days are bordered groups with a "Day 3 · Sun, Apr 16" label. The course's own teacher is not repeated on each row (matched by id first). A kind chip shows only where a course mixes practice and listening. (#121, on apk)
3. Episode page: cleaned title, an "In / Part of ⟨course⟩" line, a labelled "Play · 44 min", the description with Show more, Share hidden for imports, ⋮ for the rest. Guide and length pickers are chips, shown only when there is a real choice. (#110, on develop; #122, on apk)
4. A YouTube channel is a teacher: its avatar shows on cards and in the course header, a Teacher tab exists, descriptions fill in for playlists and videos. Go to teacher opens the channel page. (#111, on apk)

Friction that remains:
- Real YouTube extraction, the channel avatar against the pin disc, and the Kotlin changes have not run on a network or been compiled outside CI: device check.
- Day boxes under the pinned tabs, ripple at box edges and a month-long retreat are device checks (#121).
- Talks and practice should be able to start differently, for example talks at 1.5× or 2× playback speed. The decision (separate per-kind defaults) is made; whether speed is one of those defaults is waiting on owner.
- Nothing on a row says it can be long-pressed. The hint belongs to the tour (#87).

## 4. Pin

1. Pin is a pin icon, never a heart. It is on the course header, the player and the Library ⋮ sheet, and in the sheet on any row. (#117, on apk)
2. Courses, playlists and single sessions can be pinned. Home shows three; the rest are under "See all". The three-pin limit is gone. Old favourites become pins once, at the update. (#117, on apk)
3. Unpin on a Home card gives an Undo snackbar. (#106, on develop)
4. Adding something to Home is pinning; there is no Add on Home. (#123, on apk)

Friction that remains:
- Without a Favourites screen, "everything I pinned" is reached through Home › Pinned › See all. Whether that is findable is a device check.
- The legacy `favorites` deep link now opens the pins list.

## 5. Library and import

1. The top bar holds "+" and the You button. "+" opens a sheet with Import and New playlist. (#123, on apk)
2. The ⋮ sheet on any Library entry offers Pin (not on a teacher or channel) and Remove. (#117 with #107, on apk)
3. Teachers (Dharma Seed or YouTube) are saved from their page and found under Library › Teachers. (#111, on apk)
4. The chip row fades at its scrolling edge, so a cut-off chip reads as scrollable. (#114, on develop)

Friction that remains:
- Library still files each entry whole under Practice or Talks, so a course that mixes both sits under one. #80: sections by form (Playlists · Courses · Sessions) with Practice/Talks filter chips is the direction; the layout is waiting on owner.
- A chip is still partly cut off at rest. Whether all chips must show at once is the owner's call (#92, #114).
- No sound-preset row in the "+" sheet until presets become sits. #64.
- Per `interaction-model.md`, removing an import has no Undo, and rename and move are silent. Not re-checked in this pass.

## 6. Timer and Customize

1. Home › Timer. Customize opens on four slot tiles: Sound · Bells · Rhythm · Length. Opening a tile scrolls to its section. (#108, on apk)
2. Bells: the countdown is part of the starting bell, the silence part of the ending bell. Flow is gone. Autoplay is a button in the player, under the transport. (#108, on apk)
3. Rhythm: Rate · over · Ends at in one row of wheels, Ends at dimmed when the ramp is Off. (#124, on apk)
4. The wheels have gutters of at least 28 dp (right-biased) so the sheet can be scrolled by thumb beside them. A wheel change shows an in-sheet Undo bar for 5 s. (#124, on apk)
5. Start.

Friction that remains:
- On the Timer the duration is still one row among the others, not the hero. #65.
- A sit (length + bells + pulse + mix) cannot be kept. There is no "Save as shortcut". #64, after #75 settles the defaults.
- Customize strings are still partly hard-coded English. #74 goes last in the Customize chain.
- Practice and Talks defaults stay separate (decided). Per-course overrides stay. #75 as written (one set) no longer applies; see `friction.md`.
- Wheel gutters, the 5 s Undo, Autoplay with the screen locked, and the tile open animation are device checks.

## 7. Sounds and the mixer drawer

1. The Sounds tab: Clear in the open dock header empties the mix, with Undo. The Swell chip has a caption, "Rises and falls slowly". (#103, on develop)
2. One mixer drawer, a 94% bottom sheet, opens from the player, Customize and the Timer. Choosing a sound auditions it: the drawer is silent until a sound is tapped, then plays at the chosen kind's session level. The Sounds tab keeps its "Plays under practice / talks" lines. (#126, on apk)
3. A volume change made in a sit sticks after Done. Opening the talks drawer during a practice sit changes only the talks volume.

Friction that remains:
- Update vs Save as new for a loaded preset is not built. #68, after #64.
- Drone is a single root note. #69. Shared per-sound controls wait on what "customisable" means. #71.
- Chimes, footstep and heartbeat are not real samples. #76 (content).
- Audition loudness and fade-in, double-starts when changing sound in a running sit, the dock's nested drag in the 94% sheet and the Sounds foreground notification are device checks.
- Sounds is still a tab. Folding it into Explore waits on the drawer being proven on a device. #89.

## 8. You page and Settings

1. The 5th tab is Settings. Stats and history are on the You page, opened from the top-right button on Home, Library and Settings. (#113, on apk)
2. Settings has lost Default guide name, Default duration and App icon. "Edit stats" now reads "Session history"; headings are sentence case. A switch controls automatic update checks. (#104, on develop)
3. About › "What Meditejo is" reopens the intro. (#125, on apk)

Friction that remains:
- How the You button reads beside each page's title, and whether the tab swap is clear, are device checks.
- The two per-kind "sounds & cues" rows in Settings stay (per-kind defaults are decided).

## Not yet walked

Explore and search, the player as a whole, the end screen, downloads and the Home widget have no step list: the pass touches them only through #92's Explore-search item and #86 (timer sessions show the day's mark, breathing; waits on #63). Walk them once the APK has been tested.
