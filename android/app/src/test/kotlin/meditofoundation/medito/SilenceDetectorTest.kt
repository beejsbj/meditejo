package meditofoundation.medito

import org.junit.Assert.*
import org.junit.Test

class SilenceDetectorTest {
    private val w = SilenceDetector.WINDOW_MS

    /** [seconds] of audio at [db], one window at a time. */
    private fun level(db: Double, seconds: Double) = DoubleArray((seconds * 1000 / w).toInt()) { db }

    private fun track(vararg parts: DoubleArray): DoubleArray = parts.fold(DoubleArray(0)) { a, b -> a + b }

    @Test fun findsTheLongPausesOfAGuidedSit() {
        // 60 s of teaching, a 20 s pause, 30 s of teaching, a 12 s pause, 20 s of teaching.
        val levels = track(
            level(-24.0, 60.0), level(-56.0, 20.0), level(-24.0, 30.0), level(-56.0, 12.0), level(-24.0, 20.0),
        )
        val spans = SilenceDetector.findSpans(levels)
        assertEquals(listOf(SilentSpan(60_000, 80_000), SilentSpan(110_000, 122_000)), spans)
    }

    @Test fun theThresholdFollowsTheFilesOwnNoiseFloor() {
        // A noisy room: pauses sit at -38 dB, speech at -16. A fixed -45 dB would find none.
        val levels = track(level(-16.0, 40.0), level(-38.0, 15.0), level(-16.0, 40.0))
        val spans = SilenceDetector.findSpans(levels)
        assertEquals(1, spans.size)
        assertEquals(40_000, spans[0].startMs)
        assertEquals(55_000, spans[0].endMs)
    }

    @Test fun aFileWithNoDynamicRangeHasNoPauses() {
        // A music bed under the voice: always about the same loudness.
        val levels = DoubleArray(6000) { -30.0 + (it % 4) * 0.5 }
        assertNull(SilenceDetector.threshold(levels))
        assertTrue(SilenceDetector.findSpans(levels).isEmpty())
    }

    @Test fun aShortFileHasNothingToJudgeBy() {
        assertTrue(SilenceDetector.findSpans(level(-30.0, 0.5)).isEmpty())
    }

    @Test fun shortQuietStretchesAreNotPauses() {
        val levels = track(level(-24.0, 15.0), level(-56.0, 4.0), level(-24.0, 15.0))
        assertTrue(SilenceDetector.findSpans(levels).isEmpty())
        // The app's own minimum can be lower than the stored one.
        assertEquals(1, SilenceDetector.findSpans(levels, minMs = 3_000).size)
    }

    @Test fun aBreathInsideAPauseDoesNotSplitIt() {
        // 20 s quiet with a 0.2 s breath in the middle.
        val levels = track(
            level(-24.0, 30.0), level(-56.0, 10.0), level(-30.0, 0.2), level(-56.0, 10.0), level(-24.0, 30.0),
        )
        val spans = SilenceDetector.findSpans(levels)
        assertEquals(1, spans.size)
        assertEquals(30_000, spans[0].startMs)
        assertEquals(50_200, spans[0].endMs)
    }

    @Test fun aLongerSoundDoesSplitIt() {
        val levels = track(
            level(-24.0, 30.0), level(-56.0, 10.0), level(-24.0, 1.0), level(-56.0, 10.0), level(-24.0, 30.0),
        )
        assertEquals(2, SilenceDetector.findSpans(levels).size)
    }

    @Test fun quietAtTheEndOfTheFileIsClosed() {
        val levels = track(level(-24.0, 30.0), level(-56.0, 15.0))
        assertEquals(listOf(SilentSpan(30_000, 45_000)), SilenceDetector.findSpans(levels))
    }

    @Test fun digitalSilenceDoesNotMoveTheFloor() {
        // A leading gap of pure zeros must not make the room tone look like speech.
        val levels = track(level(-120.0, 10.0), level(-24.0, 40.0), level(-56.0, 12.0), level(-24.0, 40.0))
        val spans = SilenceDetector.findSpans(levels)
        assertTrue(spans.any { it.startMs == 50_000L && it.endMs == 62_000L })
    }

    @Test fun levelsAreDecibelsOfRms() {
        assertEquals(0.0, SilenceDetector.db(1.0), 1e-9)
        assertEquals(-20.0, SilenceDetector.db(0.1), 1e-9)
        assertEquals(-120.0, SilenceDetector.db(0.0), 1e-9)
        assertEquals(0.5, SilenceDetector.rms(0.25 * 4, 4), 1e-9)
        assertEquals(0.0, SilenceDetector.rms(5.0, 0), 1e-9)
    }
}
