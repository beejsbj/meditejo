# Meditejo

Meditejo is Burooj’s personal meditation app, made to keep the practice material that was scattered across Dharma Seed, YouTube and courses in one calm place. It is on Android (version 0.1.4 at the time of writing). The whole of Dharma Seed is built in and searchable offline; you can add retreats, talks, YouTube playlists, podcast feeds, audio links and your own files to a library of courses and playlists, and carry on where you left off. There is a timer with bells, interval cues and background sounds, and the app draws its own art. There are no accounts, no analytics, and no donation asks. *Meditejo* is Esperanto for “place of meditation”.

## Build

See [docs/fork/BUILD.md](docs/fork/BUILD.md) for the toolchain, code generation, build and signing instructions. The Dart package retains its internal name `medito`.

## Branding

The launcher icon is the **shelter** (a roof over a resting pebble) in the Tidewater palette, Meditejo's fixed house mark. Its geometry is frozen in [assets/branding/house_mark.json](assets/branding/house_mark.json); regenerate every platform's icon from it with:

```sh
uv run tools/meditejo/branding/make_icons.py
```

This writes the Android adaptive icon (with its Android 13 monochrome layer), legacy mipmaps, notification and widget glyphs, the iOS app and widget icons, and the app's own copies. Inside the app, Home shows a different generated mark each day, which can be pinned; see `lib/services/identity/`.

## Lineage and sources

Meditejo is an independent fork. This section says where everything comes from and on what terms. [`assets/audio/NOTICE`](assets/audio/NOTICE), [`assets/sounds/NOTICE`](assets/sounds/NOTICE), [`assets/licenses/`](assets/licenses/) and [docs/fork/DECISIONS.md](docs/fork/DECISIONS.md) are the sources of truth; in the app, the credits are under You › About.

**Medito (the code).** Meditejo started on 2026-10-13 from [Medito](https://github.com/meditohq/medito-app), the open-source app by the [Medito Foundation](https://meditofoundation.org), under the AGPL-3.0, and keeps its player, pack view, timer, downloads and local stats. The Dart package still has the internal name `medito`. Medito’s audio catalogue, its backend, accounts, donations, shop and analytics were not carried over: that audio is proprietary to the Foundation, and none of it is in this app. Some upstream files remain. The session bell (`session_bell_v2.wav`, synthesised by `tools/generate_session_bell.py`) is under the AGPL-3.0. Most of the UI icons (all but `ic_logo.svg`, now the house mark), `placeholder.jpg`, `splashbg.png` and the onboarding illustrations in `assets/images/` are inherited from Medito unchanged, and their original source and licence are not recorded in this repository.

**Dharma Seed (talks and catalogue).** [Dharma Seed](https://dharmaseed.org) is one of the built-in catalogues: the title, teacher, retreat, length and description of every talk, which ship in the app as a snapshot and are refreshed from Dharma Seed’s unofficial API (the one its own Android app uses) when you open search or browse. The audio is never bundled or altered: it streams from Dharma Seed as recorded, and is downloaded only if you choose to. The talks are published under [CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/), so each talk, course and teacher page shows the teacher, a link back to Dharma Seed and the licence. Teacher photos load from dharmaseed.org. Meditejo is free and non-commercial, and is not affiliated with Dharma Seed.

**dhammatalks.org (Thanissaro Bhikkhu’s talks).** [dhammatalks.org](https://www.dhammatalks.org) is the second built-in catalogue: the title, date and file address of every talk in its evening and morning archives, its guided meditations and its collections (about 9,300 talks), which ship in the app as a snapshot and are kept current from the site’s RSS feeds when you open Explore. The audio is never bundled or altered: it streams from dhammatalks.org as published, and is downloaded only if you choose to. The talks are published under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/), so each talk, course and teacher page shows Thanissaro Bhikkhu, a link back to the talk’s page and the licence. Meditejo is free and non-commercial, and is not affiliated with dhammatalks.org.

**YouTube (starter playlists and imports).** The starter set includes two YouTube playlists: *Meditating with John Vervaeke* (John Vervaeke’s Lectern) and *Qualia Mastery* (Qualia Research Institute). Nothing from YouTube is bundled. The app stores a video ID and asks YouTube for a fresh audio stream each time you stream a video, using [NewPipeExtractor](https://github.com/TeamNewPipe/NewPipeExtractor) (GPL-3.0-or-later, v0.26.5) with its runtime dependencies (nanojson, jsoup, JSR-305, protobuf-javalite, Rhino), whose licences ship in the app. The extractor’s licence covers that code only. It gives no rights to any recording, and no licence from the creators is recorded here. Burooj accepts the YouTube terms-of-service risk; an app that does this can’t be on the Play Store, so Meditejo is distributed through GitHub Releases.

**Background sounds (30 loops).** Looped recordings from [BigSoundBank](https://bigsoundbank.com/) (18, all by Joseph Sardin), [Freesound](https://freesound.org/) (11) and [OpenGameArt](https://opengameart.org/) (1). 29 are CC0 and one, the Yamanote Line train by SDLx, is [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). Each was cut to a loop, set to a common loudness and re-encoded. All 30 ship inside the app. They are separate works under their own licences, not under the AGPL. The author, source, licence and changes for each are in [`assets/sounds/NOTICE`](assets/sounds/NOTICE), and in the app under You › About › Sound credits.

**Bells and pulse sounds.** The ten bells and bowls are generated in-house by [`tools/meditejo/generate_bells.py`](tools/meditejo/generate_bells.py) from modal synthesis, with no recorded samples, and the four pulse sounds by `tools/meditejo/generate_pulse_sounds.py`. Both are dedicated to the public domain under CC0 1.0. The noise colours, drones and binaural beats in the mixer are also synthesised in the app.

**Marks, palettes and generated art.** The house mark (the shelter, a roof over a resting pebble), the daily marks, the palettes and the generated covers were made for Meditejo in 2026: Burooj picked them from candidates built by the project’s own identity tools. The generators are ported to Dart from the identity exploration on `fork/mark-explore`, and the choices are recorded in [docs/fork/DECISIONS.md](docs/fork/DECISIONS.md). They are not taken from another app, though the breathing mark was prompted by Claude’s Duet icon (a source of inspiration only). They live in this repository with the app code.

**Fonts.** [Google Sans](https://fonts.google.com/specimen/Google+Sans) under the [SIL Open Font License 1.1](assets/fonts/google-sans/OFL.txt).

**Libraries.** The native audio engine behind the Sounds mixer ([flutter_soloud](https://pub.dev/packages/flutter_soloud) with SoLoud, miniaudio, dr_libs, PFFFT, Signalsmith Stretch and Linear, and the libogg, libvorbis, libopus and libFLAC codecs) has its notices in [`assets/licenses/`](assets/licenses/). Flutter and the other Dart packages are listed in [`pubspec.yaml`](pubspec.yaml), and the app’s Licenses page (You › About › Open-source licences) shows the full list with their licence texts.

## Licence

App code is licensed under [AGPL-3.0](LICENSE). Upstream notices are preserved. Source: [beejsbj/meditejo](https://github.com/beejsbj/meditejo).
