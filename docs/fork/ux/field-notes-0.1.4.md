# Field notes: Burooj on 0.1.4

Tracked in issue #88 (one issue per change, label `ux-pass`). Burooj's first pass through 0.1.4 on the S23+ (2026-10-27), with what the code does behind each note and a first proposal. Code facts are from `develop` at `1f0b81cc` (0.1.4 plus release tooling). Proposals are for discussion; the ranked list goes to `friction.md` once we've agreed on them.

## The threads under the notes

Most notes are symptoms of four things.

1. **Sound has four owners.** The mix (Sounds tab), Background sound (Customize), "Under sessions" (Sounds tab, same state as Background sound), and bells and pulse (Customize, a different engine). The player reaches two of them by two buttons that open two different UIs. The engines should stay separate (cues are scheduled natively, to the sample), but the user should meet one surface.
2. **There's only one kind of preset in the code, but the app implies two.** A preset is a sound mix. Home's preset tiles are the newest two mixes, each starting the Timer with whatever bells and length the Timer last had. A "sit" (length, bells, pulse, mix, saved together) doesn't exist, but the tiles read as if it does.
3. **Customize grew by accretion.** Countdown is separate from the starting bell, Extend is separate from the ending bell, Autoplay (about the queue) sits beside the bells (about the sit), and "Flow" holds whatever was left over. On the Timer, the one thing the screen is for, the duration, is one accordion row among the rest.
4. **Medito-era scaffolding is still in Settings and on pages.** Default guide name, Default duration, the App icon row, back and actions in a bottom bar, and favourites only reachable from Settings.

## Home

| Note | What the code does | Proposal |
|---|---|---|
| The mark could be more alive than the breathing blob. | 60 s loop: the blob turns and morphs, a ring and dot counter-rotate, and the core breathes six times a minute (`branding/meditejo_mark.dart`, `mark_painter.dart`). It changes daily. Long-press opens the pin sheet (`home_mark_sheet.dart`). | Let it answer touch: a tap sends one slow breath through it. Show the day's name for the mark under it for a moment on first open each day. Hint the long-press once. Don't make it busier at rest; quiet is the point. |
| Add is in a weird place; I expected it to add quick tiles. | Add is a full-width pill under the shortcut tiles and opens **Import** ("Add to your library"), not a tile editor (`shortcuts_section.dart:109`). Tiles can't be added or edited; the layout screen only toggles and reorders sections. | `+` top right. It opens a small sheet: **New shortcut** (save a sit, see Timer) and **Import to library**. Library gets its own `+` for import. |
| Hold Resume or a pinned card for a menu; I wanted the course from a Resume. | No long-press anywhere on Home cards. Continue only plays; the course name is just subtitle text. Pinned's pin icon unpins in one tap. | Long-press (and ⋮) on Continue: **Open course**, Restart, Remove from Continue. On Pinned: Open, Play next, Unpin (with Undo). Small fix, high value. |

## Art and sources

| Note | What the code does | Proposal |
|---|---|---|
| Are we using our generated art instead of the source art? | Rule (`widgets/cards/card_art.dart`): curated art for a shipped starter id first, then the source's picture (feed artwork, YouTube thumbnail), then art generated from the id. **Dharma Seed has no course art**; its "cover" is the teacher's photo, so DS gets generated art with the photo as an avatar. | Keep the rule. It's only DS and the starters that you're seeing generated art on. |
| I like the teacher circle at the bottom right. | The teacher photo sits **bottom-left**. The bottom-right disc is the pin mark (`course_card.dart:216`). | Worth a look on the phone: if you meant the left one, fine; if the right one reads as a person, the pin mark is unclear. |
| Could YouTube channels get the avatar too? A playlist description as the summary? A summary for videos? | The YouTube extractor stores the channel name but **no avatar and no playlist description**; a video description only once a video is fully resolved (`youtube_source.dart:165, 358-391`). Podcasts store author and description. | Yes to the avatar and the descriptions; it's extractor work (pigeon fields plus DB columns), a medium change. "Summary" = the source's own description, not a generated summary: no network AI in a FOSS offline-first app. |

## Course and episode pages

| Note | What the code does | Proposal |
|---|---|---|
| Episode page layout could be better. | TrackView, top to bottom: 16:9 cover, title, meta line, description, guide/duration dropdowns, Add to library, Play, From the beginning; Share / Add to playlist / ♥ in the bottom bar. | Cover, title and meta, then **Play** (with the duration choice inline as chips if there's more than one), then the description. Save, Playlist and Share become one row of icon buttons under Play. |
| The episode ⋮ only has Add to playlist, and it's weirdly larger. | A popup with one item, which then opens a tall titled sheet (two steps for one action). | Row ⋮ opens one sheet: Play, Add to playlist, Save to library, Download, Mark as played, Go to teacher, Share. |
| Dates as headings with episodes under them; the date belongs in the row. | Grouping starts at 8+ dated items over 2+ dates (`pack_view.dart:466-557`). A podcast gets one heading per release. | Date in the row's meta line. Keep headings only for retreats ("Day 3 · Wed"), where the day is the structure. |
| Is a dropdown the best UX? | The only dropdowns are TrackView's guide and duration pickers. | Chips (there are rarely more than 4 options). |
| The course menu at the bottom beside Back is weird. | Every page uses Medito's bottom action bar: Back left, Share/⋮/♥ right. | Structural: an M3 top app bar (Back top-left, actions top-right), keeping the primary action (Play) low and reachable. The cost: one-handed reach on a big phone, and it touches every page. |

## Library

| Note | What the code does | Proposal |
|---|---|---|
| Courses sit under Practice even when they contain talks. | Practice/Talks is per library **entry**: a course lands whole in one section. DS retreats are always Practice. Rows on the course page still show each recording's own kind. | Two options. **A:** sections by form (In progress · Playlists · Courses · Sessions), with Practice/Talks as filter chips that filter by track, so a mixed course shows under both. **B:** keep kind sections, and let a mixed course appear in both. I lean A. It's a change to decision 8's shape, so it's your call. |
| Favorites should be in Library. | Only via Settings › Library & downloads › Favorites. | A Favorites row in Library (or a chip in A). |

## Timer

| Note | What the code does | Proposal |
|---|---|---|
| The main timer shouldn't collapse; it should be the hero. | The Timer embeds the whole Customize sheet; Duration is one accordion row (Time leads for a timer). `timer/widgets/timer_duration_wheels.dart` is built and unused. | The duration is the screen: a big open dial (or the unused wheels) centred, with the bells, rhythm and sound as one line of summary chips under it, and Start. "Save as shortcut" lives here; that's where a sit is made. |

## Sounds

| Note | What the code does | Proposal |
|---|---|---|
| Like the `+` to add. Need a way to clear what's on deck; maybe the chevron becomes ×, drag still opens. | No clear-all in the UI (`clearMix()` exists, unused). The dock has play/pause, Stop and the chevron. | Add **Clear** to the open dock's header, with Undo. Keep the chevron: a lone drag handle is hard to discover, and × on a dock reads as "close". |
| Presets: Save mix should be two buttons, Update this preset or Save as new. | Editing a loaded preset only offers "Save mix", which always saves a **new** preset. There's no update or rename. | Agreed: **Update "Night"** and **Save as new**. Built-ins only get Save as new. |
| Why can't I mix notes for the drone? | One drone per mix (one layer per sound id), one root note; it already sounds root + octave + fifth (+ more partials for warm/bright). | Let the Root chips multi-select (up to 3) into a chord. That's cheaper and clearer than allowing two drone layers. |
| How is "Under sessions" different from Customize? | It's the same state. The two switches are Customize › Background sound's on/off for each kind. | Remove the switches from Sounds. Show one line, "Plays under practice sessions", that opens the same chooser. |
| What is Drift? | Each layer's level slowly swells between 55% and 100% over 40–90 s, so a long sit doesn't sound static. | Rename it **Swell**, with the caption "Rises and falls slowly". |
| Why doesn't binaural beats use the dial and range? When is that decided? | Each generated sound's editor is hand-built: noise gets Colour + 10 band sliders; drone gets Root/Timbre/Movement; binaural gets Tone and Beat sliders plus a legend. Recordings only get volume. | Binaural: delta/theta/alpha/beta chips for the beat, fine slider under them. More broadly, a shared per-sound control vocabulary so every editor looks like the same instrument. |
| Isn't rhythm part of Sounds? Bells too? One system? | Separate engines: the mix is a Dart mixer; bells and pulse are a native scheduler (`CueEngine.kt`, `CueScheduler.swift`), all from rendered WAVs. | See below. |

### One system?

**Recommendation:** one surface and two roles. The mix is **atmosphere**: it can play on its own and be reused across sits. Bells and pulse are **the sit's shape**: they only mean something inside a timed session. Put the mix editor in one drawer and use that same drawer everywhere (the Sounds tab is its full-screen form; Customize's Sound row and the player's Sounds button both open it). Bells and pulse stay in the sit's settings.

The alternative is to fold bells and pulse into Sounds. That's simpler to name, but it puts things that only work inside a timer onto a tab that plays without one.

## Customize

| Note | What the code does | Proposal |
|---|---|---|
| Chime should sound like chimes, not one sharp tone. | `bell_chime.wav` is one synthesized struck bar (4 partials at 1568 Hz), rendered offline. | Rename it "Bar" or "Tingsha-high", and add a real wind-chime sample (several struck tubes). |
| Rhythm's footstep sounds like a hi-hat; heartbeat is synthetic. | All pulse sounds are synthesized offline (`generate_pulse_sounds.py`). | Source CC0 recordings (Freesound CC0, or record our own), with the licence in `assets/audio/NOTICE`. Content task, not code. |
| Rate, Slow down over and Ends at as three wheels in a row. | Already wheels, but two rows: Rate + Slow down over as a pair, then Ends at on its own row, shown only once a ramp is set (`customize_sheet.dart:700-730`). | Agreed: all three in one row, in reading order Rate · over · Ends at, with Ends at dimmed while the ramp is Off rather than appearing and disappearing. |
| Collapsed pulse row: the arrow from rate to ends-at; put the time on the arrow. | Folded summary: "Heartbeat · 60→40 BPM". | `60 ⟶ 40 BPM` with "over 20 min" set small above the arrow. |
| Countdown belongs in the starting bell; Extend with silence is really the ending bell. | Countdown and Extend sit under Time; the bells under Bells. | Agreed. Starting bell = countdown + bell; Ending bell = optional silence + bell. Time then holds only Duration. |
| Sound selection doesn't play, can't multi-select; Edit mix goes to a different-feeling page. | Background sound is a single-choice chip list: Off / Current mix / each preset / each single sound. "Edit your mix in Sounds" pushes the Sounds page. | The one drawer (above). Choosing **is** editing the mix, it auditions, and it multi-selects because it's the mixer. |
| Why is Hide these settings under Flow? | Flow = Autoplay + Hide; no rationale in code. | Hide becomes the sheet's footer ("Show before each session" switch). Autoplay goes to the player. Flow disappears. |
| Autoplay makes more sense in the player. | Customize › Flow, not shown for a timer. | Agreed: a queue/next control in the player, for course sessions. |

## Settings / You

| Note | What the code does | Proposal |
|---|---|---|
| Why "You" and not Settings? | Decision 18: stats and settings under one tab. No rationale for the word. | Keep "You" only if it's about you: stats, history, your mixes and sits, favourites. Otherwise call it Settings. I lean towards keeping You and moving Settings behind a gear on it. |
| What is Default guide name? | Medito's: remembers the last voice picked, so a track with several voices can skip its page. Meditejo's sources almost never have several. | Remove from Settings. |
| What is Default duration for? Why a range? | One value (the slider runs 1–60). It picks the closest-length file for multi-length tracks. **Not the Timer's length.** | Remove (Medito leftover). The Timer remembers its own length. |
| Why Customize per Practice and per Talks? Could it be one setting? | Decision 8/17: different background-sound defaults per kind. Since 17 both start silent, so the split mostly carries bells now. Per-course overrides exist too. | One set of defaults plus per-course overrides, unless you actually want different bells for talks. **Question for you.** |
| App icon is shown but can't be changed. | Fixed by decision 21; the row is information only, with no tap. | Remove it. The daily mark and palette rows (Appearance) are the real choices. |

## Player

| Note | What the code does | Proposal |
|---|---|---|
| Sounds from its own button and from Customize, as different menus. | The Sounds button pushes the full Sounds page; Customize › Background sound is the chip chooser. Same state. | One drawer (Sounds, above). |
| The timer player is boring; the mark should be there, animating, pushing the buttons down. | A timer plays over live generated art (`da6367eb`). | Yes: the day's mark, large, breathing at the pulse rate if there is one, otherwise the six-a-minute breath. This joins Home and the sit visually. |

## Questions this raises

1. Do you want different bells or sounds for talks than for practice? If not, Customize defaults collapse to one set.
2. Should a Home tile save the whole sit (length, bells, pulse, mix)? I think that's what the tiles already promise.
3. Back at the bottom: does it bother you everywhere, or mainly on the course page where it shares a bar with the ⋮?

## Burooj's answers (2026-10-28)

- **Presets:** every preset should be a timer preset (a sit), and the timer should allow "infinite" so a sound mix on its own is a sit too. My reading: the stopwatch already *is* an infinite timer, so Timer and Stopwatch merge into one duration that runs up to ∞. Mixes still exist as the ingredient a talk plays under. "Preset" means a sit.
- **Practice vs Talks defaults:** no difference wanted. What might differ is which preset plays under a particular course, and that's what the per-course override already does. So it's one set of defaults plus per-course overrides.
- **"Under sessions":** reaching the same setting from more than one place is fine, but this one is confusing and doesn't line up. Replace it.
- **Per-sound controls:** make them customisable, with one shared vocabulary.
- **Drone chord, Swell rename, removing Default guide name, Default duration and App icon:** agreed.
- **Leftovers:** reimagine or discard each one; don't keep any as it is.
- **Sources:** keep the art hierarchy. A YouTube import should carry the channel as its "teacher" (avatar included), and import the playlist, channel and video descriptions.
- **Retreat days:** not headings at all; visual groups instead, like a bordered box with the day as small text inside.
- **Bottom bar:** follow M3 Expressive. Back at the bottom is fine. The problem is Share, ⋮ and ♥ sitting in that bar instead of with the course's own actions beside Pin, and Pin should be an icon, not a three-word sentence.
- **Sound, one drawer:** agreed exactly.

## Screenshots: course page and episode page (0.1.4)

**Course page (Practising the Jhānas):**
- The header art is cropped to a strip behind the title.
- The meta line says "32 talks" for a mix of talks and guided meditations (Dharma Seed's word for any recording).
- "32 of 32 left" is a sentence where a progress bar would do.
- "In library" (outlined button) and "Unpin from Home" (text row) are two ways of showing a toggle.
- The ▶ FAB straddles the panel edge and is clipped at the right.
- Every row repeats "Rob Burbea" although the course has one teacher.
- The kind overline (TALK / GUIDED MEDITATION) is loud for metadata.
- Share, ⋮ and ♥ live in the bottom bar.
- Favourite, In library and Pin are three different ways to keep the same thing.

**Episode page (Vervaeke, YouTube):**
- The raw YouTube title runs to four lines, including the playlist name and "Livestream Mon-Fri 09:30 EST".
- The channel name appears three times: subtitle, attribution link, and a *guide picker*.
- The guide and duration pickers each have one option but still look like inputs (Medito's multi-voice pickers).
- There's no description, because the importer didn't store one.
- There's no way to reach the course.
- The Play pill has no label.
- Below Play there's dead space.
