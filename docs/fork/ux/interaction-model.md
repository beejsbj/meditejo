# Interaction model: what every card and row does

The UX pass (BRIEF decision 23). The "now" half: what the code on `develop` does, found by reading the code. Written against a pre-0.1.4 tree; the rows that 0.1.4 changed (the mark, Customize) were corrected after rebasing onto `1f0b81cc`. Burooj's first phone pass on 0.1.4 is in `field-notes-0.1.4.md`. Paths are relative to `lib/`. Strings come from `l10n/app_en.arb` unless marked hard-coded. The proposals live in `friction.md` once we have walked the journeys with Burooj.

## The shape of it

Three verbs carry almost everything, and the app uses them inconsistently:

| Verb | Where a tap does it |
|---|---|
| **Play now** | Continue (Home), In progress (Library), a course's ▶, Timer and preset tiles (Home), a preset card (Sounds) |
| **Open a page** | Course cards and rows everywhere, **single and session rows everywhere** (TrackView, then ▶), teachers, Pinned |
| **Change a collection** | A sound card (toggles a layer in the mix), ⊕ (add to library), Save/In library (toggle), pin, add to playlist |

Long-press is almost unused: only user presets (delete), History rows (delete) and the hidden Debug entry on the You header. Swipe exists only on Downloads. Both are undiscoverable, so treat them as absent.

## Home

| Element | Code | Tap | Long-press | ⋮ | Feedback |
|---|---|---|---|---|---|
| Mark | `views/home/home_view.dart:159` | — | Pin / unpin sheet (`branding/home_mark_sheet.dart`) | — | Not discoverable: no hint on screen |
| Customize (tune icon) | `home_view.dart:69` | Home layout screen | — | — | — |
| Update notice: View / ✕ | `home/widgets/update_notice.dart:34` | You tab / hide for this version | — | — | No Undo |
| Continue card (≤3) | `home/widgets/continue/continue_section.dart:129` | **Plays** (`startContinueItem`); the Resume/Start button does the same | — | — | First card is filled with a filled button; the rest are tonal |
| Timer tile | `home/widgets/shortcuts/shortcuts_section.dart:42` | Pushes the Timer screen | — | — | — |
| Sounds tile | `shortcuts_section.dart:54` | Switches to the **Sounds tab** | — | — | — |
| Preset tile (≤2) | `shortcuts_section.dart:64` | **Starts a Timer session at once**, with the preset for that session only | — | — | Haptic |
| Add | `shortcuts_section.dart:107` | Add screen (`openImport`) | — | — | "Added to your library · Open" |
| Pinned card | `home/widgets/pinned/pinned_section.dart:265` | Opens the course | — | — | — |
| Pinned card's pin icon | `pinned_section.dart:326` | **Unpins at once** | — | — | **None, no Undo** |

## Explore

| Element | Code | Tap | Long-press | ⋮ | Feedback |
|---|---|---|---|---|---|
| Search field | `views/explore/widgets/explore_view.dart:192` | Search (400 ms debounce) | — | — | — |
| Practice / Talks chips | `explore/widgets/kind_chips.dart:20` | Filter; tap again to clear | — | — | — |
| Suggestion chips | `explore_view.dart:248` | Fill the field and search | — | — | — |
| In your library card | `explore_view.dart:376` | Opens the page | — | **none** | — |
| Dharma Seed course card | `explore_view.dart:426` | Opens the course | — | **none**, only ⊕ on the art | — |
| ⊕ / ✓ (`AddToLibraryIcon`) | `widgets/add_to_library_icon.dart:65` | ⊕ adds; ✓ **never removes** ("Already in your library") | — | — | "Added to your library" + **Undo** |
| Teacher | `dharma_seed/widgets/teacher_widgets.dart:15` | Teacher page | — | — | — |
| Latest session row | `dharma_seed/widgets/session_rows_sliver.dart:40` | **Opens TrackView** | — | ⊕ and ⋮ "Add to playlist…" | — |
| Search course row | `dharma_seed/widgets/course_rows_sliver.dart:46` | Opens the course | — | ⊕ and ⋮ Add to playlist, Copy as playlist | — |
| Search talk row | `search/search_results.dart:153` | Opens TrackView | — | ⊕ and ⋮ | — |

## Sounds tab

| Element | Code | Tap | Long-press | ⋮ | Feedback |
|---|---|---|---|---|---|
| Sound card | `soundscape/sound_cards.dart:198`; `providers/soundscape/soundscape_provider.dart:281` | **Toggles one layer** in or out of the live mix, and starts the mix if silent. With 6 layers, unselected cards fade but stay tappable and do nothing | — | — | Outline and ✓; the dock line updates; no snackbar |
| Preset card | `sound_cards.dart:279`; `soundscape_provider.dart:396` | **Replaces the whole mix, saves it as the user's mix**, and plays. Tapping a playing preset applies it again; it doesn't pause | User presets: delete | User presets: Delete | ▶ becomes "Playing". **No warning that an unsaved mix is lost, no Undo** |
| Save mix card / button | `sound_cards.dart:403`; `sound_mix_panel.dart:244` | Name dialog, then save | — | — | "Saved “name”". The card vanishes once the mix matches a preset |
| Delete preset | `sound_mix_panel.dart:548` | Confirm dialog | | | No snackbar, no Undo |
| Dock | `sounds_view.dart:270` | Opens or folds the panel; drag works too | — | — | — |
| Play/pause, Stop, mix volume | `sound_mix_panel.dart:95-204` | Usual; during a session the volume is the session kind's | | | — |
| Layer: mute, ✕, slider, Drift, Adjust | `sound_mix_panel.dart:464-519` | ✕ removes the layer (**no Undo**) | | | — |
| Play under practice / talks | `sounds_view.dart:546` | Session defaults | | | — |

## Library

| Element | Code | Tap | Long-press | ⋮ | Feedback |
|---|---|---|---|---|---|
| New playlist (app-bar icon) | `views/library/library_view.dart:38` | Name and kind dialog, then opens it | — | — | — |
| Add | `library_view.dart:44` | Add screen | | | "Added · Open" |
| In progress card | `library/library_widgets.dart:181` | **Plays** (same as Continue); ▶ on the art does the same | — | — | — |
| Kind chips, Practice/Talks segments, sort, layout | `library_view.dart:216-304` | Filter / sort / layout | | | — |
| Course or playlist (card or row) | `library_widgets.dart:91, 151` | Opens the course | — | Entry menu | Pin mark |
| Single row | `library_widgets.dart:118` | **Opens TrackView** | — | Entry menu | — |
| Teacher row | `library_widgets.dart:136` | Teacher page | — | Entry menu | — |
| Entry menu | `library_widgets.dart:319` | Edit playlist · Add to playlist… · Copy as playlist · Move to Practice/Talks · Rename · Pin/Unpin · Delete playlist or Remove from library | | | Remove a catalogue item: **Undo**. Remove an import: confirm, no Undo. Pin: snackbar, or the three-pin limit. **Unpin, Move, Rename: silent** |

## Course page, teacher page, session page

| Element | Code | Tap | ⋮ | Feedback |
|---|---|---|---|---|
| ▶ (floating) | `pack/widgets/pack_path_button.dart:197` | Plays the next unfinished session | — | Spinner |
| Add to library / In library (`SaveButton`) | `widgets/save_button.dart:316` | **Toggles**. A catalogue item is removed instantly; an import asks, then the page closes | — | **None either way** |
| Pin / Unpin | `pack/pack_view.dart:327` | Toggle; **only shown when the course is in the library** | — | As in the Library |
| Session row | `pack_view.dart:620` | **Opens TrackView** | Add to playlist…; Remove from playlist (own) | Remove: **no confirm, no Undo** |
| Completion circle | `pack/widgets/pack_item_widget.dart:130` | Toggles complete | | Visual |
| Mark all complete / incomplete | `pack_view.dart:695` | Bulk toggle | | **No confirm, no Undo** |
| Bottom bar: ⋮, share, ♥ | `player/widgets/bottom_actions/pack_view_bottom_bar.dart:181` | Actions sheet / share / favourite | | ♥ snackbar |
| Teacher page: Add to library, Website, rows | `teacher/teacher_view.dart:154` | Toggle (silent) / browser / as in search | | — |
| TrackView: Add to library, ▶, From the beginning, Add to playlist, ♥ | `track/track_view.dart:201-415` | Toggle (silent) / player / restart / sheet / favourite | | ♥ snackbar |

## Player, Customize, Timer, end screen

| Element | Code | Behaviour |
|---|---|---|
| Customize before start | `player/player_view.dart:226` | Shown unless hidden or a timer. "Start" plays; dismissing it **closes the player** |
| Action bar | `player/widgets/bottom_actions/player_action_bar.dart:37` | ✕, download (delete confirms), Sounds (**pushes Sounds as a page**), Customize, speed |
| Customize rows | `cues/customize_sheet.dart:256-402` | Sections Bells · Rhythm · Time · Sound · Flow (Time first for a timer). Each row is an accordion, one open at a time, saved at once. Flow holds Autoplay and "Hide these settings before practice". **All hard-coded English** |
| Customize › Background sound | `customize_sheet.dart:640` | Off / Current mix / each preset / **each single sound (replaces the choice)**, volume, "Edit your mix in Sounds" |
| Timer | `timer/timer_view.dart:50` | Timer/Stopwatch, then the embedded Customize sheet: the duration is one accordion row among the others. `timer/widgets/timer_duration_wheels.dart` is built but unused |
| End screen | `end_screen/end_screen_view.dart:180` | ✕, Home, reminder card |

## You, Stats, Add, playlists

| Element | Code | Behaviour |
|---|---|---|
| You header | `you/you_view.dart:36` | **Long-press opens Debug** |
| Stats card | `you/stats_summary_card.dart:42` | Stats screen |
| Settings "Add to your library" | `settings/settings_sections.dart:145` | Pushes ImportView directly, **so no "Added" confirmation** (Home and Library go through `openImport`) |
| History row | `home/widgets/bottom_sheet/stats/meditation_calendar_widget.dart:1175` | Tap opens the session; **long-press deletes** after a confirm, no Undo |
| Downloads row | `downloads/downloads_view.dart:189` | **Swipe** removes, with Undo |
| Playlist editor | `my_courses/my_course_edit_view.dart:188` | Local until Save; back asks to discard; Save is silent |
| Add-to-playlist sheet | `my_courses/my_course_actions.dart:361` | ✓ rows stay tappable ("Already in…"); adding gives "Open", no Undo |

## Inconsistencies, first cut

Ranked by how often Burooj will hit them. Proposals come after the journeys are walked.

1. **Sound vs preset: add vs replace.** Two art cards that look alike. One toggles a layer; the other silently overwrites the live mix *and the saved mix*. A Home preset tile does something else again: it starts a Timer with the preset for that session only. And in Customize › Background sound, choosing one sound *replaces* the choice. So "tap a sound" means three different things.
2. **"Sounds" opens two ways.** From Home it's a tab; from the player it's a pushed page, with the session underneath.
3. **Rows open a page; Continue plays.** Every single/session/talk row opens TrackView, and then you tap ▶. Continue, In progress and ▶ play directly. That's defensible (a row is "look", a card with a play affordance is "go"), but the rule isn't visible: the In progress card and the course card in the Library are the same size and shape.
4. **Continue and In progress are one list in two looks.** The data and the action are the same, the cards differ, and the empty behaviour differs (Home falls back to a suggestion; the Library hides the strip).
5. **Three add-to-library controls.** ⊕ adds with Undo and never removes. Save/In library toggles silently, and its remove is instant. Import offers "Open". Removing from the Library menu gives Undo; removing from the course page gives nothing.
6. **Pin is lopsided.** Pinning confirms, unpinning is silent, and Home's pin icon unpins in one tap with no Undo. Pin is only offered on a course page when the course is in the library. The mark's pin hides behind a long-press with nothing on screen to suggest it.
7. **Course cards carry different actions per screen.** Explore's big cards have only ⊕; search rows have ⊕ and ⋮; "In your library" cards have nothing.
8. **Practice/Talks is four different controls:** chips (Explore), segments (Library), switches (Sounds), Settings rows. Changing a single item's label is a menu item in the Library, but the player doesn't offer it (decision 16, "this is actually a talk").
9. **Destructive actions with no Undo:** Remove from playlist, Mark all, removing a layer, replacing the mix with a preset, deleting a preset, deleting History, Unpin.
10. **Words.** "Customize" names both the Home layout and the session sheet. The Customize sheet and the player's countdown/autoplay strings are hard-coded English. Settings carries Medito-era labels ("Default Guide Name", "Edit stats", Title Case).
11. **Silent dead taps:** faded sound cards at the layer limit, and ✓ rows in the add-to-playlist sheet.
