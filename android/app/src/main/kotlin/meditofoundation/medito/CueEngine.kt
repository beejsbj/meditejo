@file:androidx.media3.common.util.UnstableApi
package meditofoundation.medito

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.media3.common.Player

/**
 * One scheduler for every cue of a session: countdown, start bell, interval
 * bells, pulse, extension and end bell. Runs in the playback service on the
 * main looper, so the screen being off changes nothing.
 *
 * The timeline is session time (see [CueMath]). It is read from the player's
 * media clock while the voice plays, and from the monotonic clock during the
 * countdown and the extension, so pause and buffering freeze it, a seek jumps
 * it without a burst of missed cues, and speed is accounted for.
 */
internal class CueEngine(
    private val context: Context,
    private val primary: Player,
    private val host: Host,
) : Player.Listener {

    interface Host {
        /** The countdown is over (or skipped): start the narration now. */
        fun startNarration()

        /** The session reached its true end. [tailMs] is how long the end bell still rings. */
        fun onSessionEnded(extensionFinished: Boolean, tailMs: Long)
    }

    enum class Phase { IDLE, COUNTDOWN, PLAYING, EXTENSION, ENDED }

    private val handler = Handler(Looper.getMainLooper())
    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "meditejo:cues")
        .apply { setReferenceCounted(false) }

    private var bank: CueSoundBank? = null
    var config: CueConfig? = null
        private set
    var phase = Phase.IDLE
        private set

    // Countdown and extension run on the monotonic clock. A zero anchor means held.
    private var holdRemainingMs = 0L
    private var holdAnchor = 0L

    // Session time.
    private var started = false
    private var sessionMs = 0.0
    private var lastPositionMs = 0L
    private var lastRealMs = 0L
    private var extensionStartSessionMs = 0.0

    private var intervalIndex = Long.MAX_VALUE
    private var intervalAtMs = Double.MAX_VALUE
    private var beatNumber = Long.MAX_VALUE
    private var beatAtMs = Double.MAX_VALUE
    private val halfway = HalfwayCue()
    // The halfway deadline as of the last fireDue (the end is only known there).
    private var halfwayAtMs = Double.MAX_VALUE

    private var interludeReady: Runnable? = null

    // With autoplay the interlude starts at the session end, before Dart has
    // resolved the next session: when it ends (0: none), and when the end
    // bell stops ringing.
    private var interludeEndsAt = 0L
    private var tailEndsAt = 0L
    private val tick = Runnable { run() }
    private val cleanup = Runnable {
        releaseWake()
        if (phase == Phase.ENDED) { bank?.release(); bank = null; config = null; phase = Phase.IDLE }
    }

    init { primary.addListener(this) }

    val isEngaged: Boolean get() = config != null && phase != Phase.IDLE && phase != Phase.ENDED
    val isTimer: Boolean get() = config?.isTimer == true

    // ---- Lifecycle -------------------------------------------------------

    /** Applies a configuration. Mid-session it re-arms the cues from where the session is. */
    fun configure(cfg: CueConfig) {
        val live = phase == Phase.PLAYING || phase == Phase.EXTENSION || phase == Phase.COUNTDOWN
        if (!live) stopTimers()
        if (phase == Phase.EXTENSION) {
            val elapsed = (config?.extensionMs ?: 0L) - heldRemaining()
            holdRemainingMs = (cfg.extensionMs - elapsed).coerceAtLeast(0L)
            if (holdAnchor != 0L) {
                holdAnchor = SystemClock.elapsedRealtime()
                // The lock was sized for the old length: re-time it to the new one.
                acquireWake(holdRemainingMs + WAKE_SLACK_MS)
            }
        }
        config = cfg
        val sounds = bank ?: CueSoundBank(context).also { bank = it }
        listOf(cfg.startSound, cfg.endSound, cfg.intervalSound, cfg.pulseSound).forEach { sounds.preload(it) }
        if (live && started) {
            armAll(sessionMs, fresh = false)
            kick()
        } else if (!live) {
            phase = Phase.IDLE
            started = false
        }
    }

    /** playAudio is about to start a track: the session begins from nothing. */
    fun prepareSession() {
        if (config == null) return
        stopTimers()
        started = false
        sessionMs = 0.0
        phase = Phase.PLAYING
    }

    /**
     * Called when the voice is ready to play. Returns true when a countdown
     * took over: the service must not play until [Host.startNarration].
     */
    fun beginCountdown(): Boolean {
        val cfg = config ?: return false
        if (phase != Phase.PLAYING || started || cfg.countdownMs <= 0) return false
        phase = Phase.COUNTDOWN
        holdRemainingMs = cfg.countdownMs
        holdAnchor = SystemClock.elapsedRealtime()
        acquireWake(cfg.countdownMs + WAKE_SLACK_MS)
        handler.removeCallbacks(tick)
        handler.post(tick)
        return true
    }

    fun skipCountdown() {
        if (phase == Phase.COUNTDOWN) finishCountdown()
    }

    /** Cancels every timer and sound. The session is over or abandoned. */
    fun stop() {
        stopTimers()
        halfway.disarm()
        phase = Phase.IDLE
        started = false
        config = null
        bank?.release()
        bank = null
    }

    fun release() {
        stop()
        primary.removeListener(this)
    }

    fun holdInterlude(seconds: Int, ready: () -> Unit) {
        val full = seconds.coerceIn(0, 30) * 1000L
        // Already counting since the session end: wait only for what is left.
        val delay = if (interludeEndsAt != 0L) {
            (interludeEndsAt - SystemClock.elapsedRealtime()).coerceIn(0L, full)
        } else full
        interludeEndsAt = 0L
        handler.removeCallbacks(cleanup)
        interludeReady?.let { handler.removeCallbacks(it); it.run() }
        acquireWake(delay + WAKE_SLACK_MS)
        val callback = Runnable { interludeReady = null; ready() }
        interludeReady = callback
        handler.postDelayed(callback, delay)
        handler.postDelayed(cleanup, delay + WAKE_SLACK_MS)
    }

    /**
     * Dart will not autoplay after all, or the listener left: drop the
     * interlude (begun at the session end or by [holdInterlude]) and keep only
     * the end bell's tail. False when no session has just ended.
     */
    fun endInterlude(): Boolean {
        if (phase != Phase.ENDED) return false
        interludeEndsAt = 0L
        interludeReady?.let { handler.removeCallbacks(it); it.run() }
        interludeReady = null
        val tail = tailRemainingMs()
        handler.removeCallbacks(cleanup)
        acquireWake(tail + WAKE_SLACK_MS)
        handler.postDelayed(cleanup, tail + 500)
        return true
    }

    fun tailRemainingMs(): Long = (tailEndsAt - SystemClock.elapsedRealtime()).coerceAtLeast(0L)

    /** How long the service must stay for the autoplay interlude; 0 when none runs. */
    fun interludeHoldMs(): Long =
        if (interludeEndsAt == 0L) 0L
        else (interludeEndsAt - SystemClock.elapsedRealtime()).coerceAtLeast(0L) + WAKE_SLACK_MS

    private fun stopTimers() {
        interludeEndsAt = 0L
        interludeReady?.let { handler.removeCallbacks(it); it.run() }
        interludeReady = null
        handler.removeCallbacks(tick)
        handler.removeCallbacks(cleanup)
        releaseWake()
        holdAnchor = 0L
        holdRemainingMs = 0L
    }

    // ---- Queries ---------------------------------------------------------

    private fun heldRemaining(): Long {
        if (holdAnchor == 0L) return holdRemainingMs.coerceAtLeast(0)
        return (holdRemainingMs - (SystemClock.elapsedRealtime() - holdAnchor)).coerceAtLeast(0)
    }

    fun countdownRemainingMs(): Long = if (phase == Phase.COUNTDOWN) heldRemaining() else 0L
    fun extensionRemainingMs(): Long = if (phase == Phase.EXTENSION) heldRemaining() else 0L

    /** True during the countdown or extension while their clock is actually running. */
    fun isHoldRunning(): Boolean = (phase == Phase.COUNTDOWN || phase == Phase.EXTENSION) && holdAnchor != 0L

    /** The session has an extension still to come or under way. */
    fun hasExtension(): Boolean = (config?.extensionMs ?: 0L) > 0L && phase != Phase.ENDED

    fun endTailMs(): Long = bank?.tailMs(config?.endSound) ?: 0L

    fun state(): Map<String, Any?> = mapOf(
        "phase" to phase.name.lowercase(),
        "countdownRemainingMs" to countdownRemainingMs(),
        "extensionRemainingMs" to extensionRemainingMs(),
        "sessionMs" to sessionMs.toLong(),
        "paused" to ((phase == Phase.COUNTDOWN || phase == Phase.EXTENSION) && holdAnchor == 0L),
    )

    /**
     * Pause or resume the countdown or extension, which the player's own
     * pause button cannot reach. Returns false when neither is running.
     */
    fun toggleHold(): Boolean {
        if (phase != Phase.COUNTDOWN && phase != Phase.EXTENSION) return false
        if (holdAnchor != 0L) {
            holdRemainingMs = heldRemaining()
            holdAnchor = 0L
            handler.removeCallbacks(tick)
            releaseWake()
            bank?.pauseAll()
        } else {
            holdAnchor = SystemClock.elapsedRealtime()
            acquireWake(holdRemainingMs + WAKE_SLACK_MS)
            bank?.resumeAll()
            kick()
        }
        return true
    }

    // ---- The loop --------------------------------------------------------

    private fun kick() {
        handler.removeCallbacks(tick)
        handler.post(tick)
    }

    private fun run() {
        try {
            when (phase) {
                Phase.COUNTDOWN -> runCountdown()
                Phase.PLAYING -> runPlaying()
                Phase.EXTENSION -> runExtension()
                else -> Unit
            }
        } catch (e: Exception) {
            Log.e(TAG, "Cue tick failed: ${e.message}", e)
        }
    }

    private fun runCountdown() {
        if (holdAnchor == 0L) return
        val remaining = heldRemaining()
        if (remaining <= 0) finishCountdown() else handler.postDelayed(tick, minOf(remaining, 250L))
    }

    private fun finishCountdown() {
        releaseWake()
        holdAnchor = 0L
        holdRemainingMs = 0L
        phase = Phase.PLAYING
        host.startNarration()
        kick()
    }

    private fun runPlaying() {
        val cfg = config ?: return
        if (!primary.isPlaying) return // frozen: events kick the loop when it resumes
        val position = primary.currentPosition
        val speed = primary.playbackParameters.speed.toDouble()
        val now = SystemClock.elapsedRealtime()
        if (!started) {
            started = true
            sessionMs = CueMath.advance(0.0, 0, position, speed)
            armAll(sessionMs, fresh = sessionMs <= 0.0)
            if (CueMath.shouldRingStart(position)) bank?.play(cfg.startSound, cfg.bellVolume)
        } else {
            val delta = position - lastPositionMs
            sessionMs = CueMath.advance(sessionMs, lastPositionMs, position, speed)
            if (CueMath.isSeek(delta, now - lastRealMs, speed)) armAll(sessionMs, fresh = false)
        }
        lastPositionMs = position
        lastRealMs = now
        fireDue(remainingEndMs(speed))
        scheduleNext()
    }

    private fun runExtension() {
        val cfg = config ?: return
        if (holdAnchor == 0L) return
        val remaining = heldRemaining()
        sessionMs = extensionStartSessionMs + (cfg.extensionMs - remaining)
        if (remaining <= 0) {
            finishSession(extensionFinished = true)
            return
        }
        fireDue(extensionStartSessionMs + cfg.extensionMs)
        scheduleNext(maxDelayMs = remaining)
    }

    /** Session time at which the session ends, or null when it has no known end. */
    private fun remainingEndMs(speed: Double): Double? {
        val cfg = config ?: return null
        val duration = primary.duration.takeIf { it > 0 } ?: cfg.durationMs
        val items = primary.mediaItemCount
        val after = if (items > 0) items - 1 - primary.currentMediaItemIndex else 0
        val endless = primary.repeatMode == Player.REPEAT_MODE_ONE
        val remaining = CueMath.remainingSessionMs(
            primary.currentPosition, duration, speed, after.coerceAtLeast(0), endless, cfg.extensionMs,
        ) ?: return null
        return sessionMs + remaining
    }

    private fun armAll(atMs: Double, fresh: Boolean) {
        armInterval(atMs)
        armPulse(atMs, fresh)
        armHalfway()
    }

    /** Re-armed by every arm (a seek back before the midpoint rings it again when crossed). */
    private fun armHalfway() {
        if (config?.hasHalfway == true) halfway.arm() else halfway.disarm()
        halfwayAtMs = Double.MAX_VALUE // recomputed by the next fireDue
    }

    private fun armInterval(atMs: Double) {
        val cfg = config ?: return
        if (cfg.hasInterval) {
            intervalIndex = CueMath.firstIntervalAfter(atMs, cfg.intervalMinutes, cfg.randomWindowMinutes, cfg.randomSeed)
            intervalAtMs = CueMath.intervalTime(cfg.intervalMinutes, cfg.randomWindowMinutes, cfg.randomSeed, intervalIndex).toDouble()
        } else {
            intervalIndex = Long.MAX_VALUE
            intervalAtMs = Double.MAX_VALUE
        }
    }

    private fun armPulse(atMs: Double, fresh: Boolean) {
        val cfg = config ?: return
        if (cfg.hasPulse) {
            beatNumber = if (fresh) 1 else CueMath.firstBeatAfter(atMs, cfg.pulseBpm, cfg.pulseEndBpm, cfg.pulseRampMinutes)
            beatAtMs = CueMath.beatTime(beatNumber, cfg.pulseBpm, cfg.pulseEndBpm, cfg.pulseRampMinutes)
        } else {
            beatNumber = Long.MAX_VALUE
            beatAtMs = Double.MAX_VALUE
        }
    }

    /** Rings what is due. A cue that is late, or past the end, is consumed silently. */
    private fun fireDue(endMs: Double?) {
        val cfg = config ?: return
        if (sessionMs >= intervalAtMs) {
            if (sessionMs - intervalAtMs <= CueMath.INTERVAL_LATE_TOLERANCE_MS && CueMath.insideSession(intervalAtMs, endMs)) {
                bank?.play(cfg.intervalSound, cfg.bellVolume)
            }
            armInterval(sessionMs)
        }
        if (sessionMs >= beatAtMs) {
            if (sessionMs - beatAtMs <= CueMath.PULSE_LATE_TOLERANCE_MS && CueMath.insideSession(beatAtMs, endMs)) {
                bank?.play(cfg.pulseSound, cfg.pulseVolume)
            }
            armPulse(sessionMs, fresh = false)
        }
        if (halfway.poll(sessionMs, endMs)) bank?.play(cfg.intervalSound, cfg.bellVolume)
        // Pending with no known end yet (a stream whose length arrives late):
        // look again in a second rather than stop ticking.
        halfwayAtMs = when {
            !halfway.pending -> Double.MAX_VALUE
            else -> halfway.dueAt(endMs) ?: (sessionMs + 1000.0)
        }
    }

    private fun scheduleNext(maxDelayMs: Long = Long.MAX_VALUE) {
        val next = minOf(intervalAtMs, beatAtMs, halfwayAtMs)
        if (next == Double.MAX_VALUE && maxDelayMs == Long.MAX_VALUE) return
        val wait = if (next == Double.MAX_VALUE) Double.MAX_VALUE else (next - sessionMs)
        val delay = minOf(maxOf(wait, 1.0), 1000.0, maxDelayMs.toDouble()).toLong()
        handler.postDelayed(tick, maxOf(delay, 1L))
    }

    // ---- Player events -----------------------------------------------------

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        if (phase != Phase.PLAYING) return
        if (isPlaying) {
            bank?.resumeAll()
            // A resume starts a new stretch of real time from this position.
            if (started) { lastPositionMs = primary.currentPosition; lastRealMs = SystemClock.elapsedRealtime() }
            kick()
        } else {
            handler.removeCallbacks(tick)
            // Take the time played so far before freezing.
            if (started) {
                val position = primary.currentPosition
                sessionMs = CueMath.advance(sessionMs, lastPositionMs, position, primary.playbackParameters.speed.toDouble())
                lastPositionMs = position
            }
            if (primary.playbackState != Player.STATE_BUFFERING) bank?.pauseAll()
        }
    }

    override fun onPlaybackParametersChanged(playbackParameters: androidx.media3.common.PlaybackParameters) {
        // Bring the session up to date at the speed it had, then carry on at the new one.
        if (phase != Phase.PLAYING || !started) return
        val position = primary.currentPosition
        // The listener runs after the change, so approximate with the new speed over the tiny gap.
        sessionMs = CueMath.advance(sessionMs, lastPositionMs, position, playbackParameters.speed.toDouble())
        lastPositionMs = position
        kick()
    }

    override fun onPositionDiscontinuity(
        oldPosition: Player.PositionInfo,
        newPosition: Player.PositionInfo,
        reason: Int,
    ) {
        val speed = primary.playbackParameters.speed.toDouble()
        when (phase) {
            Phase.PLAYING -> {
                if (!started) return
                when (reason) {
                    Player.DISCONTINUITY_REASON_SEEK, Player.DISCONTINUITY_REASON_SEEK_ADJUSTMENT -> {
                        // Catch up to where the seek began, then jump by the distance.
                        sessionMs = CueMath.advance(sessionMs, lastPositionMs, oldPosition.positionMs, speed)
                        sessionMs = CueMath.advance(sessionMs, oldPosition.positionMs, newPosition.positionMs, speed)
                        lastPositionMs = newPosition.positionMs
                        lastRealMs = SystemClock.elapsedRealtime()
                        armAll(sessionMs, fresh = false)
                    }
                    Player.DISCONTINUITY_REASON_AUTO_TRANSITION -> {
                        // A repeat: the session carries on from the end of the last pass.
                        sessionMs = CueMath.advance(sessionMs, lastPositionMs, oldPosition.positionMs, speed)
                        sessionMs = CueMath.advance(sessionMs, 0, newPosition.positionMs, speed)
                        lastPositionMs = newPosition.positionMs
                        lastRealMs = SystemClock.elapsedRealtime()
                    }
                }
                kick()
            }
            Phase.EXTENSION -> {
                // The listener moved the voice back during the extension: it is playing again.
                if (reason == Player.DISCONTINUITY_REASON_SEEK) {
                    // The voice follows the extension: paused stays paused, running plays
                    // (an unplug during the extension cleared playWhenReady).
                    if (holdAnchor == 0L) primary.pause() else primary.play()
                    stopTimers()
                    phase = Phase.PLAYING
                    lastPositionMs = newPosition.positionMs
                    lastRealMs = SystemClock.elapsedRealtime()
                    started = true
                    armAll(sessionMs, fresh = false)
                    kick()
                }
            }
            else -> Unit
        }
    }

    // ---- The end -------------------------------------------------------------

    /** The voice reached its true end (never called for an endless repeat). */
    fun onPrimaryEnded() {
        val cfg = config
        if (cfg == null || phase != Phase.PLAYING) {
            host.onSessionEnded(extensionFinished = false, tailMs = 0)
            return
        }
        handler.removeCallbacks(tick)
        if (started) {
            sessionMs = CueMath.advance(
                sessionMs, lastPositionMs,
                primary.duration.takeIf { it > 0 } ?: primary.currentPosition,
                primary.playbackParameters.speed.toDouble(),
            )
        }
        if (cfg.extensionMs > 0) {
            phase = Phase.EXTENSION
            extensionStartSessionMs = sessionMs
            holdRemainingMs = cfg.extensionMs
            holdAnchor = SystemClock.elapsedRealtime()
            acquireWake(cfg.extensionMs + WAKE_SLACK_MS)
            kick()
        } else {
            finishSession(extensionFinished = false)
        }
    }

    private fun finishSession(extensionFinished: Boolean) {
        val cfg = config
        handler.removeCallbacks(tick)
        holdAnchor = 0L
        holdRemainingMs = 0L
        phase = Phase.ENDED
        val tail = bank?.tailMs(cfg?.endSound) ?: 0L
        if (cfg?.endSound != null) bank?.play(cfg.endSound, cfg.bellVolume)
        val now = SystemClock.elapsedRealtime()
        tailEndsAt = now + tail
        // With autoplay the interlude starts now, so a locked phone keeps the
        // service and the CPU while Dart resolves the next session.
        val interlude = if (cfg != null && cfg.autoplay && !cfg.isTimer) cfg.interludeMs else -1L
        interludeEndsAt = if (interlude >= 0) now + interlude else 0L
        val holdMs = if (interlude >= 0) interlude + WAKE_SLACK_MS else 0L
        // Keep the CPU up until the end bell has rung out (and the interlude).
        acquireWake(maxOf(tail, holdMs) + WAKE_SLACK_MS)
        host.onSessionEnded(extensionFinished, tail)
        handler.postDelayed(cleanup, maxOf(tail + 500, holdMs))
    }

    // ---- Wake lock -----------------------------------------------------------

    private fun acquireWake(timeoutMs: Long) {
        try { wakeLock.acquire(timeoutMs) } catch (e: Exception) { Log.w(TAG, "No wake lock: ${e.message}") }
    }

    private fun releaseWake() {
        try { if (wakeLock.isHeld) wakeLock.release() } catch (_: Exception) {}
    }

    private companion object {
        const val TAG = "CueEngine"
        const val WAKE_SLACK_MS = 30_000L
    }
}
