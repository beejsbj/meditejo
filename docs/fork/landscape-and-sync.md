<!-- Scout report, 2026-10-14 (Sonnet subagent, web research). Positioning + heart-rate sync routes. -->

**Verdict: "No other meditation app lets you bring your own content" is false, so don't use it.** A shipped app already does (c) without an account, and one open-source Android app does URL and local import.

| App | Platform / OSS? | Covers | Evidence |
|---|---|---|---|
| MeditationPal | iOS/iPad, proprietary, free with a $6.99 lifetime unlock | (c) paste a podcast, video-page or direct-audio link, or import files. Also (d) with no account and iCloud-only sync, plus ambient sounds and a breathing circle. Lacks (b) and courses. It has playlists and a progress "Journey" view, but no bells and timer in the listing. | https://apps.apple.com/app/id6759429876 |
| Mindra | Android and Linux, Flutter, MIT | (c) partial: "Add network audio/video resources via URL" and local import. Also (d) (no account mentioned) and ambient overlay plus session tracking. YouTubeExplode is in the tech stack, but the README doesn't list YouTube as a feature. "Professional course content" is only planned, and cloud sync is in development. | https://github.com/gonewx/mindra |
| Meditate (janekbt) | Android and Linux, GPLv3, F-Droid | (c) local guided audio only (imports it, with on-device Opus transcode), plus bells and timer. (d) with no telemetry. No URL, RSS, courses or catalogues. | https://f-droid.org/packages/io.github.janekbt.Meditate/ |
| Zazen Meditation Timer (Graf) | Android, F-Droid | Import your own bell sounds only. It does not play guided audio. | https://f-droid.org/packages/at.priv.graf.zazentimer/ |
| Bodhi Timer | Android, OSS | Custom alert tone only. No guided audio found. | https://github.com/yuttadhammo/BodhiTimer |
| SoundAura | Android, Apache-2.0 | Local files as ambient layers (soundscape player). | https://alternativeto.net/software/meditationpal |
| Insight Timer | Android/iOS, commercial | No listener upload found. Playlists contain only library tracks, and uploads go through the teacher dashboard. | https://help.insighttimer.com/support/solutions/articles/67000667366-how-do-i-add-tracks-to-my-playlists- |
| Medito, Waking Up, Plum Village | OSS / commercial | None found. Playlists hold in-app content only. | https://meditofoundation.org/medito-app, https://m.wakingup.com/inside-the-app/customize |
| Official Dharma Seed app | Android and iOS, GPLv3 | (b) only: stream, search, offline. No import. | https://github.com/dharmaseed/dharmaseed-android |
| Course tools (Course.link, Focus Room, Owlpeer) | Web / iOS only | YouTube playlist to course, with no meditation features. | https://courselink.help.center/article/1022-how-to-create-course-from-youtube-playlist |

**Not confirmed either way.** I found nothing for Calm, Headspace, Balance, Healthy Minds, Enso, Prana Breath, Session, Oak or Open Meditation. That's absence in search results, not proof; Healthy Minds returned only store listings, and Open Meditation and Meditation Assistant returned no F-Droid listing at all. Dharma Radio (dharmaradio.org) turned out to be a Dharma Realm Buddhist Association project, not a Dharma Seed-style archive, and it has no import. I did not check Mindra's CHANGELOG for YouTube (the URL 404'd), so check it before you publish anything about Mindra.

**How to phrase it**
- Accurate: "The free, open-source, account-free Android meditation app that turns podcast feeds, YouTube playlists and your own audio into courses with 'session N of M' progress, built on top of searchable Dharma Seed and dhammatalks.org catalogues."
- This works because the combination is what's new. I found no meditation app, open-source or commercial, that treats RSS feeds or YouTube playlists as sequenced courses. MeditationPal is closest on import. Mindra is closest on open source and Android, but it lacks courses and the catalogues.
- Drop "only", "first" and "no other". Soften to "as far as we found" if you want the stronger claim.
- Two risks. Mindra could add courses, since they're on its roadmap. YouTube extraction also carries terms-of-service risk, so the strict "openly licensed" framing fits (b) better than (c).

**How Endel-style sync works**
- Endel's site says it "reacts to inputs like time of day, weather, heart rate, and location" and mentions "cadence of your walks". The only heart rate source it names is Apple Watch. Source: https://endel.io/
- It adjusts the pace of the music by comparing your heart rate to your resting rate. This detail comes from a secondary summary, not Endel's own documentation. Brain.fm (brainwave-entrainment audio, no biometric input found), myNoise and Portal show no heart-rate input in what I found. SereneFreq and Sonaur are HealthKit-based and iOS-only.
- Whether Endel's Android app reads heart rate, and from where, is undocumented. I couldn't verify it.

**Real-time heart rate on Android**
- **Health Connect:** not live. Google's own guidance is to write heart rate in batches of up to 15 minutes. Use it for history only. https://developer.android.com/health-and-fitness/health-connect/experiences/vitals
- **Wear OS Health Services:** `MeasureClient.heartRateMeasureFlow()` runs on the watch and needs the BODY_SENSORS permission. Send the samples to the phone over the Data Layer. This is the least restricted live route. https://developer.android.com/health-and-fitness/fitness/basic-app/integrate-wear-os
- **Samsung Health Sensor SDK:** continuous heart rate and inter-beat intervals, but Galaxy Watch4 or later only, watch-side, not on phones. A Samsung code lab says the full library needs the Samsung partner program. I couldn't confirm that on the overview page. https://developer.samsung.com/health/sensor/overview.html
- **Bluetooth LE chest strap or arm band:** the standard Heart Rate Service (0x180D, characteristic 0x2A37) streams about once a second. I didn't verify this against the Bluetooth SIG spec; it's from general knowledge. It needs no vendor approval.
- **Phone sensors:** phones have no heart rate sensor. A camera-based fingertip pulse is possible but impractical during meditation.

Nothing was written to disk.
