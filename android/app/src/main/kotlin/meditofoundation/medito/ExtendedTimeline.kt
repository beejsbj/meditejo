package meditofoundation.medito

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * A guided session as the listener sees it: the recording with Extend's
 * silence laid into it, as if the file itself were longer. Silence sits in
 * the guide's own pauses ([holds], at media positions) and, for whatever the
 * pauses do not take, after the recording (the tail). The player, the seek
 * bar, the lock screen and completion all read this timeline; only the voice
 * underneath runs on media time.
 *
 * Timeline positions are media milliseconds for the voice and real
 * milliseconds for silence, so at 1x a position is simply time into the
 * session. Holds sit at fixed places: seeking forward over one skips it, as
 * it would skip a stretch of a longer file, and seeking back plays it again.
 *
 * The clock is injected so the silence (a hold or the tail, paused and
 * resumed by the listener) can be tested without a device.
 */
internal class ExtendedTimeline(private val clock: () -> Long) {

    enum class Part { VOICE, HOLD, TAIL }

    /** A place on the timeline, in terms the player can act on. */
    sealed class Spot {
        /** In the voice at [mediaMs], with the first [holdsBehind] holds already behind it. */
        data class Voice(val mediaMs: Long, val holdsBehind: Int) : Spot()

        /** [offsetMs] into hold number [index]; the voice waits at that hold's position. */
        data class Hold(val index: Int, val offsetMs: Long) : Spot()

        /** [offsetMs] into the silence after the recording. */
        data class Tail(val offsetMs: Long) : Spot()
    }

    var holds: List<PauseHold> = emptyList()
        private set

    /** All the silence the session adds: the holds and the tail. */
    var extensionMs = 0L
        private set

    var part = Part.VOICE
        private set

    /** How many holds are wholly behind the playhead; in a hold, the index of the one under way. */
    var cursor = 0
        private set

    // The silence under way (a hold or the tail): time done before the anchor,
    // and the clock when it last started running (0: paused).
    private var silenceDoneMs = 0L
    private var silenceAnchor = 0L

    val heldMs: Long get() = holds.sumOf { it.holdMs }

    /** The silence after the recording: what the holds do not take. */
    val tailMs: Long get() = (extensionMs - heldMs).coerceAtLeast(0L)

    fun durationMs(mediaDurationMs: Long): Long = mediaDurationMs.coerceAtLeast(0L) + heldMs + tailMs

    /** The holds before hold number [count], added up. */
    fun heldBeforeMs(count: Int): Long = holds.take(count.coerceIn(0, holds.size)).sumOf { it.holdMs }

    // ---- The silence under way ------------------------------------------------

    val silenceRunning: Boolean get() = part != Part.VOICE && silenceAnchor != 0L

    fun silenceLengthMs(): Long = when (part) {
        Part.VOICE -> 0L
        Part.HOLD -> holds[cursor].holdMs
        Part.TAIL -> tailMs
    }

    fun silenceElapsedMs(): Long {
        if (part == Part.VOICE) return 0L
        val running = if (silenceAnchor != 0L) clock() - silenceAnchor else 0L
        return (silenceDoneMs + running).coerceIn(0L, silenceLengthMs())
    }

    fun silenceRemainingMs(): Long = silenceLengthMs() - silenceElapsedMs()

    fun pauseSilence() {
        if (silenceAnchor == 0L) return
        silenceDoneMs = silenceElapsedMs()
        silenceAnchor = 0L
    }

    fun resumeSilence() {
        if (part == Part.VOICE || silenceAnchor != 0L) return
        silenceAnchor = nonZeroNow()
    }

    // ---- Where the playhead is --------------------------------------------------

    /** The timeline position, given where the voice is. */
    fun positionMs(mediaMs: Long, mediaDurationMs: Long): Long = when (part) {
        Part.VOICE -> mediaMs.coerceAtLeast(0L) + heldBeforeMs(cursor)
        Part.HOLD -> holds[cursor].atMs + heldBeforeMs(cursor) + silenceElapsedMs()
        Part.TAIL -> mediaDurationMs.coerceAtLeast(0L) + heldMs + silenceElapsedMs()
    }

    /** Silence still to come: the rest of the one under way, the holds ahead, and the tail. */
    fun silenceLeftMs(): Long = when (part) {
        Part.VOICE -> holds.drop(cursor).sumOf { it.holdMs } + tailMs
        Part.HOLD -> silenceRemainingMs() + holds.drop(cursor + 1).sumOf { it.holdMs } + tailMs
        Part.TAIL -> silenceRemainingMs()
    }

    /** Playback has just reached the next hold: it begins now. */
    fun holdDue(mediaMs: Long): Boolean =
        part == Part.VOICE && cursor < holds.size && mediaMs >= holds[cursor].atMs

    /** The media position of hold number [index]. */
    fun holdAtMs(index: Int): Long = holds[index].atMs

    /** The timeline position of [spot]: the inverse of [locate]. */
    fun positionOf(spot: Spot, mediaDurationMs: Long): Long = when (spot) {
        is Spot.Voice -> spot.mediaMs + heldBeforeMs(spot.holdsBehind)
        is Spot.Hold -> holds[spot.index].atMs + heldBeforeMs(spot.index) + spot.offsetMs
        is Spot.Tail -> mediaDurationMs.coerceAtLeast(0L) + heldMs + spot.offsetMs
    }

    /** Where [positionMs] falls: in the voice, inside a hold, or in the tail. */
    fun locate(positionMs: Long, mediaDurationMs: Long): Spot {
        val media = mediaDurationMs.coerceAtLeast(0L)
        val v = positionMs.coerceIn(0L, durationMs(media))
        var before = 0L
        holds.forEachIndexed { i, h ->
            val start = h.atMs + before
            if (v < start) return Spot.Voice(v - before, i)
            if (v < start + h.holdMs) return Spot.Hold(i, v - start)
            before += h.holdMs
        }
        val voiceEnd = media + before
        if (v < voiceEnd || tailMs == 0L) return Spot.Voice(min(v - before, media), holds.size)
        return Spot.Tail(min(v - voiceEnd, tailMs))
    }

    /**
     * Of the stretch between two positions, how much is silence. Session time
     * (the bells' clock) moves by the voice part at the player's speed and by
     * the silence as it is.
     */
    fun silenceBetweenMs(fromMs: Long, toMs: Long, mediaDurationMs: Long): Long {
        val lo = min(fromMs, toMs)
        val hi = max(fromMs, toMs)
        var silence = 0L
        var before = 0L
        holds.forEach { h ->
            val start = h.atMs + before
            silence += overlap(lo, hi, start, start + h.holdMs)
            before += h.holdMs
        }
        val tailStart = mediaDurationMs.coerceAtLeast(0L) + before
        silence += overlap(lo, hi, tailStart, tailStart + tailMs)
        return silence
    }

    /** Session time between two positions: the voice part at [speed], the silence as it is. Signed. */
    fun sessionDistanceMs(fromMs: Long, toMs: Long, mediaDurationMs: Long, speed: Double): Double {
        val silence = silenceBetweenMs(fromMs, toMs, mediaDurationMs)
        val voice = abs(toMs - fromMs) - silence
        val distance = voice / max(speed, 0.05) + silence
        return if (toMs >= fromMs) distance else -distance
    }

    // ---- Moving the playhead -------------------------------------------------------

    fun enterVoice(holdsBehind: Int) {
        part = Part.VOICE
        cursor = holdsBehind.coerceIn(0, holds.size)
        clearSilence()
    }

    /** The voice moved by itself (not through [locate]): the holds before it count as behind. */
    fun mediaMoved(mediaMs: Long) = enterVoice(holds.count { it.atMs < mediaMs })

    fun enterHold(index: Int, offsetMs: Long, running: Boolean) {
        part = Part.HOLD
        cursor = index.coerceIn(0, holds.size - 1)
        silenceDoneMs = offsetMs.coerceIn(0L, holds[cursor].holdMs)
        silenceAnchor = if (running) nonZeroNow() else 0L
    }

    /** The hold under way ran out: the voice carries on after it. */
    fun leaveHold() {
        if (part != Part.HOLD) return
        enterVoice(cursor + 1)
    }

    fun enterTail(offsetMs: Long, running: Boolean) {
        part = Part.TAIL
        cursor = holds.size
        silenceDoneMs = offsetMs.coerceIn(0L, tailMs)
        silenceAnchor = if (running) nonZeroNow() else 0L
    }

    // ---- Planning ---------------------------------------------------------------

    /**
     * Lays out [planned] holds and [extensionMs] of silence in all. Mid-session
     * ([live]) the timeline behind the playhead never changes: the holds behind
     * it, and one under way, stay as they were, and new ones are taken only
     * ahead of [mediaMs]. So a pause map that arrives late changes only what
     * is to come, and the length does not jump. Holds never add up to more
     * than [extensionMs]; one past the end of the recording is dropped.
     */
    fun configure(planned: List<PauseHold>, extensionMs: Long, mediaMs: Long, mediaDurationMs: Long, live: Boolean) {
        val keep = if (!live) 0 else when (part) {
            Part.VOICE -> cursor
            Part.HOLD -> cursor + 1
            Part.TAIL -> holds.size
        }
        val kept = holds.take(keep)
        val from = when {
            !live -> -1L
            part == Part.HOLD -> holds[cursor].atMs
            else -> mediaMs
        }
        var budget = (extensionMs - kept.sumOf { it.holdMs }).coerceAtLeast(0L)
        val ahead = if (live && part == Part.TAIL) emptyList() else planned
            .filter { it.holdMs > 0 && it.atMs > from && it.atMs > 0 && (mediaDurationMs <= 0 || it.atMs < mediaDurationMs) }
            .sortedBy { it.atMs }
            .distinctBy { it.atMs }
            .mapNotNull { h ->
                val take = min(h.holdMs, budget)
                budget -= take
                if (take > 0) PauseHold(h.atMs, take) else null
            }
        holds = kept + ahead
        this.extensionMs = extensionMs.coerceAtLeast(0L)
        if (!live) { part = Part.VOICE; cursor = 0; clearSilence() }
        if (part == Part.TAIL) silenceDoneMs = min(silenceDoneMs, tailMs)
    }

    /** A new session over the same plan: back to the start of the voice. */
    fun reset() {
        part = Part.VOICE
        cursor = 0
        clearSilence()
    }

    fun clear() {
        holds = emptyList()
        extensionMs = 0L
        reset()
    }

    private fun clearSilence() {
        silenceDoneMs = 0L
        silenceAnchor = 0L
    }

    // A zero anchor means paused, so a clock that reads 0 still starts one.
    private fun nonZeroNow(): Long = clock().let { if (it == 0L) 1L else it }

    private fun overlap(lo: Long, hi: Long, start: Long, end: Long): Long =
        (min(hi, end) - max(lo, start)).coerceAtLeast(0L)

    companion object {
        /** One hold never exceeds the longest Extend. */
        const val MAX_HOLD_MS = 60L * 60_000L
    }
}
