<!-- Scout report, 2026-10-14 (Sonnet subagent, web research; licences read on primary pages, sounds not auditioned). -->

# Audio scouting report for the open-source Medito fork (2026-10-14)

**Summary:** Freesound CC0 is the best source. I found no ready-made CC0 stem library. Noise colours should be synthesized, not shipped as files. "Verified" below means I read the license on the primary page, either the Freesound sound page or the project's own licensing file.

## Ranked recommendations

**1. Freesound, filtered to CC0.** This is the main source.
- Each CC0 page says the sound can be copied, modified, distributed and used commercially without asking, and attribution is optional.
- Freesound does not list loopability, so I only trust "loop" claims that the uploader makes in the description. Anything else needs your own crossfade.
- Per-sound licenses vary, even within one uploader's work. felix.blume's bio says "most" are CC. Check every file's page. For CC-BY files, list them in the app's credits screen.
- Freesound throttled me (HTTP 429) partway through, so I verified fewer candidates than I wanted.

**2. BigSoundBank (Joseph Sardin).** The singing bowl page I read (s1109) says "CC0 (public domain)", attribution not required. It is mono, 48 kHz/16-bit, 44 s, and downloadable as WAV, OGG, FLAC and more. A search result lists a church bell (s3445) as CC0 too, but I did not open its page.

**3. OpenGameArt.** Per-file licenses, so check each page.
- Ylmir's ["Rain (loopable)"](https://opengameart.org/content/rain-loopable) is CC0: four loopable rain clips of 25–45 s, in MP3 and OGG.
- alxl's ["Rain on Window Loop"](https://opengameart.org/content/rain-on-window-loop) is multi-licensed (CC-BY 4.0, CC-BY 3.0, OGA-BY 3.0, CC0) and only about 11 s long.

**4. Open-source apps (use as leads, not as license proof).**
- **Blanket (GNOME).** Its [SOUNDS_LICENSING.md](https://raw.githubusercontent.com/rafaelmardojai/blanket/master/SOUNDS_LICENSING.md) gives a per-sound author, license and source URL.
  - CC0: birds (kvgarlic), boat (Falcet), stream (gluckose), wind (felix.blume).
  - CC-BY: rain (alex36917), storm (digifishmusic), waves (Luftrum), city, train.
  - Public Domain: SoundBible fireplace, crickets and coffee shop.
  - **Avoid:** its pink and white noise are CC-BY-SA, and the sounds as a whole sit in a GPL app.
  - This is the best-documented set I found. The CC0 and CC-BY entries are usable if you go to each Freesound page directly. I checked the gluckose stream and kvgarlic birds there and both are CC0.
- **Moodist** (MIT code). Its README says only that "some sounds" are Pixabay Content License and "others" CC0. There is no per-file mapping, so its audio can't be audited. Do not copy from it.
- **Noice** (GPL-3.0 code). I found no audio license or credits file in the app repo or in the org's other repos. Treat its sounds as unlicensed for our purposes.
- I did not check Anoise.

## Do not bundle

- **Pixabay.** Credit is not required, but the [license summary](https://pixabay.com/service/license-summary/) bans distributing content "on a Standalone basis". Raw files in a public GitHub repo arguably do that, and the summary doesn't mention apps.
- **Sonniss GDC.** Apps are permitted, but [redistributing the sounds "as sound effects"](https://sonniss.com/gameaudiogdc) is not, and AI/ML training use is prohibited. Putting the raw files in an AGPL repo that anyone can fork conflicts with that.
- **BBC Sound Effects.** Search results say it is a RemArc license limited to personal, educational and research use. I could not fetch the BBC's own licence text (the fetch failed). Treat it as not bundlable.
- **CC-BY-SA** (Wikimedia noise files): the license compatibility with AGPL is murky, and you can synthesize noise instead.
- **CC-BY-NC:** excluded.
- I did not research Internet Archive, NASA or Wikimedia Commons.

## Procedural options

- **Noise colours.** White, pink and brown are a few lines of Dart or C++ each: Voss-McCartney for pink, and a leaky integrator on white noise for brown.
- **flutter_soloud** (MIT plugin, [pub.dev](https://pub.dev/packages/flutter_soloud)).
  - It runs on Android 21+ and offers gapless looping with region control, filters and mixing buses.
  - It generates sine, square, saw and triangle waveforms, which is enough for drones and binaural tones.
  - The SoLoud engine is zlib/libpng, and its bundled decoders are public domain or Unlicense.
  - SoLoud's C++ has a `Noise` class (white, pink, brown-ish, blue-ish), but I found no sign the Flutter wrapper exposes it.
  - I could not confirm that it accepts raw PCM streams.
  - Check both against its API docs. Otherwise write a small native or FFI generator.
- **Faust:** I could not reach its license page, so its licensing is unverified.
- Gapless looping plus per-layer volume gives you most of the mixing a myNoise-style mixer needs. Individual loops (rain, wind, thunder, each as its own file) stand in for stems.

## Suggested starter set (all CC0 unless noted, license read on each page)

**Soundscapes**
1. Rain, indoors: [samesamesame](https://freesound.org/people/samesamesame/sounds/242889/). 48 s, described as a "perfect loop", WAV 24-bit.
2. Rain, balcony: [unfa](https://freesound.org/people/unfa/sounds/177479/). 73 s, described as seamless, FLAC, with a distant dog bark and passing cars.
3. Ocean: [kkenny101](https://freesound.org/people/kkenny101/sounds/852826/). 22 s seamless loop, mono, 48 kHz.
4. Stream: [gluckose](https://freesound.org/people/gluckose/sounds/333987/). 2:36, needs a crossfade, has birdsong in it.
5. Wind: [felix.blume](https://freesound.org/people/felix.blume/sounds/217506/). 3:32, 96 kHz/24-bit WAV, so downsample it.
6. Fire: [samarobryn](https://freesound.org/people/samarobryn/sounds/414767/) (60 s). Alternative: [Sauron974](https://freesound.org/people/Sauron974/sounds/204348/) (1:35, crickets audible).
7. Forest birds: [kvgarlic](https://freesound.org/people/kvgarlic/sounds/156826/). Wood thrush at dawn, 2:12, needs a crossfade.
8. Night crickets and sea: [felix.blume](https://freesound.org/people/felix.blume/sounds/479041/). 8:45 binaural, but 289 MB as WAV, so trim and encode it.
9. Drone: [kkenny101](https://freesound.org/people/kkenny101/sounds/860432/). 37 s, evolving, PaulStretch-processed, with a meditation use stated in the description.
10. Rain, window: Ylmir's OpenGameArt pack, linked above.
11. Singing bowl, long: [hollandm](https://freesound.org/people/hollandm/sounds/573805/). 2:07 rim-played, no reverb.
12. Singing bowl, struck: [BigSoundBank s1109](https://bigsoundbank.com/tibetan-bowl-singing-s1109.html). 44 s.
13. Noise colours: synthesize in code.

**Bells**
- [fauxpress, "Bell Meditation"](https://freesound.org/people/fauxpress/sounds/42095/): small bell, single stroke, 30 s, mono MP3. Good start/end cue.
- [JetRye, cleaned version](https://freesound.org/people/JetRye/sounds/140128/): the same bell cleaned up, 17 s, mono WAV.
- [tec_studio, temple bell](https://freesound.org/people/tec_studio/sounds/668647/): 1532 bronze Japanese bell, about 13 s, 24-bit. Good for interval cues.

**Optional CC-BY:** [the_very_Real_Horst's 5-minute bowl](https://freesound.org/s/206034), CC BY 4.0. Needs a credit.

**Gaps:** I found no verified CC0 thunder or gong. Fire and forest were checked less thoroughly than the rest. I did not audition any of these by ear.
