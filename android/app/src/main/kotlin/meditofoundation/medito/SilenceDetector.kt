package meditofoundation.medito

import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/** A quiet stretch of a recording, in media milliseconds. */
internal data class SilentSpan(val startMs: Long, val endMs: Long) {
    val lengthMs: Long get() = endMs - startMs
}

/**
 * Finds the pauses in a recording from its loudness, with no fixed level:
 * the threshold sits a quarter of the way from the file's own noise floor up
 * to its speaking level, so a quiet studio and a noisy room both work. A file
 * with no real dynamic range (a music bed, a constant hiss) has no pauses.
 *
 * Pure: it takes the level of each window and returns spans, so it is tested
 * without audio. [PauseMapAnalyzer] feeds it from the decoder.
 */
internal object SilenceDetector {
    /** Loudness is measured over windows this long. */
    const val WINDOW_MS = 100

    /** Spans shorter than this are not kept (the app asks for its own, longer minimum). */
    const val MIN_SPAN_MS = 5_000L

    /** Windows at or under this are digital silence, not the room. */
    const val DIGITAL_SILENCE_DB = -90.0

    /** Speech must stand at least this far above the floor, or the file has no pauses. */
    const val MIN_DYNAMIC_RANGE_DB = 12.0

    /** Where the threshold sits between the floor and the speaking level. */
    const val THRESHOLD_FRACTION = 0.25

    /** A burst this short inside a quiet stretch (a breath, a creak) does not end it. */
    const val BRIDGE_MS = 300L

    const val FLOOR_PERCENTILE = 0.10
    const val SPEECH_PERCENTILE = 0.90

    /** RMS of samples in [-1, 1] as dBFS. */
    fun db(rms: Double): Double = if (rms <= 1e-9) -120.0 else 20 * log10(rms)

    fun rms(sumOfSquares: Double, count: Long): Double =
        if (count <= 0) 0.0 else sqrt(sumOfSquares / count)

    /** The level quiet has to fall under, or null when the file has no dynamic range. */
    fun threshold(levelsDb: DoubleArray): Double? {
        if (levelsDb.size < 10) return null
        val sorted = levelsDb.sortedArray()
        val floor = percentile(sorted, FLOOR_PERCENTILE)
        val speech = percentile(sorted, SPEECH_PERCENTILE)
        if (speech - floor < MIN_DYNAMIC_RANGE_DB) return null
        return floor + (speech - floor) * THRESHOLD_FRACTION
    }

    /**
     * The quiet spans of at least [minMs], from the level of each
     * [WINDOW_MS] window, in order.
     */
    fun findSpans(levelsDb: DoubleArray, minMs: Long = MIN_SPAN_MS): List<SilentSpan> {
        val threshold = threshold(levelsDb) ?: return emptyList()
        val bridge = max(1, (BRIDGE_MS / WINDOW_MS).toInt())
        val spans = ArrayList<SilentSpan>()
        var start = -1
        var lastQuiet = -1
        for (i in levelsDb.indices) {
            val quiet = levelsDb[i] <= threshold
            if (quiet) {
                if (start < 0) start = i
                lastQuiet = i
            } else if (start >= 0 && i - lastQuiet > bridge) {
                close(spans, start, lastQuiet, minMs)
                start = -1
            }
        }
        if (start >= 0) close(spans, start, lastQuiet, minMs)
        return spans
    }

    private fun close(spans: MutableList<SilentSpan>, firstWindow: Int, lastWindow: Int, minMs: Long) {
        val span = SilentSpan(firstWindow * WINDOW_MS.toLong(), (lastWindow + 1) * WINDOW_MS.toLong())
        if (span.lengthMs >= minMs) spans.add(span)
    }

    private fun percentile(sorted: DoubleArray, p: Double): Double {
        // Digital silence (a gap with nothing at all) must not drag the floor to -120.
        val real = sorted.filter { it > DIGITAL_SILENCE_DB }
        if (real.isEmpty()) return DIGITAL_SILENCE_DB
        return real[((real.size - 1) * p).toInt()]
    }
}
