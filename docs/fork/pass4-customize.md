# Pass 4: Customize

From Burooj's 14 Nov walkthrough (issue comment 6882875033) and his listening notes. Branch `p4-customize`, off `staging`.

## What changed and why

- **The summary line under Extend keeps one height.** "The whole sheet jumps when the summary line changes ("43 min" → "43 min + 2 min = 45 min")." The sum and the Finishes pill now share one line of fixed height (40 dp, scaled with the text). A longer line shrinks to fit; it never wraps. The sum is shorter and smaller: "43 + 2 = 45 min", in body-medium instead of body-large. It keeps "min" on each part only when a part is an hour or more ("1 h 5 min + 2 min = …").
- **No Undo toast for Customize changes.** "An Undo toast ("Duration: ∞ · Undo") pushes the sheet up." The bar, its timer, the room kept under the list, and the `customizeUndoChange` string (en/de/es) are gone. Wheels, ∞, bells and the rhythm save at once, as they did, with nothing shown after.
- **∞ has a clear on state.** "You can't tell whether it's on." On, it is a filled button in the primary colour; off, an outlined one. Before, it was tonal both ways and differed only slightly.
- **Bells and Rhythm open as sheets over Customize.** Before, a tile swapped the sheet's content for a card with a back arrow. Now each tile opens a modal bottom sheet over Customize, titled with the tile's name. The drag handle, a tap above, or system back closes it, and Customize is where it was left. Its wheels are the main dial's size: large rows, and as many rows as the main dial shows (five on a tall screen for the Timer, three for Extend).
- **Bell sheets: wheels left, volume right, in one row.** "Put the countdown on the left and the bell volume on the right, in one row." The Starting bell's countdown, the Interval bell's Every and Random window, and the Ending bell's silence each stand in one row with the bell volume as a vertical slider on their right. The list of bells is under that row. The Timer's Ending bell has no wheel, so its volume stays a horizontal slider.
- **Rhythm: centred, with volume as a fourth column.** "The three wheels sit left of centre. Centre them, and make pulse volume a vertical fourth column." Rate, Over and Ends at now centre with the pulse volume as a vertical slider beside them. Every wheel row is now centred. The 1:4 split of spare room that pushed rows left (#91, room for a right thumb) is gone. Both gutters stay at least 28 dp.
- **Rhythm plays the pulse while it is set.** "So you can hear how it feels." While the Rhythm sheet is open and a pulse is chosen, it beats at the chosen rate and level. This is a true live preview, not a short audition loop. A new rate restarts the beat; a new level or sound is heard from the next beat. It stops when Off is chosen and when the sheet closes. It does not play if a session is already playing, so it never doubles a session's own pulse. It is `PulsePreview` in `lib/views/cues/pulse_preview.dart`: a Dart timer re-sounding one just_audio player. It uses the bell preview's player, which on Android takes no audio focus. The session's native pulse (CueEngine.kt) is untouched.
- **The Sound button is gone from Customize's header.** The Sounds slice builds the floating Sounds button that replaces it. The header is now the title and whose settings these are. `customizeSlotSound` stays because presets use it.

## My calls (overrule freely)

- **The preview beats at the starting rate only.** A ramp ("slow down over 20 min to 40 BPM") is heard only in a session. Previewing the ramp would mean either waiting minutes or squeezing it, and neither tells you how it feels.
- **"A session is playing" means the player reports playing.** A paused session gets the preview. A playing session gets nothing, even if it has no pulse of its own.
- **A tile's sheet has no Back or close button.** It has a title and a drag handle, as Customize itself has. Tapping above it or system back closes it too.
- **Extend's dial keeps three rows.** "The same size as the main dial" is read as matching whichever dial the sheet has. The Timer's length dial is five rows on a tall screen, and the bell and rhythm sheets follow it. On a recording, everything is three rows.
- **The summary line shrinks rather than wraps.** On a narrow screen with large text, the sum and Finishes pill get smaller instead of taking two lines.

## Tests

- `test/views/cues/customize_sheet_test.dart` covers:
  - a tile opens a bottom sheet over Customize and closing it keeps Customize's scroll position;
  - the countdown and volume share one row above the bells;
  - the Rhythm row is centred with volume as a fourth column;
  - the summary line keeps its rect when the sum grows, and the tiles under it do not move;
  - ∞ is filled in the primary colour only when on;
  - no Undo toast appears after a wheel or ∞ change;
  - the pulse plays, follows the rate and level, stops on Off and on close, and is not added over a playing session.
- Removed tests, with reasons:
  - all Undo-bar tests, because the bar is gone by request;
  - the in-place card motion tests, because the cards are now standard modal sheets;
  - the header Sound-button and drawer tests in the Customize test and `test/views/timer/timer_sound_drawer_test.dart`, because the button moved to the Sounds slice's floating button, which gets its own tests.

## Known limits

- The vertical sliders sit inside a scrolling sheet. A vertical drag on one moves the slider; a drag in the gutters scrolls. This needs a feel check on the phone.
- The just_audio preview re-sounds the sample with a seek on each beat. Its timing is good enough to judge a rate, not sample-accurate.
- Screenshot tests still look for the old header button: `test/screenshots/design_screenshots_test.dart` ("Customize sound open") and `sounds_sheet_screenshots_test.dart` (`_tapSound`). They run only with `MEDITEJO_SCREENSHOTS=1`. These files are shared with the Sounds slice, so I left them for the orchestrator.

## Needs the phone

- Does the pulse preview sound right, and does it stay in time at 120 BPM?
- Does it duck or pause a soundscape playing in the background? It takes no audio focus on Android, as the bell preview doesn't.
- How do the vertical volume sliders feel next to the wheels?
- Does the ∞ on state now read at a glance?
- Do the bell and rhythm sheets slide over Customize cleanly?
