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
- [x] Final hosted analyze/serial tests/full suite and signed APK receipt.

## Verification and limits

- Local Pigeon/build_runner codegen passed through the heavy-job queue.
- Portable Flutter checks were unavailable (Daytona exit 125 before execution).
  Hosted `Cue checks` runs affected files one at a time with a 1200-second
  timeout; the existing Flutter workflow runs the full suite.
- Code commit `a1d5cfcf`: analyze clean; 78 affected tests in 14 serial files;
  all 1,071 Flutter tests passed. Hosted native gate: 83 passed, including
  26 cue maths/listening tests, with zero failures or errors.
- Signed APK: `/home/admin/.local/share/meditejo/apk/meditejo-cues-a1d5cfcf.apk`
  (62,559,665 bytes). The build receipt verifies the code commit and pinned
  signing certificate; all six cue WAV/NOTICE entries match the sources
  byte-for-byte. Final workflow: https://github.com/beejsbj/meditejo/actions/runs/39313709640.
- Flutter verification: https://github.com/beejsbj/meditejo/actions/runs/39313634697;
  serial checks: https://github.com/beejsbj/meditejo/actions/runs/39313634720.
- No local Gradle, phone operation or release publication was performed.
- iOS remains unbuilt. Native deadline maths does not prove acoustic latency;
  a real screen-off sit and speaker/Bluetooth timing remain device checks.
- Background sound now chooses from the slice 7 sound library through the
  mixer (DECISIONS, slice 7, "Customize and the mixer"). Practice defaults
  enabled, Talks disabled.
- New Customize labels are English, retaining the current Medito styling.

Implementation choices and the runtime seams are recorded in DECISIONS.md
and ARCHITECTURE.md.
