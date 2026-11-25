# Pass 4: content (starter set additions, livestream schedule trimmed)

## 2026-11-25 (staging pass 4: three starter additions, existing installs get them, schedule text gone)

### The starter set gains three items

- **Why:** the curation pass (`Projects/tmi-guided/practices/curation-youtube.md`) recommended QRI's second course and Vervaeke's short practice set, the only other guided practice on either channel.
- **QRI, "Qualia Mastery II - Further Develop Your Toolkit for Navigating the State-Space of Consciousness"** (playlist `PLbmYHvGI-YStGL1bzkuxj_xqFvHzvjxEY`, 9 sessions). Practice. It is last in the set, after Qualia Mastery.
- **Vervaeke, "After Socrates | The Practices"** (playlist `PLND1JCRq8VuhiAkaZ4UfmMwDq0c3a_cDn`, practices #2 to #4). Practice, after *Meditating with John Vervaeke*.
- **Vervaeke, "Mindfulness Meditation - Find Your Center"** (video `9c736DThL_M`, practice #1, about 32 minutes). The playlist leaves it out, so it is seeded as a single, just before the course.
- **Licence:** none was found for either channel, so both stream from YouTube like the two YouTube starter courses already there. Nothing is cached or downloaded.

### Single-video seeding (#152, part 1)

- Issue #152 was right: the seed only wrote playlist rows, and a `yt-video-` single with no `youtube_videos` row cannot open (`YoutubeSource.track` throws).
- **Smallest clean fix:** the seed now writes a placeholder video row for a single (title and channel from `starter_set.dart`, no picture, length 0, never looked up). That is the same idea as the empty, already-due playlist row a starter course gets. Seeding it as an extra episode of the After Socrates course does not work, because a playlist refresh rewrites the course's video list from YouTube.
- **The first look fills in the gaps.** `_describeVideoNow` (which runs when the single's page opens, or during the background detail fill) already read the description and channel. It now also sets the picture and the length, but only where the stored row has none. It then updates the library card. A row a playlist already filled keeps its values.
- **Known limit:** until that first look, the single shows no length and no thumbnail. It plays as soon as it is opened, because the audio stream is looked up at play time.
- #152's Wim Hof video is not added here; it needs its safety note first. The seeding it needed now works.

### Existing installs get the additions (my call on the mechanism)

- **There was no mechanism.** The starter set was seeded once, behind `starter_seeded`, and an install that already had a library got nothing. The YouTube courses joined the set before any phone had seeded, so nothing had to be added afterwards.
- **Now:** each `StarterItem` has `since` (the set's version that brought it), and `starterSetVersion` is 2. `addNewStarterItems` runs after `seedStarterSet` at every library open. An install that holds an older version (an install with no recorded version counts as 1) gets each newer item once. Then the version is recorded, so anything the user removes stays removed. A fresh install is seeded with everything and recorded as version 2, so nothing is added twice.
- **No duplicates.** An item already in the library (for example, if Burooj imported Qualia Mastery II by hand) is skipped, and its stored playlist or video row is left alone. Placeholder rows are inserted only where none exists. Before, the seed's playlist row overwrote one.
- **Who gets them:** installs seeded with the first set, and also installs whose library predates the starter set (Burooj's phone: it was flagged without seeding then). The first set itself is still never added to those. *My call:* the additions are new content Burooj asked for, and his own phone is such an install.
- **Where they land:** at the top of the library (added "now", in the set's order). *My call:* new things lead, as they would after an import.
- **Without YouTube (iOS):** nothing is added, and the version is still recorded, the same as the first seed.
- The seed and the additions each write their rows and the version in one transaction, so an interrupted launch tries again next time.
- To add starter items later: give them `since: 3` and raise `starterSetVersion` to 3.

### Livestream schedule trimmed

- **Why:** Burooj still saw "| Livestream Mon-Fri 09:30 EST" and its variants on Vervaeke's sessions. `episodeTitle` (#84) cuts only what all of a course's titles share at a separator, but YouTube spells the schedule five ways: "-Livestream Mon-Fri 09:30 EST", "-Livestream Mon-Fri at 09:30 EST", "- Live Mon-Fri …", "- Live Stream Mon-Fri …" and "- Stream Mon-Fri 9:30 EST". So the shared tail was only ":30 EST", with no separator before it, and nothing was cut. `episodeTitle` was also used only on the episode page and the course page's path button. Lists, the player, Continue and search showed the raw title.
- **Fix:** `withoutSchedule` (`lib/utils/episode_title.dart`) removes a trailing "Live/Livestream/Live stream/Stream + days + time (+ zone)", with an optional separator before it. It only does this when the schedule ends the title and words remain before it. `episodeTitle` applies it first, so the course-name cut now works on all 18 lessons. `YoutubeSource` applies it wherever a title leaves it or is stored: course lists, the player (`track`), search, the import preview, saved singles, and new or refreshed rows. Continue and the player screen read those, so they follow; the media notification should too (not checked). Rows stored before the fix read clean too, and they are rewritten clean at the course's next refresh (every 12 hours).
- **Kept:** "Day 1", "Lesson 1:" and the course name in front (that one is cut only on the episode page, as before). The schedule is cut only from YouTube titles. Dharma Seed and other sources are untouched.
- **Tests:** `test/utils/episode_title_test.dart` (each real spelling, and titles that must stay whole, such as "Live Q&A …" or "Stream of Consciousness"), `test/services/youtube/youtube_source_test.dart` (lists, player, search, rows stored before), `test/services/library/library_defaults_test.dart` (fresh seed, additions once, removal sticks, no duplicate, iOS, a single opening and filling in).

### Not done, flagged

- **Art and categories for the new items.** The four Dharma Seed starters and the two first YouTube courses have frozen curated art (`assets/art/curated_art.json`) and hand-picked categories. The three new items show their YouTube thumbnail (the single shows one after its first look) and no category. Curating them needs the art tool and a read of their contents. That is a follow-up if Burooj wants them to match.
- **Needs the phone:** on Burooj's installed build, updating should put the three items at the top of the library once, with nothing doubled. Opening the single should play practice #1 and fill in its length and picture. Vervaeke's lessons should show no schedule in the course list, the player, Continue or search.
