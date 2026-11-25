# Pass 4: Sounds

From Burooj's 14 Nov walkthrough (issue comment 6882875033) and his listening notes (6883089013). Branch `p4-sounds`, off `staging` e738fa20.

## One floating Sounds button

- **Why:** "The Sound button in the header is hard to read. Sounds should be one **floating button reachable from anywhere**."
- **Where.** Bottom right, above the nav bar, on Home, Explore, Library and Settings (`SoundsButton`, `lib/views/bottom_navigation/widgets/sounds_button.dart`, the main screen's floating action button). A tap opens the Sounds sheet on his own mix, as Home's Sounds tile did.
- **Idle and playing.** Idle, it is a quiet surface-coloured button with the sound-wave icon. While his own mix plays on its own, it is filled in the primary colour and shows a turning record (33⅓ rpm, as the player's sound button turns). A screen reader hears "Sounds, playing Night" (the preset, or the sounds of the mix). A session's sound does not light it: the player shows that. **My call.**
- **Hidden.** It hides while the keyboard is up. A page or sheet pushed over the tabs (a player, the Sounds sheet itself, Customize) covers it, so it needs no hiding of its own there.
- **Room for it.** Library and Settings now end 80 dp lower, so the last row's action scrolls clear of the button. Explore already kept 96 dp. Home did its own 80 dp in the Home slice.
- **Gone:** `SoundsShortcutTile` (Home's old tile; nothing used it), and `showSoundsSheetFor`, whose last caller was Customize's header Sound button. The player's Sounds button still opens the same sheet on the running session.

## Search in the Sounds sheet

- **Why:** "Sounds has no search. Add one."
- A search field sits at the top of the sheet. It matches a sound's name in the app's language, its shelf's name, and for Train its variants and the recordings' own titles. A shelf whose name matches shows whole ("rain" shows the Rain shelf).
- While it holds text, only matching shelves show; Presets, "Plays under" and Credits step aside. A clear button empties it. With nothing found it says "No sounds match".
- New strings, in en/de/es: "Search sounds", "No sounds match", "Train", "Metro", "Yamanote".

## Metro carriage and Yamanote Line train are one "Train"

- **Why:** "Metro carriage and Yamanote Line train should be one sound with knobs for their properties."
- **This is the orchestrator's recommendation, not something Burooj confirmed.** He asked for one sound with knobs; the knobs are #101 and out of scope here. What he gets now is one card and a choice of recording.
- **One card, "Train".** Its row in the mix has two chips, **Metro** and **Yamanote**; a chip swaps the recording in place and keeps the level and Swell. **My call** on the names: "Metro" (German "U-Bahn") and "Yamanote".
- **Nothing stored changes.** Both recordings keep their ids (`train`, `train-yamanote`) as sounds of their own; `kSoundVariants` in `sound_library.dart` only groups them under one card. A saved mix or preset that names either plays exactly what it did. Nothing is migrated or rewritten.
- **A mix that already holds both** keeps both: two Train rows, each with the other chip greyed out. A tap on the card then takes both out. **My call.**
- Everywhere a mix is named (the mix bar, presets, "Plays under"), either recording reads "Train". Sound credits still list both recordings with their authors, as their licences need.
- The art already draws both as the metro scene (`compose.dart`).

## Known limits

- The button turns its record whenever his mix plays; with "Remove animations" on it stays still, filled.
- Search does not look inside presets.
- Two Train rows with neither chip usable is a little odd; it only happens to a mix saved before the merge with both trains in it.
- `docs/fork/design` PNGs of the Sounds sheet are not regenerated (the screenshot tests now render the button; run them with `MEDITEJO_SCREENSHOTS=1`).

## Needs the phone

- Whether the button covers anything on Explore, Library or Settings at the end of a scroll, and on Home with one to three Continue cards.
- Whether the filled, turning button reads as "something is playing" at a glance.
- The search field in the sheet with the keyboard up: the mix bar rides up above the keyboard.
- Metro and Yamanote swap without a gap you notice.
