# Waking Up: UI/UX study for Meditejo

This study draws on two sources, both from 2026-10-16:

- **A tour of the installed Android app.** Version 3.27.0, on Burooj's S23+, logged in as a full member. A Sonnet subagent drove it through the phone MCP, so the screenshots were low-resolution and sit only on bjslab, not in the repo.
- **Public sources:** `waking-up-web.md` beside this file, with links and confidence levels.

Where the two disagree, the tour is the more current evidence. For example, the web sources describe four tabs, but 3.27 has five. The point is to take patterns, not pixels, and Meditejo's own brief decides. The **Meditejo** notes after each section say what follows for us.

## Information architecture

- **Five tabs that stay put:** Home, Explore, My Library, Profile and More.
  - Each tab keeps its own back stack, and tapping a tab twice returns to its root.
  - New features land in Home modules, not in new tabs.
- **Two taps to play.** The route is tab root → series page → session, and the player opens over everything as a full-screen layer.
- **Explore** is a single browse page with category chips (Practice, Theory, Life, Conversations) that work as filters, plus search.
- **Search** opens on a landing page of "Top searches" in plain text. Results are grouped into Speakers and Series. Filters cover format, session length (under 10, 10–20, 20–30, 30–45 minutes) and category (Meditation, Lesson, Talk, Q&A and others).
- **More** is one short, non-scrolling screen of settings and help.

**Meditejo:** Medito already has a small tab bar (Home, Explore, Search, Settings), and it stays stable. Explore's chips map well onto content kinds: *Practice* for guided meditations and *Talks* for dharma talks and Q&A. Dharma Seed's `recording_type` gives us the kind, and the duration filter costs nothing because we sync durations. Search grouped by **Teacher** and **Course** fits Dharma Seed's teachers and retreats.

## Home

The tour found Home ordered like this:

1. The brand mark, then **"Today"** with a **Customize** link.
2. **A hero card.** The user picks it in Customize: either the Introductory Course or Daily Meditation, with the helper text "Start with the Introductory Course. Once you've finished, try Daily Meditation."
3. **Daily supports,** which can be switched on or off: Daily Wisdom (full width), then tiles for Timer, Moment, Quote and Sleep, two per row. Each tile shows a duration, and changes to "Played" once used today.
4. **My List:** up to three pinned series, each showing "N sessions left" with a small progress bar.
5. **Continue Listening:** a horizontal carousel of partly played sessions.
6. A share and guest-pass promo at the bottom.

There is **no single "next session" banner** and no streak. Continuation is spread across the pinned series, the carousel and each series' Resume button.

**Meditejo:**
- **This is where we deliberately diverge.** The brief leads Home with **"Continue your practice — course · Session 4 of 18"**, because losing the thread is the exact failure Burooj wants fixed. Waking Up never needed that, since its own catalogue *is* the thread.
- **Keep the brief's hero, and borrow the rest:**
  - the hero slot as a choice (the current course, or a fallback such as the timer);
  - a short "Today" set of supports that can be switched on and off (timer, soundscape, maybe a talk of the day);
  - pinned courses, capped at three;
  - a quiet continue-listening row.
- **The mechanism already exists.** Medito's `HomeWidgetType` order and its *Organize Home Layout* setting are the natural basis for a Customize screen.
- **One question for Burooj:** the current Home shows a "Consistency Score 0%" badge. Waking Up shows no score on Home, and its stats screens say *"These stats are feedback, not a score."*

## Course and series pages

- **Header:**
  - large square artwork, a status line ("Complete") and a centred title, teacher and description;
  - **"N of M sessions left"** with a small progress bar;
  - one accent-coloured pill (**Start**, or **Resume** mid-course), beside icon buttons to pin, save and download.
- **Tabs:** Sessions, Summary, Teacher and Artwork. They stick at the top as the title collapses into the app bar.
- **Introductory Course structure:** Part → Day → sessions. Each Day mixes a short **Theory** piece with a **Practice**, in alternating order. Days and Parts show a check when done, with Expand all and Collapse all.
- **Flat series** alternate Lesson and Meditation rows. Each row has a kind label, a title, a one-line description, the duration with a play glyph or the position reached, a downloaded marker and a "⋮" menu. New rows get a "New" label.
- **No gating** for members: any session plays in any order, and the course only *suggests* the order.
- **Menus.** The series menu has Add to My List, Save, Download, Share and Mark as Played. The session menu has Save to Playlist, Download, Cast, View Description and View Program.

**Meditejo:**
- **Courses:** a Dharma Seed retreat becomes a course whose sessions are its talks in recording order. Label each row's kind (Talk, Guided, Q&A) from `recording_type`. "N of M left" plus Resume is exactly the pack-progress model from the brief (`tracksChecked`).
- **Never gate,** but always make the next session obvious.
- **Retreats are long.** Grouping rows by day, using `rec_date`, gives us Waking Up's Part/Day rhythm for free.
- **Summary and Teacher tabs** come straight from the retreat description and the teacher bio and photo.

## Player

- **Before playing:** a skippable full-screen countdown (configurable as Off, 5 s or 10 s).
- **Layout:**
  - close (×) and minimise (chevron) at the top;
  - large artwork, with the background colour taken from the art;
  - the series name and session title, with a bookmark;
  - a seek bar showing elapsed and remaining time;
  - previous, back 15 s, play/pause, forward 15 s and next.
- **Bottom row:** share, speed ("1.2x"), **Customize**, and a "⋮" menu.
- **Minimise** leaves a mini-player card above the tab bar ("11m 9s left").
- **The Customize sheet is the key pattern.** One bottom sheet holds:
  - **Extend Session:** a minutes wheel longer than the guided audio, for example 11–13 minutes for an 8m 34s recording;
  - countdown;
  - **starting bell and ending bell:** Off, Bowl 1, Bowl 2, Bowl 3, Extended, Triplet;
  - **background sounds**, with separate General and Practice settings, a few presets (Music, Forest, Rain, Ocean, Brown Noise) and a volume mix;
  - autoplay, with an optional **interlude** gap;
  - a live **"Finishes at 12:48 AM"** line;
  - a "Hide settings before practice" option.

  Each row shows its current value in the accent colour and opens a small sub-sheet.

**Meditejo:**
- **This is the strongest thing to borrow,** and it lines up with the brief's cue system. One Customize sheet should serve both guided sessions and the timer: countdown, start/end/interval cues, extend-with-silence, soundscape layers with a mix, and a "Finishes at" line.
- **Two settings scopes.** Waking Up keeps General and Practice separate, so talks and meditations can have different background-sound defaults. That matters for us, because Dharma Seed talks shouldn't get rain sounds by default.
- **Extend Session.** Waking Up offers more minutes than the recording. The web sources describe its daily meditation spreading the silence *through* the track. The brief settles silence *after* the track ends, which suits recorded dharma talks we can't alter (CC BY-NC-ND), so we keep that.

## Timer

- **Set Timer** is the same sheet: a duration wheel, countdown, starting and ending bells, **Interval Bell** ("every minute, every 2 minutes, every 5 minutes …"), background sounds, "Finishes at …", and **Start**.
- There's no guided-voice option.
- One Play review says the ending bell rings about 3 seconds early. That's a reminder that cue timing has to be exact.

**Meditejo:** the timer becomes the bare form of the Customize sheet. Interval bells and the pulse belong in it as cues, as the brief describes. Test that cue timing is accurate to within 100 ms.

## Profile and stats

- **Trends and History** tabs.
- Trends shows minutes, weekly activity, a cluster of teacher portraits sized by listening share, and a donut chart of sections.
- The copy is gentle: *"These numbers don't reflect the quality of your practice. Review with curiosity, not judgment."*
- No streak badges. Reminders are opt-in, with time windows.

**Meditejo:** stats are already local. Use this tone in their copy, and consider a "teachers you've sat with" view. Streaks are worth a check against the brief's no-gamification rule; see the questions below.

## Visual language

- **Colour:** a very dark navy page with **a single saturated mint/teal accent**, used for CTAs, selected chips, progress and status words. Titles are white; metadata is blue-grey; cards are slightly lighter, with rounded corners.
- **Artwork carries the colour:** commissioned illustration and generative art, and painted teacher portraits. The 2021 Partner redesign aimed for browsing that feels like "walking through MoMA".
- **Type:** a clean geometric sans-serif. Each item gets a big title, one line of meta, and a 2–3 line description.
- **Density:** about 4–5 rows per screen, no ratings or badges beyond "New", and settings hidden behind one Customize affordance.
- **Motion** is minimal: collapsing headers, sheets that slide up, the countdown.

**Meditejo:**
- **Direction:** one accent colour, quiet surfaces, and artwork as the colour source. This is direction for the later design-language pass with the design-lab skill. We don't change it now.
- **Artwork is our gap.** Dharma Seed teacher photos are the main art we have, so plan a calm generative fallback (per course) rather than empty tiles.

## What not to copy

- **Paywalls, billing and promos:** paywalls in the middle of a course, billing surprises, and promos on Home (guest pass, "Give 30 days"). None of these apply to us.
- **Findability:** a library that's hard to search, which is why local full-text search over the synced catalogue matters.
- **Playback bugs on Android:** these show up in reviews. Our player is Medito's, which is already proven.
- **Silent "Played" marking:** merely opening a session marks it "Played" on Home and in History. The tour saw this happen from accidental taps. Mark completion on real listening (Medito's completion threshold), not on open.

## Questions for Burooj

1. **Home:** keep the brief's "Continue your practice" hero, and add Waking Up's Customize-style toggleable "Today" supports and up to three pinned courses? (Recommended.)
2. **Consistency score and streaks:** keep them, demote them to the stats screen, or reword them in Waking Up's "feedback, not a score" spirit? (Recommended: demote and reword.)
3. **Content kinds in Explore:** split *Practice* (guided) from *Talks* (dharma talks, Q&A) as chips? (Recommended.)
