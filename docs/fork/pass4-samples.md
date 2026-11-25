# Pass 4: samples (Wind chimes and Chirp regenerated)

## 2026-11-25 (staging pass 4: two cue samples regenerated, #76 follow-up)

- **Why:** Burooj, listening on the phone (14 Nov): "Wind chimes sounds like one high note, not chimes. Regenerate it." and "Chirp is still a little fake; regenerate it." Heartbeat and Footstep stay as they are (byte-identical; `process.py` rebuilds them to the recorded hashes).
- **Same paths, same ids.** `assets/audio/bell_chime.wav` and `assets/audio/pulse_chirp.wav` are replaced in place, so every stored setting plays the new sound with nothing migrated. Names are unchanged ("Wind chimes", "Chirp").
- **Source and licence: as on 2026-11-11.** ElevenLabs text-to-sound-effects, `eleven_text_to_sound_v3`, loop off, on Burooj's paid Creator plan, dedicated CC0-1.0. `tools/meditejo/cue_samples.json` (model, prompt, take, date, plan, cut, measurements, sha256) and `assets/audio/NOTICE` carry the new records. `generate_bells.py --check` and `generate_pulse_sounds.py --check` pass against the new hashes; `test/models/cues/cue_samples_test.dart` passes.
- **Credits.** 13 takes, 45.1 s requested (7 chime takes of 6 s, 6 chirp takes of 0.5 or 0.7 s). The account's usage counter moved by 504 credits (14,150 to 14,654). At the 66-a-second rate last time's notes used as an estimate it would be about 2,980. Either way it is inside the 3,000 budget.
- **Nobody has listened to these.** I cannot hear. Takes were chosen by measurement alone, and whether they sound right is Burooj's to say on the phone. Either file goes back to its old version by reverting that WAV and its record.
- Raw takes, `records.jsonl`, the cut script (`process.py`; the 2026-11-11 run is kept as `process_2026-11-11.py`) and the two new measuring scripts (`pitches.py`, `chirp.py`) are in `Projects/sfx-pilot/cues` on bjslab, as before.

### Wind chimes (take 4 of 10)

- **What was wrong, measured.** The old take (chime-1) has two strong pitches, about 991 and 1179 Hz, 5 dB apart; every other partial is 22 dB or more below. That is "one high note" with a second one under it.
- **Prompts.** Two prompts asked for a set of five or six aluminium tubes, low to high, struck at random over the first few seconds, overlapping, then ringing out; no wind noise, no rumble. The chosen take's prompt is in the record.
- **Measure used.** `pitches.py` finds the spectral peaks within 30 dB of the loudest (250 Hz to 6 kHz, 3% apart), folds a struck tube's overtones (about 2.76 and 5.40 times a lower peak) into their tube, and counts the pitches within 15 dB of the loudest. For each pitch it also finds when it is first struck and how often.
- **Chosen: take 4.** Five pitches within 15 dB of each other: 614, 818, 1055, 1190 and 1626 Hz (the old take reached 991/1179). The lowest note is now 614 Hz instead of 991. Six strikes, at 0.10, 0.44, 0.70, 0.80, 1.35 and 3.19 s, so they are spread over the first three seconds and do not repeat a pattern. Then it rings out: about 40 dB under its loudest by 5 s and 60 dB under by 5.6 s. Its quiet floor is 66 dB under the peak, with take 6 the cleanest of the takes, and only 1% of its energy is under 200 Hz.
- **The losing takes** (pitches within 15 dB, strike times, why not):
  - take 5: 3 (662, 872, 1174 Hz); strikes 0.19 to 1.95 s; fewer pitches.
  - take 6: 3 (624, 937, 1055 Hz); strikes 0.22, 0.35, 0.54, 2.31 s; fewer pitches, the strikes bunched at the start.
  - take 7: 5 (657, 738, 834, 980, 1098 Hz), but one onset only (a swell, not separate strikes), and 25% of its energy under 200 Hz (rumble).
  - take 8: 3 (781, 974, 1179 Hz); 19% under 200 Hz; a late strike at 4.2 s.
  - take 9: 5 (619, 931, 1034, 1174, 1610 Hz), but its strikes are all in the first 0.3 s and one at 4.4 s.
  - take 10: 5 (614, 775, 1050, 1174, 1572 Hz) and seven strikes, the runner-up; but one strike falls at 4.8 s, leaving under a second of ring-out, and 12% of its energy was under 200 Hz.
- **Cut and level.** Cut 0.07 to 5.8 s, high-passed at 300 Hz, faded out over the last 1.4 s, mono 16-bit, 22.05 kHz (5.73 s, 247 KiB), levelled like every bell to −9.84 LUFS momentary (the session bell's loudest 400 ms K-weighted block), peak −1.0 dBFS.
- **Peak limiting: my call.** Separate strikes of several tubes have sharp peaks: this take's peaks sit about 15 dB over its loudness, where the old take's sat 8.5 dB over. The −1 dBFS ceiling alone would have left the new chime about 6 dB quieter than the other bells (−15.9 LUFS). So `process.py` runs a lookahead peak limiter on this file only (5 ms lookahead, 20 ms release). It turns down 19 of the 445 audible 10 ms blocks by more than 1 dB and 10 by more than 3 dB (the deepest by 9.6 dB): only the first moments of the strikes. A slower release (120 ms) would have ducked 88 blocks and dulled the strikes, so I did not use it. If the strikes sound squashed, the other way is to leave it 6 dB quieter than the other bells; that is a one-line change in `process.py`.

### Chirp (take 11 of 14)

- **What was wrong, measured.** `chirp.py` measures each 5 ms frame of the call. The old chirp (take 7 of 2026-11-11) is close to a pure whistle: its second harmonic is 51 dB under the fundamental, its spectral spread is 232 Hz, its flatness is 0.000, and its pitch moves over only 360 Hz. That fits "a little fake".
- **Prompts.** One asked for a real wild house sparrow's single, slightly raspy call, recorded outdoors, "not electronic, not a whistle" (0.5 s, three takes). The other asked for a finch- or sparrow-like "chip" with a little rasp and pitch bend (0.7 s, three takes).
- **Chosen: take 11.** One call, 0.21 s of it within 30 dB of its loudest point. Its pitch falls from about 5.5 to 3.5 kHz with an irregular wobble: the frame-to-frame jitter is 129 Hz, against 22 Hz (the analysis resolution, so a smooth glide) in the old chirp. Its second harmonic is 20 dB under the fundamental (the old one's was 51 dB under). Spread 810 Hz, flatness 0.028 (a little rasp). Its quiet floor is 49 to 51 dB under the peak, the lowest of the six.
- **The losing takes:**
  - take 9 (same prompt): pitch range 1751 Hz, jitter 86 Hz, spread 730 Hz, flatness 0.011, harmonic −21 dB, floor −46 dB. Close, but smoother and noisier.
  - take 10 (same prompt): range 1593 Hz, jitter 22 Hz (a smooth glide), spread 951 Hz, flatness 0.029, harmonic −22 dB, floor −45 dB. The runner-up.
  - takes 12, 13, 14 (the "chip" prompt): second harmonic only 39 to 48 dB under, spread 213 to 316 Hz, flatness 0.000 to 0.002. They are whistles like the old one, so they lost.
- **Cut and level.** Cut 0 to 0.4 s, high-passed at 1500 Hz, faded in over 4 ms and out over the last 0.12 s, mono 16-bit, 44.1 kHz. Levelled to −25.71 LUFS on the loudest 400 ms K-weighted block, as the old chirp was, so it plays at the same loudness; peak −10.8 dBFS.
- **Known limit.** The take begins only about 25 dB under its loudest point at its first sample, so the attack may be slightly clipped by the generator. The 4 ms fade-in removes any click, and the file starts and ends on zero (tested), but the onset may sound abrupt.
- **The tail.** After the call the take decays from −20 to −60 dB over about 0.3 s. That may be room sound in the generated take, though the prompt asked for none. The cut keeps 0.19 s of it under the fade.

### Needs the phone

- Do Wind chimes now sound like several tubes, and do the strikes sound natural after the limiting?
- Is Chirp now a bird and not a notification? Is its start abrupt?
- Is Wind chimes as loud as the other bells, and Chirp as loud as Heartbeat and Footstep?
