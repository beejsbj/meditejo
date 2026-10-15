<!-- Scout report, 2026-10-14 (Sonnet subagent, web research; endpoints tested, licences read on primary pages). Dharma Seed API details: see memory/handoff brief. -->

**Dharma Seed already covers a lot, so the other CC sources add less than they first seem to.** Burbea (teacher 210, about 439 talks, including the jhana and Soulmaking material) and Leigh Brasington are both on Dharma Seed. I tested the Dharma Seed API and it responds. AudioDharma's Gil Fronsdal talks have large overlap with it, and Spirit Rock and IMS talks sit on Dharma Seed too. I spent most of the effort on testing endpoints and primary license text. Nothing was written to disk beyond scratch files in /tmp.

## Recommended (ranked)

**1. dhammatalks.org (Thanissaro Bhikkhu), best new source for jhana and breath**
- **License:** CC BY-NC 4.0. Quoted from the evening-talks feed: "Copyright 2026, Thanissaro Bhikkhu… Creative Commons Attribution-NonCommercial 4.0… Any sale, including by non-profit entities for non-profit purposes, shall be considered 'commercial'." The [homepage copyright section](https://www.dhammatalks.org/) says the content is "meant to be released under" that license, and most pre-2014 works carry only "for free distribution only" wording. A free app is fine. Never charge or put it behind a paywall.
- **Access, all tested and returning 200:**
  - Evening talks feed: `https://www.dhammatalks.org/rss/evening.xml`. It has 50 items with direct `<enclosure>` MP3s, e.g. `/Archive/y2026/261013_The_Focus_of_the_Practice.mp3`.
  - Morning short talks feed: `https://www.dhammatalks.org/rss/morning.xml`. It has 50 items with direct MP3s.
  - Year index pages: `/audio/evening/{year}/`. Each lists about 200 to 280 MP3 links, back to at least 2005. That suggests roughly 4,000 or more talks. Scrape these for the back catalogue.
  - Curated indexes: `/mp3_guidedMed_index.html` (5 guided meditations: metta 4 min, breath 12/30/40/40 min) and the Basics collection (`/mp3_collections_index.html`, 343 links).
  - `/dhammatalks.rss` is only a "new content" notice feed. It has no audio.
  - `/audio/lectures/` and `/rss/lectures.xml` returned 404.
- **Fit:** Breath and right-concentration/jhana talks are strong. Guided material is thin (5 files), and insight is moderate. Metta is limited to the one 4-minute guided track and scattered talks.
- **Cautions:** Audio quality is inconsistent (filename tags such as "low-fi"). There is no JSON API, so you would parse HTML and RSS.

**2. AudioDharma (audiodharma.org, Insight Meditation Center, Gil Fronsdal)**
- **License:** CC BY-NC-ND 4.0. The [homepage](https://www.audiodharma.org/) links it, and the feed says "Licensed under a Creative Commons Attribution-Noncommercial-No Derivative Works 4.0 License https://creativecommons.org/licenses/by-nc-nd/4.0".
- **Access:**
  - Feed: `http://feeds.feedburner.com/audiodharma`. It is valid, with 100 items, direct MP3s on `https://audiodharma.us-east-1.linodeobjects.com/talks/{id}/…mp3`, and durations. A HEAD request on an enclosure returned 200 with Accept-Ranges, so seeking works.
  - Browse pages (`/talks/`, `/speakers/{id}`, `/series/`, `/retreats/`) are HTML only. About 632 pages of 24 talks, so roughly 15,000 talks, and about 390 speakers.
  - There is no JSON or RSS per speaker (both return 406).
  - `sitemap.xml.gz` is only an index. The sub-sitemap `sitemap_talks.xml.gz` returns 404, so the sitemap is not usable for bulk enumeration.
- **Constraints:** [robots.txt](https://www.audiodharma.org/robots.txt) disallows `/talks/*/download` (it 302s to short-lived presigned URLs), `?page=` pagination, and search, with Crawl-delay 10. Practical route: the feed for new talks, and ask IMC for a catalogue export for the back catalogue. An offer to send a dump is plausible, and the contact would be the donate/feedback form.
- **Fit:** Strong on insight and metta. It has a Guided Meditations section and Path Fundamentals and Intro to Meditation series. Jhana is moderate (Brasington, Ajahn Brahm and others appear).

**3. UCLA Mindful (MARC) free guided meditations, small but clean**
- **License:** CC BY-NC-ND 4.0, copyright The UC Regents. Stated on the [guided meditations page](https://www.uclahealth.org/programs/marc/free-guided-meditations/guided-meditations) and the [weekly page](https://www.uclahealth.org/uclamindful/weekly-meditations-talks). Attribution plus a license link is required, with no implied endorsement.
- **Access:** The guided meditations page links 106 distinct MP3s on `https://d1cy5zxxhbcbkk.cloudfront.net/guided-meditations/*.mp3`. Spot check: 200, audio/mp3. They cover about 19 languages, and English has only 8. The weekly "Hammer" podcast page links 101 MP3s at `/hammer-podcast/Hammer*.mp3`. I found no RSS feed, so scrape the HTML.
- **Fit:** Breath, body and compassion basics, and multilingual. No jhana or deep insight.

**4. Free Mindfulness Project (freemindfulness.org)**
- **License:** [Download page](https://www.freemindfulness.org/download) states CC BY-NC-SA 3.0 Unported and asks you to credit the original sources. The tracks come from several contributors (UCLA, UCSD, Breathworks, others), and the page does not say whether each contributor agreed to this license.
- **Access:** 32 MP3s (24 guided, 8 bell timers) at Google Drive links `https://drive.google.com/uc?export=download&id=…`. I tested one and it served audio/mpeg. There is no RSS or API. Drive is a fragile host for streaming because of quotas and link-rot.
- **Fit:** Body scan and breath, MBSR-style. This is a candidate for bundling, or for asking the project to host the files elsewhere.

## Rejected or uncertain
- **Hermes Amāra Foundation (hermesamara.org):** the site only says "Copyright Hermes Amāra Foundation for the benefit of all beings", with no license or redistribution terms. It lists 89 guided meditations, but audio URLs are JS-rendered. The CC BY-NC-ND copies on Dharma Seed teacher 210 are already in scope. Email info@hermesamara.org if you want direct hosting.
- **Tara Brach:** her libsyn feed (`tarabrach.libsyn.com/rss`, 1,634 enclosures) says "Tara Brach - All rights reserved". Reject.
- **Thich Nhat Hanh / Plum Village (tnhaudio.org feed, 300 items):** copyright is "Plum Village Community of Engaged Buddhism", and I found no license or terms. The tnhaudio.org feed is run by a volunteer (Kenley Neufeld). Needs written permission.
- **Amaravati / Forest Sangha:** the site returns 403 to my requests, and I found no license statement (only a "© Amaravati Buddhist Monastery" line in podcast directories). Needs permission.
- **QRI:** podcast feed `media.rss.com/qri/feed.xml` is live, but copyright reads "Qualia Research Institute 2022" with no license. No guided jhana library found. Ask them.
- **SuttaCentral / Bhante Sujato audio:** the CC0 license covers the text. The audio license is only a forum-user claim, and only SN 1.1 to 2.20 are recorded by Sujato (the rest is synthetic voice). Reject for now.
- **Palouse Mindfulness:** free but third-party permissions only. A 2025 letter forbids teaching or reusing it. Reject.
- **Insight Timer:** closed, noted only.
- **Internet Archive:** a CC audio search returned mostly lo-fi music and one-offs, with no coherent dharma collection. LibriVox-style public-domain audio is not worth pursuing.
- **Pa-Auk and jhana-specific sources:** I found no separate open feed (Brasington's talks are on Dharma Seed and AudioDharma).
- **Dharma Seed sister sites** (gaia, imsrc, fgr and others): these are subdomains of the same data and add nothing.
- **UCSD Center for Mindfulness:** only appears as a contributor on Free Mindfulness. I did not find its own license page.

## Open points for you
- **Licenses:** AudioDharma and UCLA are CC BY-NC-ND, so stream them unmodified, with attribution and a license link. That means no trimming, re-encoding or mixing.
- **Coverage:** For jhana, metta and body practice, Dharma Seed plus dhammatalks.org plus AudioDharma is most of what is openly licensed and usable. Hermes Amāra, QRI and Plum Village are the ones where an email for permission could add material.

Sources: [AudioDharma](https://www.audiodharma.org/), [dhammatalks.org](https://www.dhammatalks.org/), [Free Mindfulness download page](https://www.freemindfulness.org/download), [UCLA Mindful guided meditations](https://www.uclahealth.org/programs/marc/free-guided-meditations/guided-meditations), [Hermes Amāra](https://www.hermesamara.org/).
