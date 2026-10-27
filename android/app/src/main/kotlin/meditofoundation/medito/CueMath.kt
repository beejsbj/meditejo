package meditofoundation.medito

import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * What the Customize sheet asked for. Plain values only, so the same map
 * crosses the `meditejo/cues` channel on both platforms.
 */
internal data class CueConfig(
    val countdownSeconds: Int = 0,
    val startSound: String? = null,
    val endSound: String? = null,
    val intervalSound: String? = null,
    val intervalMinutes: Int = 0,
    val randomWindowMinutes: Int = 0,
    val pulseSound: String? = null,
    val pulseBpm: Double = 60.0,
    val pulseEndBpm: Double = 60.0,
    val pulseRampMinutes: Int = 0,
    val pulseVolume: Double = 1.0,
    val bellVolume: Double = 1.0,
    val extendMinutes: Int = 0,
    val isTimer: Boolean = false,
    val durationMs: Long = 0,
    val randomSeed: Long = 0,
    /** Autoplay is on: the session end holds the service for the interlude. */
    val autoplay: Boolean = false,
    val interludeSeconds: Int = 0,
    /** The interval bell is "Halfway": one bell at the midpoint, not every N minutes. */
    val intervalHalfway: Boolean = false,
) {
    val countdownMs: Long get() = countdownSeconds.coerceIn(0, 10) * 1000L
    val interludeMs: Long get() = interludeSeconds.coerceIn(0, 30) * 1000L
    val extensionMs: Long get() = extendMinutes.coerceIn(0, 60) * 60_000L
    /** Every-N-minutes bells; never alongside the halfway bell. */
    val hasInterval: Boolean get() = !intervalHalfway && intervalMinutes > 0 && intervalSound != null
    val hasHalfway: Boolean get() = intervalHalfway && intervalSound != null
    val hasPulse: Boolean get() = pulseSound != null

    companion object {
        private fun str(v: Any?): String? = (v as? String)?.takeIf { it.isNotBlank() }
        private fun int(v: Any?): Int = (v as? Number)?.toInt() ?: 0
        private fun long(v: Any?): Long = (v as? Number)?.toLong() ?: 0L
        private fun dbl(v: Any?, d: Double): Double = (v as? Number)?.toDouble() ?: d

        fun fromMap(m: Map<*, *>): CueConfig = CueConfig(
            countdownSeconds = int(m["countdownSeconds"]),
            startSound = str(m["startSound"]),
            endSound = str(m["endSound"]),
            intervalSound = str(m["intervalSound"]),
            intervalMinutes = int(m["intervalMinutes"]).coerceIn(0, 60),
            randomWindowMinutes = int(m["randomWindowMinutes"]).coerceIn(0, 60),
            pulseSound = str(m["pulseSound"]),
            pulseBpm = dbl(m["pulseBpm"], 60.0),
            pulseEndBpm = dbl(m["pulseEndBpm"], dbl(m["pulseBpm"], 60.0)),
            pulseRampMinutes = int(m["pulseRampMinutes"]).coerceIn(0, 60),
            pulseVolume = dbl(m["pulseVolume"], 1.0).coerceIn(0.0, 1.0),
            bellVolume = dbl(m["bellVolume"], 1.0).coerceIn(0.0, 1.0),
            extendMinutes = int(m["extendMinutes"]).coerceIn(0, 60),
            isTimer = m["isTimer"] as? Boolean ?: false,
            durationMs = long(m["durationMs"]),
            randomSeed = long(m["randomSeed"]),
            autoplay = m["autoplay"] as? Boolean ?: false,
            interludeSeconds = int(m["interludeSeconds"]).coerceIn(0, 30),
            intervalHalfway = m["intervalHalfway"] as? Boolean ?: false,
        )
    }
}

/**
 * Pure cue maths. Every time is milliseconds of session time: it starts at
 * zero when the meditation starts (after the countdown), advances with
 * playback in real time (so it is frozen by pause and buffering) and follows
 * a seek by the media distance divided by speed.
 */
internal object CueMath {
    const val MIN_BPM = 20.0
    const val MAX_BPM = 120.0

    /** A beat or bell this late is dropped, never played in a burst. */
    const val PULSE_LATE_TOLERANCE_MS = 400.0
    const val INTERVAL_LATE_TOLERANCE_MS = 1500.0

    /** Heard media this size or smaller between samples counts as listening. */
    const val LISTENING_MAX_STEP_MS = 5000L
    const val LISTENING_THRESHOLD = 0.9

    // ---- Pulse -------------------------------------------------------

    private fun clampBpm(v: Double) = v.coerceIn(MIN_BPM, MAX_BPM)

    /** BPM at session time [tMs]: linear start to end over the ramp, then constant. */
    fun bpmAt(tMs: Double, startBpm: Double, endBpm: Double, rampMinutes: Int): Double {
        val b0 = clampBpm(startBpm)
        val b1 = clampBpm(endBpm)
        val ramp = rampMinutes * 60_000.0
        if (ramp <= 0 || tMs >= ramp) return if (ramp <= 0) b0 else b1
        if (tMs <= 0) return b0
        return b0 + (b1 - b0) * (tMs / ramp)
    }

    /** Beats elapsed at session time [tMs], the integral of BPM / 60 over time. */
    fun pulsePhase(tMs: Double, startBpm: Double, endBpm: Double, rampMinutes: Int): Double {
        if (tMs <= 0) return 0.0
        val b0 = clampBpm(startBpm)
        val b1 = clampBpm(endBpm)
        val ramp = rampMinutes * 60_000.0
        if (ramp <= 0) return b0 * tMs / 60_000.0
        val tr = min(tMs, ramp)
        // beats = (b0*t + (b1-b0)*t^2/(2*ramp)) / 60000 for t in ms
        var beats = (b0 * tr + (b1 - b0) * tr * tr / (2 * ramp)) / 60_000.0
        if (tMs > ramp) beats += b1 * (tMs - ramp) / 60_000.0
        return beats
    }

    /** Session time of beat number [n] (beat 0 is at 0), the analytical inverse of [pulsePhase]. */
    fun beatTime(n: Long, startBpm: Double, endBpm: Double, rampMinutes: Int): Double {
        if (n <= 0) return 0.0
        val b0 = clampBpm(startBpm)
        val b1 = clampBpm(endBpm)
        val ramp = rampMinutes * 60_000.0
        if (ramp <= 0) return n * 60_000.0 / b0
        val rampBeats = pulsePhase(ramp, b0, b1, rampMinutes)
        if (n >= rampBeats) return ramp + (n - rampBeats) * 60_000.0 / b1
        // (b1-b0)/(2*ramp) * t^2 + b0 * t = n * 60000; stable root of the quadratic.
        val a = (b1 - b0) / (2 * ramp)
        val c = n * 60_000.0
        if (kotlin.math.abs(a) < 1e-15) return c / b0
        return 2 * c / (b0 + sqrt(b0 * b0 + 4 * a * c))
    }

    /** Number of the first beat strictly after [tMs]. */
    fun firstBeatAfter(tMs: Double, startBpm: Double, endBpm: Double, rampMinutes: Int): Long {
        if (tMs < 0) return 0
        var n = floor(pulsePhase(tMs, startBpm, endBpm, rampMinutes) + 1e-9).toLong() + 1
        // Guard the rounding either side of the analytical inverse.
        while (n > 0 && beatTime(n - 1, startBpm, endBpm, rampMinutes) > tMs) n--
        while (beatTime(n, startBpm, endBpm, rampMinutes) <= tMs) n++
        return n
    }

    // ---- Interval gaps -------------------------------------------------

    private fun mix64(x: Long): Long {
        var z = x + -0x61c8864680b583ebL
        z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
        z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
        return z xor (z ushr 31)
    }

    /** Uniform in [0, 1), the same for the same seed and index on every call. */
    fun unit(seed: Long, index: Long): Double =
        (mix64(seed * 31 + index * -0x61c8864680b583ebL) ushr 11) / 9007199254740992.0

    /** Gap before cue number [index] (1-based): uniform [max(1, I - W), I + W] minutes. */
    fun gapMs(intervalMinutes: Int, windowMinutes: Int, seed: Long, index: Long): Long {
        val lo = max(1, intervalMinutes - windowMinutes) * 60_000.0
        val hi = (intervalMinutes + windowMinutes) * 60_000.0
        if (windowMinutes <= 0 || hi <= lo) return (intervalMinutes * 60_000.0).toLong()
        return (lo + unit(seed, index) * (hi - lo)).toLong()
    }

    /** Session time of interval cue [index] (1-based); the running sum of the gaps. */
    fun intervalTime(intervalMinutes: Int, windowMinutes: Int, seed: Long, index: Long): Long {
        if (windowMinutes <= 0) return intervalMinutes * 60_000L * index
        var t = 0L
        for (i in 1..index) t += gapMs(intervalMinutes, windowMinutes, seed, i)
        return t
    }

    /** Index of the first interval cue strictly after [tMs]. */
    fun firstIntervalAfter(tMs: Double, intervalMinutes: Int, windowMinutes: Int, seed: Long): Long {
        if (intervalMinutes <= 0) return Long.MAX_VALUE
        if (windowMinutes <= 0) return floor(max(tMs, 0.0) / (intervalMinutes * 60_000.0)).toLong() + 1
        var t = 0L
        var i = 0L
        while (t <= tMs) { i++; t += gapMs(intervalMinutes, windowMinutes, seed, i) }
        return i
    }

    // ---- End rules -----------------------------------------------------

    /**
     * A cue at [deadlineMs] rings only when it falls inside the session. The
     * end boundary itself is excluded, and an unknown end ([endMs] null) never
     * excludes anything.
     */
    fun insideSession(deadlineMs: Double, endMs: Double?): Boolean = endMs == null || deadlineMs < endMs

    /**
     * Session time of the halfway bell: half of the session end, which already
     * includes the extension and follows speed. Null when the end is unknown.
     */
    fun halfwayMs(endMs: Double?): Double? = endMs?.takeIf { it > 0 }?.let { it / 2 }

    /** Session time at which a session ends once its extension is under way. */
    fun extensionEndMs(extensionStartSessionMs: Double, extensionMs: Long): Double =
        extensionStartSessionMs + extensionMs

    /**
     * Session time left in the voice, from media position and speed. Null for
     * an endless or unknown-length track. Later items in a repeat playlist add
     * their full length.
     */
    fun remainingSessionMs(
        positionMs: Long,
        durationMs: Long,
        speed: Double,
        itemsAfterCurrent: Int,
        endless: Boolean,
        extensionMs: Long,
    ): Double? {
        if (endless || durationMs <= 0) return null
        val media = max(0L, durationMs - positionMs) + durationMs * itemsAfterCurrent
        return media / max(speed, 0.05) + extensionMs
    }

    /** Session time after a media-position change, at the speed in force. */
    fun advance(sessionMs: Double, fromPositionMs: Long, toPositionMs: Long, speed: Double): Double =
        sessionMs + (toPositionMs - fromPositionMs) / max(speed, 0.05)

    /** Whether a position jump is a seek rather than playback, given real time passed. */
    fun isSeek(deltaPositionMs: Long, realElapsedMs: Long, speed: Double): Boolean =
        deltaPositionMs < -50 || deltaPositionMs > realElapsedMs * max(speed, 0.05) + 1500

    fun shouldRingStart(positionMs: Long): Boolean = positionMs < 2000

    /**
     * Whether a session that reached its end counts in the stats. A timer
     * counts at its natural end. A recording counts only when 90% of it was
     * really heard: opening or seeking never completes a session, so a
     * finished extension does not either: [extensionFinished] is taken so the
     * rule visibly ignores it.
     */
    @Suppress("UNUSED_PARAMETER")
    fun earnsCompletion(isTimer: Boolean, heardEnough: Boolean, extensionFinished: Boolean): Boolean =
        isTimer || heardEnough
}

/**
 * The one halfway bell: pending until crossed, re-armed by a seek. The
 * midpoint is read from the session end on every poll, so a speed change moves it.
 */
internal class HalfwayCue {
    var pending = false
        private set

    fun arm() { pending = true }
    fun disarm() { pending = false }

    /** Session time it is due at, or null (not pending, or end unknown). For scheduling the next tick. */
    fun dueAt(endMs: Double?): Double? = if (pending) CueMath.halfwayMs(endMs) else null

    /**
     * True when it should ring now. Once the midpoint is crossed it is consumed,
     * and rings only if it is on time and inside the session. An unknown end
     * leaves it pending.
     */
    fun poll(sessionMs: Double, endMs: Double?): Boolean {
        val due = dueAt(endMs) ?: return false
        if (sessionMs < due) return false
        pending = false
        return sessionMs - due <= CueMath.INTERVAL_LATE_TOLERANCE_MS && CueMath.insideSession(due, endMs)
    }
}

/**
 * What the engine does around [HalfwayCue]: re-arm when the cues are re-armed
 * (a seek, a settings change, the extension starting), and say when to look
 * again. Kept out of the engine so it can be tested without a player.
 */
internal class HalfwayBell {
    private val cue = HalfwayCue()
    val pending: Boolean get() = cue.pending

    fun disarm() = cue.disarm()

    /**
     * Arms the bell for a session now at [sessionMs] with [endMs] to go. A seek
     * back before the midpoint, or a longer extension that moves it ahead,
     * rings it again. A session already at or past the midpoint leaves it used
     * up: re-arming within the late tolerance after it rang must not ring it
     * twice. An unknown end arms it, to be judged once the end is known.
     */
    fun rearm(enabled: Boolean, sessionMs: Double, endMs: Double?) {
        val due = CueMath.halfwayMs(endMs)
        if (enabled && (due == null || sessionMs < due)) cue.arm() else cue.disarm()
    }

    /** True when the bell should ring now. */
    fun fire(sessionMs: Double, endMs: Double?): Boolean = cue.poll(sessionMs, endMs)

    /**
     * Session time to look again at: the midpoint while pending, a second on
     * while pending with no known end yet (a stream whose length arrives late),
     * and never ([Double.MAX_VALUE]) when nothing is pending.
     */
    fun nextCheckMs(sessionMs: Double, endMs: Double?): Double =
        if (!cue.pending) Double.MAX_VALUE else cue.dueAt(endMs) ?: (sessionMs + 1000.0)
}

/**
 * Real listening. Counts each stretch of the media once, only when playback
 * walked through it in small steps: a seek (forward or back) is never listening,
 * and hearing a stretch again adds nothing.
 */
internal class ListeningTracker(private val maxStepMs: Long = CueMath.LISTENING_MAX_STEP_MS) {
    private val ranges = ArrayList<LongArray>() // merged, sorted [start, end)
    private var last = -1L

    fun reset() { ranges.clear(); last = -1L }

    fun snapshot(): List<List<Long>> = ranges.map { listOf(it[0], it[1]) }

    fun restore(saved: List<List<Long>>) {
        reset()
        saved.forEach { if (it.size == 2 && it[0] >= 0 && it[1] > it[0]) add(it[0], it[1]) }
    }

    /** Rebase after a seek or a pause: the next step starts here. */
    fun rebase(positionMs: Long) { last = positionMs }

    fun markNotPlaying() { last = -1L }

    fun sample(positionMs: Long, playing: Boolean) {
        if (!playing || positionMs < 0) { last = -1L; return }
        val from = last
        last = positionMs
        if (from < 0) return
        val step = positionMs - from
        if (step <= 0 || step > maxStepMs) return
        add(from, positionMs)
    }

    private fun add(start: Long, end: Long) {
        var s = start
        var e = end
        val it = ranges.iterator()
        val merged = ArrayList<LongArray>()
        var placed = false
        while (it.hasNext()) {
            val r = it.next()
            if (r[1] < s) merged.add(r)
            else if (r[0] > e) {
                if (!placed) { merged.add(longArrayOf(s, e)); placed = true }
                merged.add(r)
            } else { s = min(s, r[0]); e = max(e, r[1]) }
        }
        if (!placed) merged.add(longArrayOf(s, e))
        ranges.clear()
        ranges.addAll(merged)
    }

    fun heardMs(): Long = ranges.sumOf { it[1] - it[0] }

    fun completed(durationMs: Long): Boolean =
        durationMs > 0 && heardMs() >= ceil(durationMs * CueMath.LISTENING_THRESHOLD).toLong()
}

/**
 * Unfinished tracks leave a listening receipt (a finished one is removed).
 * Only recent receipts are kept, so they cannot pile up for ever.
 */
internal object ListeningReceipts {
    const val MAX_AGE_MS = 180L * 24 * 60 * 60 * 1000
    const val MAX_COUNT = 200

    /** Receipts to drop, from each one's last save time; an unknown time (0) counts as now. */
    fun stale(savedAt: Map<String, Long>, nowMs: Long, maxAgeMs: Long = MAX_AGE_MS, maxCount: Int = MAX_COUNT): Set<String> {
        val known = savedAt.mapValues { if (it.value > 0L) it.value else nowMs }
        val old = known.filterValues { nowMs - it > maxAgeMs }.keys
        val excess = known.entries.sortedByDescending { it.value }.drop(maxCount).map { it.key }
        return old + excess
    }
}
