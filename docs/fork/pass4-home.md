## 2026-11-25 (staging, pass 4: Home, Library and Settings)

From Burooj's 14 Nov walkthrough of `b491c0a1` (issue comment 6882875033).

### Home: one section

- **Why:** "Shortcuts (Timer, Sounds) and Pinned (presets, courses) read as two systems. Make them one."
- **Pinned is the one section.** The Timer is its fixed first tile, then pinned presets, then pinned courses and sessions as cards. The Shortcuts section and its heading are gone. Pinned now always shows, because the Timer is always there.
- **Sounds left Home.** The Sounds slice puts a floating Sounds button over every tab (`lib/views/root`, not built here).
- **Tiles and See all.** Home shows the Timer and up to three presets: two rows of two (`PinnedPresetsNotifier.homeLimit` 4 → 3). See all shows when there are more than three presets or more than three courses, and counts pins only; the Timer is not a pin and is not in the See all list. **My call.**
- **Organize Home layout** lists Continue and Pinned only. Hiding Pinned hides the Timer too. **My call**: the Timer belongs to the section it sits in.
- **Stored layouts migrate on read.** A saved order naming `homeShortcuts` (or the older `quickLinks`) puts Pinned where Shortcuts was, since the Timer led Shortcuts. A saved "hidden" on Shortcuts is dropped, so it never hides the pins. Nothing is rewritten until the user reorders.

### Home spacing

- **Why:** "a large gap between the mark and Continue, and the Timer/Sounds row is cut off above the nav bar."
- **The gap.** The first section has no top padding of its own; the mark's name line is the air above it (about 20 dp less). Spare height in the mark's block now goes above the mark, not between it and Continue.
- **The cut-off row.** The mark gives way until the first row of tiles ends 80 dp above the nav bar, which clears the floating Sounds button at the bottom right (it was 16 dp). The mark's floor is lower, 22% of the screen (was 28%), so the row fits even with three Continue cards. The cost: with three cards the mark is about 190 dp wide on the S23+ (it was 220 to 300). **My call.**
- Home's scroll ends 80 dp above the nav bar, so the last card scrolls clear of the button.

### + in the Home and Explore headers

- **Why:** "Add a + (add to library) to the Home and Explore headers, as Library has. The Settings → Add to your library row is pointless."
- One `LibraryAddButton` (in `library_add_sheet.dart`) in all three headers, opening the same sheet: Import, New playlist. On Home it sits left of Customize and You. Settings' "Add to your library" row is gone.

### Library: Practices and Talks

- **Why:** "Split 'Sessions' into Practices and Talks."
- Sections are now Practices, Talks, Playlists, Courses, Teachers. Courses still mix both kinds.
- **A session's kind** is what the Library filter already uses (`libraryEntryKinds`): the user's choice first; else its one known kind (Dharma Seed's recording type); else, with both or none, the kind it was filed as. Under the Practice or Talks chip, everything shown sits under that chip's section.

### Settings

- **Why:** "'Practice sounds & cues' and 'Talks sounds & cues' should say they are defaults." The rows are now **Practice defaults** and **Talk defaults**, with the same subtitle (Bells, cues and background sound). **My call** on the wording.
- **Why:** "Sources lists only Dharma Seed. dhammatalks.org is built in too but isn't shown." A **dhammatalks.org** row under Sources: "Thanissaro Bhikkhu's talks, built in". It has nothing to sync or set, so a tap opens his teacher page, where the talks are. **My call.**

### Known limits

- `SoundsShortcutTile` is no longer on Home but the file stays: the Sounds sheet screenshot test uses it, and the floating button may want its "what plays" label. Delete it once the button lands without it.
- The old strings (`homeShortcutsTitle`, `librarySectionSessions`, `settingsPracticeCues`, `settingsTalksCues`) are unused now. They stay in the ARBs, to keep this slice's ARB edit to one block at the end.
- `docs/fork/design/home-*.png` still show the old Home; not regenerated.

### Needs the phone

- Whether the first row of tiles clears the floating Sounds button with one, two and three Continue cards.
- Whether the mark at about 190 dp (three Continue cards) is too small.
- The + on Home next to Customize and You: three buttons in the corner over the mark.
