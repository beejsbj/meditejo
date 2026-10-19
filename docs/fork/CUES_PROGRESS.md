# Slice 6: cues and Customize

Implementation checkpoint for `fork/cues`.

## Progress

- [x] Read the fork decisions and existing playback seams.
- [ ] Shared cue model, deterministic scheduler and scoped defaults.
- [ ] Native Android execution and Swift parity; real-listening completion.
- [ ] Shared Customize sheet in player and timer.
- [ ] Bundled generated pulse assets and notices.
- [ ] Analyze, focused tests, native maths tests and signed APK.

## Reversible implementation choices

- Cue configuration crosses a dedicated `meditejo/cues` method channel; existing playback Pigeon APIs stay focused on transport.
- Pulse settles linearly in BPM over session time; beat deadlines come from the integral of that ramp, so polling does not accumulate drift.
- Interval randomness uses a seeded generator and bounded gaps around the selected interval; no cue at or beyond the session end.
- Completion records listening separately from the terminal player state; crossing 90% must not interrupt a playing session.
