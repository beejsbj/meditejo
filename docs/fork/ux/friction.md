# Friction: what is still in the way, ranked

The UX pass (BRIEF decision 23), tracked in #88. Written on 2026-11-03 against `develop` at `1b30cb2c` and `apk/ux-pass` (PR #115, head `a44ef9ec`). The journeys that these points come from are in `journeys.md`; the starting lists are `interaction-model.md` and `field-notes-0.1.4.md`.

**Status words**

| Status | Meaning |
|---|---|
| **fixed on develop** | Merged. Checked by tests and headless screenshots; device check noted where there is one. |
| **on apk** | In `apk/ux-pass` (PR #115), not merged to `develop`, **not yet tested on a device**. Each source PR merges on its own once the owner approves. |
| **open** | No PR yet, or a PR that does not close it. |
| **waiting on owner** | Needs a decision from Burooj before anyone builds. |

**Ranking.** Frequency (how often one person meets it) × cost (what it does to a sit or to trust in the app). Rank 1 is the worst. "v1?" is a proposal for Burooj to overrule: **must** blocks v1, **should** is wanted but can slip, **later** can wait. Nothing in the table is claimed as device-verified; the *Device check* column says what only a phone can settle.

## Ranked list

| # | Friction | Issue / PR | Status | v1? | Device check |
|---|---|---|---|---|---|
| 1 | Course ▶ and Home Continue named different next sessions | #90 / #105 | fixed on develop | done | Play the shown session from both |
| 2 | Course page: actions in a bottom bar next to Back; progress and header crowded | #81 / #120 | on apk | must | Play row on long titles; Resume on scroll; tab switching deep in a course |
| 3 | Pinning, Favourites and the Library were three ideas | #79 / #117, #81 / #120 | on apk | must | Old favourites become pins once; "See all" findable |
| 4 | Customize grew by accretion (countdown, silence, Flow, Autoplay) | #72 / #108 | on apk | must | Autoplay button and locked-screen autoplay; tile animation |
| 5 | Sound has several doors (Sounds tab, Background sound, bell/pulse) | #66 / #126 | on apk | must | Audition level and fade; no double-start; nested drag |
| 6 | Wheels in a scrolling sheet catch the thumb and save at once | #91, #73 / #124 | on apk | must | Gutter feel; 5 s Undo long enough |
| 7 | Long Home/Continue cards clipped; no way to open the course from Continue | #61 / #106 | fixed on develop | done | Menu and ⋮ feel on a real card |
| 8 | The Timer buries its one job: duration is an accordion row | #65 | open | must | Thumb feel of a big dial |
| 9 | A sit (length + bells + pulse + mix) cannot be kept; Home preset tiles imply it can | #64 | open | must | — |
| 10 | Episode page: pickers shown for one option; no description, no course link | #84 / #110, #122 | #110 fixed on develop; #122 on apk | must | Show more; "Part of" back behaviour |
| 11 | Episode ⋮ was one item that opened a second tall sheet | #83 / #107 | on apk | must | Long-press vs scroll; haptics |
| 12 | Rows had no date; retreat days were headings, not structure | #82 / #121 | on apk | should | Day boxes under pinned tabs; ripple edges |
| 13 | Settings still had Medito leftovers; no way to stop update checks | #77, #93 / #104 | fixed on develop | done | — |
| 14 | First launch: a questionnaire that belonged to Medito | #87 / #125 | on apk (intro); tour open | must (intro), later (tour) | Fresh install; upgrade goes to Home; battery page on Samsung |
| 15 | App reopened on the last tab | #92 / #109 | fixed on develop | done | — |
| 16 | "You" tab mixed stats, history and Settings access | #78 / #113 | on apk | must | You button beside each title |
| 17 | Add on Home meant Import; Library had no obvious "+" | #62 / #123 | on apk | should | "+" and You reachable together; TalkBack label |
| 18 | YouTube channels were not teachers; no avatar or descriptions | #85 / #111 | on apk | should | Real network extraction; avatar vs pin disc; Kotlin compiles |
| 19 | Sounds: no Clear; "Drift" unexplained | #67, #70 / #103 | fixed on develop | done | — |
| 20 | Sounds: Save always makes a new preset | #68 | open (needs #64) | should | — |
| 21 | Share text put the link where the title goes | #112 | fixed on develop | done | Share a pack and a track |
| 22 | Mark does not answer touch; long-press unhinted | #63 | waiting on owner ("alive") | should | Motion feel; reduced motion |
| 23 | Library files a mixed course under one kind | #80 | waiting on owner (layout) | should | — |
| 24 | Library chip row cut off at rest | #92 / #114 | fade fixed on develop; rest waiting on owner | later | Fade reads as scrollable |
| 25 | Remaining #92 items: Explore search blank state, preset tile subtitle, course header polish, sound-credit spacing | #92 / #109 (credits) | credit spacing on develop (device check); rest open | should | Credits at S23+ font scale |
| 26 | Customize strings hard-coded English | #74 | open (last in chain) | should | — |
| 27 | Per-kind defaults vs one set | #75 | reversed by the owner: kinds stay separate; per-course overrides stay | decision recorded; rewrite or close | — |
| 28 | Per-kind playback speed (talks 1.5×/2×) | no issue | waiting on owner | later | — |
| 29 | Timer session in the player shows no mark | #86 | open (needs #63) | later | Breath rate |
| 30 | Drone is one note; sound controls differ per sound | #69, #71 | #69 open; #71 waiting on owner ("customisable") | later | Hearing a chord |
| 31 | Chimes, footstep, heartbeat are not real samples | #76 | open (content) | later | Hearing them |
| 32 | Sounds is a tab | #89 | open, blocked on #66 on device | later | Is a one-tap sounds path enough? |

## What v1 must fix (proposal)

Everything marked **must** is either already on `apk/ux-pass` waiting for the owner's device test (2-6, 10, 11, 14, 16) or is one of two open structural items: **#64 and #65** (the sit and the Timer; one story). The rest can ship after v1 without making the app feel half-done.

Reasoning in one line each:
- 2–6, 10, 11, 14, 16 are the pages and sheets a person meets on every launch; they changed together and should be tested together.
- #64/#65 are the main complaint in `field-notes-0.1.4.md`: the Timer is the daily path and the app cannot keep a sit.
- #63 and #80 are *should*, not *must*: neither blocks a sit, a course or a talk. Both are decisions only Burooj can make.

## Waiting on owner

| Question | Issue | Options on the table |
|---|---|---|
| What does "alive" mean for the mark? | #63 | Tap = one slow breath; day's name on first open; one-time long-press hint (explore on the phone together) |
| What does "customisable" mean for sound controls? | #71 | User-set ranges; which controls show; or a fixed shared spec only |
| Library layout | #80 | By form with Practice/Talks chips (direction chosen); how mixed courses and the "+" fit still open |
| Playback speed per kind | — | Talks default 1.5×/2×, practice unchanged; where it lives (Customize defaults, player, or both) |
| Do the owner-default choices on the APK stand? | #115 | Listed under *Owner-default decisions* in PR #115 (#81, #82, #84, #62, #73/#91, #87, #66) |

## Not friction, but recorded

- PRs #49 (Extend) and #51 (Design your own bell) are parked. Anything that touches `customize_sheet.dart` is built without them.
- The Riverpod paused-subscription crash (#116) and the Widgetbook and screenshot-harness flakes (#118, #119) were fixed on `develop`; they were test/runtime health, not UX.
