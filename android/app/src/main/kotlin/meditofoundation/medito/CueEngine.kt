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
 * The cues run on session time (see [CueMath]). It is read from the player's
 * media clock while the voice plays, and from the monotonic clock during the
 * countdown and the silence, so pause and buffering freeze it, a seek jumps
 * it without a burst of missed cues, and speed is accounted for.
 *
 * What the listener sees is [ExtendedTimeline]: the recording with Extend's
 * silence laid into it (holds in the guide's pauses, the tail after it), as
 * if the file were longer. [positionMs], [durationMs] and [seekTo] speak it;
 * the service reports them to Dart, the lock screen and completion.
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

        /** A hold in the recording begins: stop the voice where it is (keeping focus and the background sound). */
        fun holdNarration()

        /** The hold is over: the voice carries on from where it stopped. */
        fun resumeNarration()
    }

    /** HOLD is a silent stretch inside the recording, EXTENSION the one after it (the tail). */
    enum class Phase { IDLE, COUNTDOWN, PLAYING, HOLD, EXTENSION, ENDED }

    private val handler = Handler(Looper.getMainLooper())
    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "meditejo:cues")
        .apply { setReferenceCounted(false) }

    private var bank: CueSoundBank? = null
    var config: CueConfig? = null
        private set
    var phase = Phase.IDLE
        private set

    // The countdown runs on the monotonic clock. A zero anchor means held.
    private var holdRemainingMs = 0L
    private var holdAnchor = 0L

    // The session as the listener sees it; its silence (holds and the tail)
    // runs on the monotonic clock too.
    private val timeline = ExtendedTimeline { SystemClock.elapsedRealtime() }
    // Session time at the start of the silence under way.
    private var silenceStartSessionMs = 0.0
    // A seek the engine made itself (where the voice was sent): its
    // discontinuity is already accounted for. Cleared by the next seek.
    private var ownSeekToMs = -1L
    private var lastSeekOwn = false
    // A seek into silence asked for during the countdown, taken when the voice starts.
    private var seekAfterCountdownMs = -1L

    // Session time.
    private var started = false
    private var sessionMs = 0.0
    private var lastPositionMs = 0L
    private var lastRealMs = 0L

    private var intervalIndex = Long.MAX_VALUE
    private var intervalAtMs = Double.MAX_VALUE
    private var beatNumber = Long.MAX_VALUE
    private var beatAtMs = Double.MAX_VALUE
    private val halfway = HalfwayBell()
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
        val live = phase == Phase.PLAYING || phase == Phase.EXTENSION || phase == Phase.COUNTDOWN || phase == Phase.HOLD
        if (!live) stopTimers()
        // A repeating recording has no holds: its silence is all after the last pass.
        val holds = if (cfg.isTimer || repeating()) emptyList() else cfg.holds
        // Before a session the player may still hold the previous recording, so
        // its length says nothing about this one: the holds come from this
        // recording's own pause map and are not checked against it.
        val mediaMs = if (live) mediaDurationMs(cfg) else 0L
        timeline.configure(holds, if (cfg.isTimer) 0L else cfg.extensionMs, primary.currentPosition, mediaMs, live)
        // The lock was sized for the old silence: re-time it to what is left now.
        if ((phase == Phase.HOLD || phase == Phase.EXTENSION) && timeline.silenceRunning) {
            acquireWake(timeline.silenceRemainingMs() + WAKE_SLACK_MS)
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
        seekAfterCountdownMs = -1L
        timeline.reset()
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

    /**
     * The voice was asked to play while the session is in silence, and that
     * silence is paused: the session's own start (a Resume that landed in a
     * hold or the tail before playback began), or a resume from outside the
     * engine. The silence carries on instead, and the voice keeps waiting.
     */
    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
        if (!playWhenReady || timeline.silenceRunning) return
        when (phase) {
            Phase.HOLD -> {
                timeline.resumeSilence()
                thaw(timeline.silenceRemainingMs())
                host.holdNarration()
            }
            Phase.EXTENSION -> {
                timeline.resumeSilence()
                thaw(timeline.silenceRemainingMs())
            }
            else -> Unit
        }
    }

    /** The voice is stopped for a hold or the tail. */
    val isSilent: Boolean get() = phase == Phase.HOLD || phase == Phase.EXTENSION

    /** Cancels every timer and sound. The session is over or abandoned. */
    fun stop() {
        stopTimers()
        halfway.disarm()
        timeline.clear()
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
        timeline.pauseSilence()
    }

    // ---- Queries ---------------------------------------------------------

    private fun heldRemaining(): Long {
        if (holdAnchor == 0L) return holdRemainingMs.coerceAtLeast(0)
        return (holdRemainingMs - (SystemClock.elapsedRealtime() - holdAnchor)).coerceAtLeast(0)
    }

    fun countdownRemainingMs(): Long = if (phase == Phase.COUNTDOWN) heldRemaining() else 0L
    fun extensionRemainingMs(): Long = if (phase == Phase.EXTENSION) timeline.silenceRemainingMs() else 0L
    fun holdRemainingMs(): Long = if (phase == Phase.HOLD) timeline.silenceRemainingMs() else 0L

    /** True during the countdown, a hold or the extension while their clock is actually running. */
    fun isHoldRunning(): Boolean = when (phase) {
        Phase.COUNTDOWN -> holdAnchor != 0L
        Phase.HOLD, Phase.EXTENSION -> timeline.silenceRunning
        else -> false
    }

    /** The session is under way: the voice playing (or about to), or its silence running. */
    fun isSessionRunning(): Boolean = when (phase) {
        Phase.HOLD, Phase.EXTENSION, Phase.COUNTDOWN -> isHoldRunning()
        Phase.PLAYING -> primary.playWhenReady && primary.playbackState != Player.STATE_ENDED
        else -> false
    }

    /**
     * The session has silence still to come or under way: a hold now, or an
     * extension after the recording (what the holds do not take).
     */
    fun hasExtension(): Boolean {
        if (config == null || phase == Phase.ENDED || phase == Phase.IDLE) return false
        if (phase == Phase.HOLD || phase == Phase.EXTENSION) return true
        return timeline.silenceLeftMs() > 0L
    }

    /**
     * Extend time still to come, wherever it will be spent: what a hold under
     * way has left, holds ahead, and the end. Zero without a session.
     */
    fun extensionLeftMs(): Long {
        if (config == null) return 0L
        return when (phase) {
            Phase.PLAYING, Phase.HOLD, Phase.EXTENSION -> timeline.silenceLeftMs()
            else -> 0L
        }
    }

    /**
     * Whether the session reads as [ExtendedTimeline] rather than the bare
     * recording: a guided session that plays once. A timer, or a recording
     * set to repeat, keeps the player's own position and length.
     */
    val extendsTimeline: Boolean
        get() {
            val cfg = config ?: return false
            return !cfg.isTimer && !repeating() && phase != Phase.IDLE
        }

    /** Position on the extended timeline. */
    fun positionMs(): Long =
        if (phase == Phase.ENDED) durationMs()
        else timeline.positionMs(primary.currentPosition.coerceAtLeast(0L), mediaDurationMs())

    /** Length of the extended timeline: the recording plus Extend. */
    fun durationMs(): Long = timeline.durationMs(mediaDurationMs())

    private fun mediaDurationMs(cfg: CueConfig? = config): Long =
        primary.duration.takeIf { it > 0 && it != androidx.media3.common.C.TIME_UNSET } ?: (cfg?.durationMs ?: 0L)

    private fun repeating(): Boolean =
        primary.repeatMode != Player.REPEAT_MODE_OFF || primary.mediaItemCount > 1

    fun endTailMs(): Long = bank?.tailMs(config?.endSound) ?: 0L

    fun state(): Map<String, Any?> = mapOf(
        "phase" to phase.name.lowercase(),
        "countdownRemainingMs" to countdownRemainingMs(),
        "extensionRemainingMs" to extensionRemainingMs(),
        "holdRemainingMs" to holdRemainingMs(),
        "extensionLeftMs" to extensionLeftMs(),
        "sessionMs" to sessionMs.toLong(),
        "paused" to ((phase == Phase.COUNTDOWN || phase == Phase.HOLD || phase == Phase.EXTENSION) && !isHoldRunning()),
    )

    /**
     * Pause or resume the countdown or the silence (a hold or the tail), which
     * the player's own pause button cannot reach. Returns false when none runs.
     */
    fun toggleHold(): Boolean {
        when (phase) {
            Phase.COUNTDOWN -> {
                if (holdAnchor != 0L) {
                    holdRemainingMs = heldRemaining()
                    holdAnchor = 0L
                    freeze()
                } else {
                    holdAnchor = SystemClock.elapsedRealtime()
                    thaw(holdRemainingMs)
                }
            }
            Phase.HOLD, Phase.EXTENSION -> {
                if (timeline.silenceRunning) {
                    timeline.pauseSilence()
                    freeze()
                } else {
                    timeline.resumeSilence()
                    thaw(timeline.silenceRemainingMs())
                }
            }
            else -> return false
        }
        return true
    }

    private fun freeze() {
        handler.removeCallbacks(tick)
        releaseWake()
        bank?.pauseAll()
    }

    private fun thaw(remainingMs: Long) {
        acquireWake(remainingMs + WAKE_SLACK_MS)
        bank?.resumeAll()
        kick()
    }

    /**
     * Moves the session to [positionMs] on the extended timeline: into the
     * voice, into a hold, or into the tail. Running stays running and paused
     * stays paused. False when the session does not read as the extended
     * timeline (the caller seeks the player itself).
     */
    fun seekTo(positionMs: Long): Boolean {
        if (!extendsTimeline) return false
        if (phase != Phase.PLAYING && phase != Phase.HOLD && phase != Phase.EXTENSION && phase != Phase.COUNTDOWN) return false
        val media = mediaDurationMs()
        if (media <= 0) return false
        val running = isSessionRunning()
        val speed = primary.playbackParameters.speed.toDouble()
        val spot = timeline.locate(positionMs, media)
        // The countdown is not session time yet: the voice's place changes now,
        // and a place in silence is taken when the voice starts.
        if (phase == Phase.COUNTDOWN) {
            seekAfterCountdownMs = -1L
            when (spot) {
                is ExtendedTimeline.Spot.Voice -> {
                    timeline.enterVoice(spot.holdsBehind)
                    seekVoice(spot.mediaMs)
                }
                else -> seekAfterCountdownMs = positionMs
            }
            return true
        }
        catchUpSessionTime(speed)
        val from = positionMs()
        handler.removeCallbacks(tick)
        val to = timeline.positionOf(spot, media)
        // Into the voice before the first tick (a Resume seek as playback
        // starts), the first tick still sets session time and the start up.
        if (!started && spot is ExtendedTimeline.Spot.Voice) {
            timeline.enterVoice(spot.holdsBehind)
            seekVoice(spot.mediaMs)
            kick()
            return true
        }
        sessionMs = if (started) {
            (sessionMs + timeline.sessionDistanceMs(from, to, media, speed)).coerceAtLeast(0.0)
        } else timeline.sessionDistanceMs(0L, to, media, speed)
        if (phase == Phase.HOLD || phase == Phase.EXTENSION) releaseWake()
        when (spot) {
            is ExtendedTimeline.Spot.Voice -> {
                val wasSilent = phase != Phase.PLAYING
                timeline.enterVoice(spot.holdsBehind)
                phase = Phase.PLAYING
                seekVoice(spot.mediaMs)
                // From silence the voice takes the session's state: a paused
                // tail may still have the player set to play.
                if (wasSilent) {
                    if (running) { bank?.resumeAll(); host.resumeNarration() } else primary.pause()
                }
            }
            is ExtendedTimeline.Spot.Hold -> {
                timeline.enterHold(spot.index, spot.offsetMs, running)
                silenceStartSessionMs = sessionMs - spot.offsetMs
                phase = Phase.HOLD
                seekVoice(timeline.holdAtMs(spot.index))
                host.holdNarration()
                if (running) acquireWake(timeline.silenceRemainingMs() + WAKE_SLACK_MS)
            }
            is ExtendedTimeline.Spot.Tail -> {
                timeline.enterTail(spot.offsetMs, running)
                silenceStartSessionMs = sessionMs - spot.offsetMs
                phase = Phase.EXTENSION
                // The voice is over: at its end it rests in ENDED, keeping
                // playWhenReady (and so focus and the background sound) as it was.
                seekVoice(media)
                if (running) acquireWake(timeline.silenceRemainingMs() + WAKE_SLACK_MS)
            }
        }
        started = true
        lastPositionMs = primary.currentPosition
        lastRealMs = SystemClock.elapsedRealtime()
        armAll(sessionMs, fresh = false)
        kick()
        return true
    }

    /** Brings session time up to now, so a seek moves it from where the session really is. */
    private fun catchUpSessionTime(speed: Double) {
        if (!started) return
        when (phase) {
            Phase.PLAYING -> if (primary.isPlaying) {
                val position = primary.currentPosition
                sessionMs = CueMath.advance(sessionMs, lastPositionMs, position, speed)
                lastPositionMs = position
            }
            Phase.HOLD, Phase.EXTENSION -> sessionMs = silenceStartSessionMs + timeline.silenceElapsedMs()
            else -> Unit
        }
    }

    private fun seekVoice(mediaMs: Long) {
        ownSeekToMs = mediaMs
        primary.seekTo(mediaMs)
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
                Phase.HOLD -> runHold()
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
        val pending = seekAfterCountdownMs
        seekAfterCountdownMs = -1L
        if (pending < 0 || !seekTo(pending)) kick()
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
        if (extendsTimeline && timeline.holdDue(position)) {
            beginHold()
            return
        }
        scheduleNext()
    }

    /** Playback reached the next hold: the voice stops there and its silence is counted out. */
    private fun beginHold() {
        handler.removeCallbacks(tick)
        timeline.enterHold(timeline.cursor, 0L, running = true)
        silenceStartSessionMs = sessionMs
        phase = Phase.HOLD
        acquireWake(timeline.silenceRemainingMs() + WAKE_SLACK_MS)
        host.holdNarration()
        kick()
    }

    private fun runHold() {
        if (!timeline.silenceRunning) return
        val remaining = timeline.silenceRemainingMs()
        sessionMs = silenceStartSessionMs + timeline.silenceElapsedMs()
        if (remaining <= 0) {
            endHold()
            return
        }
        fireDue(remainingEndMs(primary.playbackParameters.speed.toDouble()))
        scheduleNext(maxDelayMs = remaining)
    }

    /** The hold ran out: the voice carries on from where it stopped. */
    private fun endHold() {
        handler.removeCallbacks(tick)
        releaseWake()
        sessionMs = silenceStartSessionMs + timeline.silenceLengthMs()
        timeline.leaveHold()
        phase = Phase.PLAYING
        lastPositionMs = primary.currentPosition
        lastRealMs = SystemClock.elapsedRealtime()
        bank?.resumeAll()
        host.resumeNarration()
        kick()
    }

    /**
     * The playhead left a hold by itself (a seek the engine did not make, or
     * the voice started by a control outside the app): the hold is over, and
     * the holds before the voice count as behind.
     */
    private fun leaveHoldForVoice(resume: Boolean) {
        handler.removeCallbacks(tick)
        releaseWake()
        sessionMs = silenceStartSessionMs + timeline.silenceElapsedMs()
        timeline.mediaMoved(primary.currentPosition)
        phase = Phase.PLAYING
        lastPositionMs = primary.currentPosition
        lastRealMs = SystemClock.elapsedRealtime()
        if (resume || primary.isPlaying) bank?.resumeAll()
        if (resume) host.resumeNarration()
    }

    private fun runExtension() {
        if (!timeline.silenceRunning) return
        val remaining = timeline.silenceRemainingMs()
        sessionMs = silenceStartSessionMs + timeline.silenceElapsedMs()
        if (remaining <= 0) {
            finishSession(extensionFinished = true)
            return
        }
        fireDue(CueMath.extensionEndMs(silenceStartSessionMs, timeline.silenceLengthMs()))
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
            primary.currentPosition, duration, speed, after.coerceAtLeast(0), endless, extensionLeftMs(),
        ) ?: return null
        return sessionMs + remaining
    }

    private fun armAll(atMs: Double, fresh: Boolean) {
        armInterval(atMs)
        armPulse(atMs, fresh)
        armHalfway(atMs)
    }

    /**
     * Re-armed by every arm (a seek back before the midpoint rings it again when
     * crossed), but left used up when the session is already at or past it.
     */
    private fun armHalfway(atMs: Double) {
        val cfg = config
        halfway.rearm(cfg?.hasHalfway == true, atMs, currentEndMs())
        halfwayAtMs = Double.MAX_VALUE // recomputed by the next fireDue
    }

    /** Session time at which the session ends as it stands now; null when unknown. */
    private fun currentEndMs(): Double? {
        if (config == null) return null
        return if (phase == Phase.EXTENSION) CueMath.extensionEndMs(silenceStartSessionMs, timeline.silenceLengthMs())
        else remainingEndMs(primary.playbackParameters.speed.toDouble())
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
        if (halfway.fire(sessionMs, endMs)) bank?.play(cfg.intervalSound, cfg.bellVolume)
        halfwayAtMs = halfway.nextCheckMs(sessionMs, endMs)
    }

    private fun scheduleNext(maxDelayMs: Long = Long.MAX_VALUE) {
        val next = minOf(intervalAtMs, beatAtMs, halfwayAtMs, nextHoldAtMs())
        if (next == Double.MAX_VALUE && maxDelayMs == Long.MAX_VALUE) return
        val wait = if (next == Double.MAX_VALUE) Double.MAX_VALUE else (next - sessionMs)
        val delay = minOf(maxOf(wait, 1.0), 1000.0, maxDelayMs.toDouble()).toLong()
        handler.postDelayed(tick, maxOf(delay, 1L))
    }

    /** Session time the next hold is reached at (at the current speed), or none. */
    private fun nextHoldAtMs(): Double {
        if (phase != Phase.PLAYING || !extendsTimeline || timeline.cursor >= timeline.holds.size) return Double.MAX_VALUE
        val atMs = timeline.holdAtMs(timeline.cursor)
        return sessionMs + (atMs - lastPositionMs) / maxOf(primary.playbackParameters.speed.toDouble(), 0.05)
    }

    // ---- Player events -----------------------------------------------------

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        // The voice started during a hold, by something other than the engine,
        // and is still meant to play (a paused hold resumed through
        // [onPlayWhenReadyChanged] stops it again): the listener chose to carry on.
        if (phase == Phase.HOLD) {
            if (isPlaying && primary.playWhenReady && timeline.silenceRunning) {
                leaveHoldForVoice(resume = false)
                kick()
            }
            return
        }
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
        // The engine's own seeks ([seekTo]) have already moved the session.
        if (reason == Player.DISCONTINUITY_REASON_SEEK) {
            lastSeekOwn = ownSeekToMs >= 0 && kotlin.math.abs(newPosition.positionMs - ownSeekToMs) < SAME_POSITION_MS
            ownSeekToMs = -1L
            if (lastSeekOwn) return
        } else if (reason == Player.DISCONTINUITY_REASON_SEEK_ADJUSTMENT && lastSeekOwn) {
            lastPositionMs = newPosition.positionMs
            return
        }
        val speed = primary.playbackParameters.speed.toDouble()
        when (phase) {
            Phase.PLAYING -> {
                if (!started) { timeline.mediaMoved(newPosition.positionMs); return }
                when (reason) {
                    Player.DISCONTINUITY_REASON_SEEK, Player.DISCONTINUITY_REASON_SEEK_ADJUSTMENT -> {
                        // Catch up to where the seek began, then jump by the distance.
                        sessionMs = CueMath.advance(sessionMs, lastPositionMs, oldPosition.positionMs, speed)
                        sessionMs = CueMath.advance(sessionMs, oldPosition.positionMs, newPosition.positionMs, speed)
                        // The holds before where the voice landed are behind it.
                        timeline.mediaMoved(newPosition.positionMs)
                        lastPositionMs = newPosition.positionMs
                        lastRealMs = SystemClock.elapsedRealtime()
                        armAll(sessionMs, fresh = false)
                    }
                    Player.DISCONTINUITY_REASON_AUTO_TRANSITION -> {
                        // A repeat: the session carries on from the end of the last pass.
                        sessionMs = CueMath.advance(sessionMs, lastPositionMs, oldPosition.positionMs, speed)
                        sessionMs = CueMath.advance(sessionMs, 0, newPosition.positionMs, speed)
                        timeline.mediaMoved(newPosition.positionMs)
                        lastPositionMs = newPosition.positionMs
                        lastRealMs = SystemClock.elapsedRealtime()
                    }
                }
                kick()
            }
            Phase.HOLD -> {
                // Something moved the voice during a hold: the hold is over, the voice follows.
                if (reason == Player.DISCONTINUITY_REASON_SEEK) {
                    // A seek to where the hold already is (the player re-preparing after
                    // an error) is not the listener moving the playhead.
                    if (kotlin.math.abs(newPosition.positionMs - oldPosition.positionMs) < SAME_POSITION_MS) return
                    val running = timeline.silenceRunning
                    leaveHoldForVoice(resume = running)
                    // As while playing, a seek moves session time by the distance it jumped.
                    sessionMs = CueMath.advance(sessionMs, oldPosition.positionMs, newPosition.positionMs, speed)
                    started = true
                    armAll(sessionMs, fresh = false)
                    kick()
                }
            }
            Phase.EXTENSION -> {
                // Something moved the voice back during the tail: it is playing again.
                if (reason == Player.DISCONTINUITY_REASON_SEEK) {
                    // The voice follows the tail: paused stays paused, running plays
                    // (an unplug during the tail cleared playWhenReady).
                    val running = timeline.silenceRunning
                    if (running) primary.play() else primary.pause()
                    stopTimers()
                    timeline.mediaMoved(newPosition.positionMs)
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
        // A seek into the tail rests the voice at its end: the tail is already under way.
        if (phase == Phase.EXTENSION) return
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
        // Holds still ahead (the voice was moved past them) are skipped, as a
        // stretch of a longer file would be; the tail is what it always was.
        if (timeline.tailMs > 0) {
            phase = Phase.EXTENSION
            silenceStartSessionMs = sessionMs
            timeline.enterTail(0L, running = true)
            acquireWake(timeline.tailMs + WAKE_SLACK_MS)
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
        timeline.pauseSilence()
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
        const val SAME_POSITION_MS = 1000L
    }
}
