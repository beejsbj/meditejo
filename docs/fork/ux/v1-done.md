# v1 done: the UX pass

The UX pass (BRIEF decision 23), tracked in #88. Written 2026-11-03 against `develop` at `1b30cb2c` and `apk/ux-pass` (PR #115, head `a44ef9ec`). Rankings and reasons are in `friction.md`; the walks are in `journeys.md`.

**The UX pass is done for v1 when** every item marked *blocks v1* below is merged to `develop`, the gating device checks pass on Burooj's S23+, and the owner questions that gate a *blocks v1* item are answered. Items marked *can wait* may ship after v1. "Blocks" and "can wait" are a proposal; Burooj decides.

Legend: `[x]` merged to `develop`. `[~]` on `apk/ux-pass`, not merged, **no device test yet**. `[ ]` open. `[?]` waiting on owner. Merge policy: simple UI fixes merge to `develop` after review and green CI; bigger changes are held on `apk/ux-pass` until Burooj has tested the APK, then each source PR merges on its own. Do not merge PR #115 itself.

## Checklist

### Quick fixes
- [x] #90 Course ▶ and Home Continue agree on the next session. PR #105. *blocks v1*
- [~] #91 Wheel gutters and Undo. PR #124 (with #73). *blocks v1*
- [ ] #92 Phone-tour polish. *can wait* except as listed:
  - [x] Open on Home (#109). Sound-credit spacing (#109) needs a look at S23+ font scale.
  - [x] Pinned count never clipped; Library chips fade at the edge (#114). A chip is still partly cut off at rest: `[?]`.
  - [ ] Explore search blank state; preset tile subtitle; course header and tabs (the last folds into #81, `[~]` on #120).
- [x] #61 Long-press and ⋮ on Continue and Pinned. PR #106. *blocks v1*
- [x] #67 Clear the mix, with Undo. PR #103.
- [ ] #68 Update preset vs Save as new. Needs #64. *can wait*
- [x] #70 Drift to Swell. PR #103.
- [~] #83 One actions sheet on every row. PR #107. *blocks v1*
- [x] #77 Settings: Medito leftovers removed. PR #104.
- [x] #93 Switch for automatic update checks. PR #104.
- [~] #84 Episode page. Pickers bug fixed on develop (#110); layout, "Part of", description on apk (#122). *blocks v1*

### Structural
- [ ] #64 Presets become sits (duration to ∞, bells, pulse, mix). *blocks v1*
- [ ] #65 Timer: duration as the hero. Needs #64 for Save as shortcut. *blocks v1*
- [~] #66 One mixer drawer everywhere. PR #126. *blocks v1*
- [~] #72 Customize regroup. PR #108. *blocks v1*
- [~] #73 Rhythm wheels in a row. PR #124.
- [ ] #75 Customize defaults. **Reversed:** Practice and Talks keep separate defaults, per-course overrides stay. The issue as written (one set) should be rewritten or closed; nothing to build unless the owner wants a migration. Not a v1 blocker.
- [ ] #71 Shared sound-control vocabulary. `[?]` on what "customisable" means. *can wait*
- [ ] #69 Drone chord. *can wait*
- [~] #81 Course page: actions with the course. PR #120. *blocks v1*
- [~] #82 Course rows: date, retreat day groups. PR #121. *can wait* (merge with #81 if the device test is clean)
- [~] #85 YouTube channel as teacher. PR #111. Includes Library DB schema 6. *blocks v1 if YouTube import ships in v1*
- [ ] #86 Player: the mark for timer sessions. Needs #63. *can wait*
- [~] #62 Home: no Add; Library "+". PR #123. *blocks v1*
- [ ] #63 Home: the mark answers touch. `[?]` on "alive". *can wait*
- [ ] #74 Customize strings to l10n. Last in the Customize chain. *blocks v1* (a hard-coded English sheet in a de/es app)

### Content
- [ ] #76 Real samples for chimes, footstep, heartbeat. *can wait*

### Burooj to decide
- [~] #78 You page, 5th tab is Settings. PR #113. Decided; built on apk. *blocks v1*
- [~] #79 Pin replaces Favourites. PR #117. Decided; built on apk. *blocks v1*
- [?] #80 Library layout. Direction chosen (by form, Practice/Talks as chips); layout waiting. *can wait*
- [~] #87 First launch. Intro on apk (#125). The tour is open: needs #63. #87 stays open. Intro *blocks v1*; tour *can wait*.
- [ ] #89 Sounds into Explore. Decided; blocked on #66 being proven on a device. *can wait*

### Not in the #88 list but tracked
- Per-kind playback speed (talks 1.5×/2×): `[?]`, no issue yet. *can wait*
- [x] #112 Share text arguments. [x] #116 Riverpod paused-subscription fix. [x] #118, #119 Widgetbook and screenshot-harness health.

## Counts (2026-11-03)

| State | Issues |
|---|---|
| Merged to `develop` | #61, #67, #70, #77, #90, #93; parts of #84 (#110) and #92 (#109, #114) |
| On `apk/ux-pass`, awaiting device test | #62, #66, #72, #73, #78, #79, #81, #82, #83, #84 (rest), #85, #87 (intro), #91 |
| Open | #64, #65, #68, #69, #74, #76, #86, #87 (tour), #89, #92 (rest), #75 (rewrite or close) |
| Waiting on owner | #63, #71, #80, per-kind playback speed |

## Gating device checks (before the APK PRs merge)

These are the checks only a phone can settle. The full list, with each item, is in PR #115 under "Needs device check (combined)"; below is the gate, grouped by what could stop a merge.

**Gate A: nothing loses data or breaks a sit**
- Upgrade from an existing install lands on Home with no intro; a fresh install shows the intro with no Home flash. (#125)
- Old favourites appear as pins, once, with no hearts. (#117)
- The Library keeps its entries across the DB schema bump. (#111)
- Autoplay moves to the next session with the chosen pause, including with the screen locked. (#108)
- A volume change in a sit sticks after Done; no gap or double-start when changing sound in a running sit; the drawer is silent until a sound is tapped. (#126)
- The APK workflow's `YouTube native unit tests` step passes (the Kotlin was never compiled before that run). (#111)

**Gate B: the pages work by thumb**
- Course page: Play row on long titles, Resume on scroll, tab switching deep in a long course, Play again. (#120)
- Wheel gutters: the sheet scrolls beside a wheel without spinning it; the 5 s Undo is long enough. (#124)
- Long-press versus scroll on rows, and the haptics. (#107)
- Day boxes slide under the pinned tabs; ripples stay inside box edges. (#121)
- The You button and "+" in each top bar: reachable, not crowded. (#113, #123)

**Gate C: real content**
- Import a real YouTube playlist (e.g. Vervaeke): channel avatar, descriptions, save the channel, no bot check from the background fill, playback stays responsive. (#111)
- A month-long retreat, a podcast and a daylong read correctly as course rows. (#121)
- Episode titles clean on real courses; Share hidden for imports. (#122)
- Audition loudness and fade-in at the chosen kind's level. (#126)
- Samsung battery dialog and the one-time battery offer. (#125)

## Owner-default decisions to confirm or overrule after testing

Taken so work could continue; listed in PR #115 under "Owner-default decisions": #81 (Play row, Resume on scroll, progress hidden until first play, "Play again"), #82 (chip wording, no date in day boxes), #84 (the "Part of" line pops back), #62 (New playlist only in the "+" sheet), #73/#91 (Undo scope, gutter width), #87 (copy, battery timing), #66 (silent drawer, 94%).

## After v1

Per-kind playback speed, #63, #71, #69, #76, #80, #86, #89, #82 if not merged earlier, the tour, and the parked PRs #49 (Extend) and #51 (Design your own bell).
