# Slice 6: cues and Customize

Branch `fork/cues`, PR https://github.com/beejsbj/meditejo/pull/14.

## Progress

- [x] Read fork decisions, architecture and existing playback seams.
- [x] Shared cue configuration and deterministic scheduling maths.
- [x] Defaults per Practice/Talks, optional course overrides, timer migration.
- [x] Native Android execution with countdown, extension and end-bell tail.
- [x] Swift scheduler and Flutter transport hookup (unbuilt on iOS).
- [x] Persisted distinct heard ranges and 90% completion, separate from EOF.
- [x] Shared Customize surface in player and timer, live finish estimate.
- [x] Four original bundled pulse sounds, reproducible generator and notice.
- [x] Scheduler, coverage, persistence, widget and native maths tests written.
- [ ] Final hosted analyze/serial tests/full suite and signed APK receipt.

## Verification and limits

- Local Pigeon/build_runner codegen passed through the heavy-job queue.
- Portable Flutter checks were unavailable (Daytona exit 125 before execution).
  Hosted `Cue checks` runs affected files one at a time with a 1200-second
  timeout; the existing Flutter workflow runs the full suite.
- The native worker ran 28 pure JVM tests through the queue; later coverage
  persistence tests are included in the hosted APK test gate.
- No local Gradle, phone operation or release publication was performed.
- iOS remains unbuilt. Native deadline maths does not prove acoustic latency;
  a real screen-off sit and speaker/Bluetooth timing remain device checks.
- The existing ambient catalogue is empty. Practice defaults enabled, Talks
  disabled; the next soundscape slice supplies playable presets.
- New Customize labels are English, retaining the current Medito styling.

Implementation choices and the runtime seams are recorded in DECISIONS.md
and ARCHITECTURE.md.
