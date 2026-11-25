# Pass 4: the player (2026-11-25)

From Burooj's 14 Nov walkthrough of the staging build and his listening notes. All reversible.

## What changed

- **One look for every player.** He said: "The guided player should look like the timer player: controls at the bottom, no wallpaper." The recording player no longer has a blurred cover or moving art filling the screen. Every session uses the same dark backdrop. The figure sits at the top, the title under it, and the controls at the bottom.
  - A timer's figure is the day's mark, as before. A recording's figure is its cover, sharp and with rounded corners. With no cover, or when the cover fails to load, it is the session's art (or the course's), moving.
  - The figure takes whatever height the title and controls leave, up to 320 dp. On a short screen it shrinks, and it is dropped below 96 dp. The landscape-phone layout still has no figure.
- **The bar spreads across.** The five slots are now Close · Download · Sound · Speed · Customize. A timer fills Close, Sound and Customize, so they sit at the left edge, the middle and the right edge instead of bunching at the left. Close, Sound and Customize are in the same places for every session, as decided on 2026-11-10. Download and Speed now sit between them instead of at the right.
- **Less space between the mark and the title.** The title now sits 8 dp under the figure, with less padding above it. A timer has no artist, so the empty artist line under its title is gone.
- **The spinning disc in the timer.** The Sound button already showed the spinning disc for the Sounds mixer in every player. It now also spins while a **Rhythm pulse** plays and the session is running.
  - **My call:** the mixer path was already the same in both players, so the one sound a timer had that left the disc still was most likely its rhythm. If what he heard was a mixer sound, this is the wrong fix and needs the phone.
- **Start goes straight to the countdown.** He said: "Starting a timer sit shows the player, then jumps to the skip-countdown screen, then starts. It should go straight from one to the other." The countdown screen now covers the player from its first frame. Until the native countdown begins, it shows the full length. For a guided session it covers the player as soon as the pre-start Customize sheet closes with Start.
  - Tapping Skip before the native countdown has begun shows the player at once. The countdown is skipped as soon as it begins.
  - If the cue state cannot be read, the cover is lifted, so it can never hide the player for good.
- **Sleep timer in every recording player.** He gave the example of "falling asleep five minutes into a talk". A **Sleep** button sits under the transport, beside Autoplay. It opens a sheet with 5, 10, 15 or 30 min and End of track. While a sleep timer is set, the button shows the time left (for example 9:58) or "End of track" in Autoplay's highlight. The sheet then also offers Turn off. Timer and ∞ sits have no sleep timer.
  - **It runs in the Android audio service, not in the widget.** The cue channel has three new calls: `sleep(ms)`, `cancelSleep` and `sleepRemainingMs`. `AudioPlayerService` keeps the time with a `Handler`, on `SystemClock.elapsedRealtime`. Over the last 10 s it lowers the voice's volume, then pauses the session as the pause button would, and puts the volume back. It keeps working with the screen off and with Flutter not drawing. The Dart side (`sleepTimerProvider`) keeps its own timer only to clear the button.
  - **A pause, not an ending (my call).** When a sleep timer runs out, the session pauses on the player, and he can resume it in the morning. It is not recorded as a completed sit. The existing 90%-heard rule still counts the session if he heard that much.
  - **End of track** lets the recording finish normally, which is a real completion. It turns repeat off and stops Autoplay from starting the next session. No fade: the recording's own ending and the end bell stay as they are.
  - **Wall clock (my call).** A 10-minute sleep timer ends 10 minutes after it was set, even if he pauses in between. This matches common players. It carries over into an Autoplay next session. Closing the player, the end screen, or opening a new player cancels it.

## Known limits

- The day's mark leaves room inside its own square: the house mark is drawn in about the middle half of it. That margin still reads as space between the mark and the title (about 70 dp on a large phone). A tighter fit would need each mark's drawn bounds.
- Only the voice fades. The Sounds mixer fades on its own as it pauses with the session. During Extend's silence there is no voice to fade, so the mixer just pauses with its own fade.
- iOS (shelved) and desktop pause from a Dart timer, without a fade (`shortcut:` noted in `sleep_timer_provider.dart`).
- The new Kotlin (`AudioPlayerService` sleep timer, `CueChannel`) is not compiled by the `checks` CI. It compiles only in the APK build.
- The countdown screen's "Skip countdown" text is still English, as before.

## Needs the phone

- A sleep timer with the screen off: whether it fades over about 10 s and pauses, and whether the notification shows paused.
- Whether the timer's disc now spins for the sound he meant.
- Starting a timer from Home and from a pinned preset: no flash of the player before the countdown.
- How a cover photo (YouTube, a channel) looks as the figure, and how the moving art looks at figure size.
