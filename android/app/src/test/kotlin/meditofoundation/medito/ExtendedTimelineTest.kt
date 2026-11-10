package meditofoundation.medito

import org.junit.Assert.*
import org.junit.Test

/** Extend as if the recording were longer: the mapping, seeks, the silence clock and late plans. */
class ExtendedTimelineTest {
    private val sec = 1000L
    private val min = 60_000L
    private var now = 10_000L
    private val media = 600 * sec // a 10-minute recording

    /** Two holds (60 s at 100 s, 120 s at 300 s) and 5 minutes of Extend: 2 minutes of tail. */
    private fun timeline(
        holds: List<PauseHold> = listOf(PauseHold(100 * sec, 60 * sec), PauseHold(300 * sec, 120 * sec)),
        extensionMs: Long = 5 * min,
    ) = ExtendedTimeline { now }.apply { configure(holds, extensionMs, 0, media, live = false) }

    // ---- Length -------------------------------------------------------------

    @Test fun theSessionIsTheRecordingPlusExtendWhereverTheSilenceGoes() {
        assertEquals(media + 5 * min, timeline().durationMs(media))
        assertEquals(media + 5 * min, timeline(holds = emptyList()).durationMs(media))
        assertEquals(2 * min, timeline().tailMs)
        assertEquals(5 * min, timeline(holds = emptyList()).tailMs)
        assertEquals(media, timeline(holds = emptyList(), extensionMs = 0).durationMs(media))
    }

    @Test fun holdsNeverTakeMoreThanExtendAndNoneLiesPastTheEnd() {
        val t = timeline(
            holds = listOf(PauseHold(100 * sec, 4 * min), PauseHold(300 * sec, 4 * min), PauseHold(700 * sec, 1 * min)),
            extensionMs = 5 * min,
        )
        assertEquals(listOf(PauseHold(100 * sec, 4 * min), PauseHold(300 * sec, 1 * min)), t.holds)
        assertEquals(0L, t.tailMs)
        assertEquals(media + 5 * min, t.durationMs(media))
    }

    @Test fun duplicateUnorderedAndEmptyHoldsAreTidied() {
        val t = timeline(holds = listOf(PauseHold(300 * sec, 10 * sec), PauseHold(100 * sec, 10 * sec), PauseHold(100 * sec, 99 * sec), PauseHold(200 * sec, 0)))
        assertEquals(listOf(100 * sec, 300 * sec), t.holds.map { it.atMs })
    }

    // ---- Media to timeline ------------------------------------------------------

    @Test fun theVoiceSitsAfterTheHoldsBehindIt() {
        val t = timeline()
        assertEquals(50 * sec, t.positionMs(50 * sec, media))
        t.enterVoice(1)
        assertEquals(200 * sec + 60 * sec, t.positionMs(200 * sec, media))
        t.enterVoice(2)
        assertEquals(500 * sec + 180 * sec, t.positionMs(500 * sec, media))
    }

    @Test fun aHoldAdvancesThePositionWhileTheVoiceWaits() {
        val t = timeline()
        t.enterHold(1, 0, running = true)
        assertEquals(300 * sec + 60 * sec, t.positionMs(300 * sec, media))
        now += 45 * sec
        assertEquals(300 * sec + 60 * sec + 45 * sec, t.positionMs(300 * sec, media))
        assertEquals(75 * sec, t.silenceRemainingMs())
    }

    @Test fun theTailComesAfterTheVoiceAndEveryHold() {
        val t = timeline()
        t.enterTail(0, running = true)
        now += 30 * sec
        assertEquals(media + 3 * min + 30 * sec, t.positionMs(media, media))
        assertEquals(90 * sec, t.silenceRemainingMs())
    }

    // ---- Timeline to media ----------------------------------------------------------

    @Test fun eachPlaceOnTheTimelineIsFoundInTheVoiceAHoldOrTheTail() {
        val t = timeline()
        assertEquals(ExtendedTimeline.Spot.Voice(0, 0), t.locate(0, media))
        assertEquals(ExtendedTimeline.Spot.Voice(99 * sec, 0), t.locate(99 * sec, media))
        assertEquals(ExtendedTimeline.Spot.Hold(0, 0), t.locate(100 * sec, media))
        assertEquals(ExtendedTimeline.Spot.Hold(0, 30 * sec), t.locate(130 * sec, media))
        assertEquals(ExtendedTimeline.Spot.Voice(100 * sec, 1), t.locate(160 * sec, media))
        assertEquals(ExtendedTimeline.Spot.Voice(250 * sec, 1), t.locate(310 * sec, media))
        assertEquals(ExtendedTimeline.Spot.Hold(1, 100 * sec), t.locate(460 * sec, media))
        assertEquals(ExtendedTimeline.Spot.Voice(300 * sec, 2), t.locate(480 * sec, media))
        assertEquals(ExtendedTimeline.Spot.Voice(599 * sec, 2), t.locate(779 * sec, media))
        assertEquals(ExtendedTimeline.Spot.Tail(0), t.locate(780 * sec, media))
        assertEquals(ExtendedTimeline.Spot.Tail(60 * sec), t.locate(840 * sec, media))
        // Past the end is the end; before the start is the start.
        assertEquals(ExtendedTimeline.Spot.Tail(2 * min), t.locate(99 * min, media))
        assertEquals(ExtendedTimeline.Spot.Voice(0, 0), t.locate(-5 * sec, media))
    }

    @Test fun withoutATailTheEndIsTheEndOfTheVoice() {
        val t = timeline(holds = listOf(PauseHold(100 * sec, 5 * min)), extensionMs = 5 * min)
        assertEquals(ExtendedTimeline.Spot.Voice(media, 1), t.locate(media + 5 * min, media))
    }

    @Test fun aPositionFoundAndPlayedFromIsThePositionAgain() {
        val t = timeline()
        for (v in 0..(media + 5 * min) step 7_000L) {
            when (val spot = t.locate(v, media)) {
                is ExtendedTimeline.Spot.Voice -> { t.enterVoice(spot.holdsBehind); assertEquals(v, t.positionMs(spot.mediaMs, media)) }
                is ExtendedTimeline.Spot.Hold -> { t.enterHold(spot.index, spot.offsetMs, running = false); assertEquals(v, t.positionMs(t.holdAtMs(spot.index), media)) }
                is ExtendedTimeline.Spot.Tail -> { t.enterTail(spot.offsetMs, running = false); assertEquals(v, t.positionMs(media, media)) }
            }
        }
    }

    // ---- Playing through, and seeking -------------------------------------------------

    @Test fun playingThroughTakesEveryHoldOnceAndEndsAtTheFullLength() {
        val t = timeline()
        var mediaMs = 0L
        val taken = mutableListOf<Long>()
        while (mediaMs < media) {
            if (t.holdDue(mediaMs)) {
                taken += t.holdAtMs(t.cursor)
                t.enterHold(t.cursor, 0, running = true)
                now += t.silenceLengthMs()
                assertEquals(0L, t.silenceRemainingMs())
                t.leaveHold()
                continue
            }
            mediaMs += sec
            now += sec
        }
        assertEquals(listOf(100 * sec, 300 * sec), taken)
        t.enterTail(0, running = true)
        now += t.tailMs
        assertEquals(media + 5 * min, t.positionMs(media, media))
    }

    @Test fun seekingForwardOverAHoldSkipsItAndSeekingBackPlaysItAgain() {
        val t = timeline()
        // From the start to just past the first hold, on the timeline.
        val past = t.locate(170 * sec, media) as ExtendedTimeline.Spot.Voice
        t.enterVoice(past.holdsBehind)
        assertEquals(110 * sec, past.mediaMs)
        assertFalse(t.holdDue(past.mediaMs))
        // The skipped hold is not moved anywhere: the length stays.
        assertEquals(media + 5 * min, t.durationMs(media))
        // Back before it: reached again, it is taken again.
        val before = t.locate(90 * sec, media) as ExtendedTimeline.Spot.Voice
        t.enterVoice(before.holdsBehind)
        assertFalse(t.holdDue(95 * sec))
        assertTrue(t.holdDue(100 * sec))
    }

    @Test fun aSeekIntoAHoldStartsThereAndTheVoiceFollowsWhenItEnds() {
        val t = timeline()
        val spot = t.locate(400 * sec, media) as ExtendedTimeline.Spot.Hold
        assertEquals(1, spot.index)
        assertEquals(40 * sec, spot.offsetMs)
        t.enterHold(spot.index, spot.offsetMs, running = true)
        assertEquals(80 * sec, t.silenceRemainingMs())
        now += 80 * sec
        t.leaveHold()
        assertEquals(ExtendedTimeline.Part.VOICE, t.part)
        assertEquals(2, t.cursor)
        assertEquals(300 * sec + 180 * sec, t.positionMs(300 * sec, media))
    }

    @Test fun aRawSeekOfTheVoiceCountsTheHoldsBeforeItAsBehind() {
        val t = timeline()
        t.mediaMoved(301 * sec)
        assertEquals(2, t.cursor)
        t.mediaMoved(300 * sec)
        assertEquals(1, t.cursor)
        assertTrue(t.holdDue(300 * sec))
    }

    // ---- Pause and resume in silence ---------------------------------------------------

    @Test fun pausingInsideAHoldFreezesItAndResumingCarriesOn() {
        val t = timeline()
        t.enterHold(0, 0, running = true)
        now += 20 * sec
        t.pauseSilence()
        assertFalse(t.silenceRunning)
        now += 5 * min // the listener left it paused
        assertEquals(40 * sec, t.silenceRemainingMs())
        assertEquals(120 * sec, t.positionMs(100 * sec, media))
        t.resumeSilence()
        now += 10 * sec
        assertEquals(30 * sec, t.silenceRemainingMs())
        assertEquals(130 * sec, t.positionMs(100 * sec, media))
    }

    @Test fun aHoldEnteredPausedWaitsForResume() {
        val t = timeline()
        t.enterHold(0, 15 * sec, running = false)
        now += 30 * sec
        assertEquals(45 * sec, t.silenceRemainingMs())
        t.resumeSilence()
        now += 45 * sec
        assertEquals(0L, t.silenceRemainingMs())
    }

    @Test fun theTailPausesLikeAHold() {
        val t = timeline()
        t.enterTail(30 * sec, running = true)
        now += 10 * sec
        t.pauseSilence()
        now += 60 * sec
        assertEquals(80 * sec, t.silenceRemainingMs())
        t.resumeSilence()
        now += 80 * sec
        assertEquals(0L, t.silenceRemainingMs())
        assertEquals(media + 5 * min, t.positionMs(media, media))
    }

    // ---- Silence left, and session time ---------------------------------------------------

    @Test fun silenceLeftCountsTheHoldUnderWayTheOnesAheadAndTheTail() {
        val t = timeline()
        assertEquals(5 * min, t.silenceLeftMs())
        t.enterHold(0, 0, running = true)
        now += 20 * sec
        assertEquals(40 * sec + 120 * sec + 2 * min, t.silenceLeftMs())
        t.enterVoice(2)
        assertEquals(2 * min, t.silenceLeftMs())
        t.enterTail(0, running = true)
        now += 30 * sec
        assertEquals(90 * sec, t.silenceLeftMs())
    }

    @Test fun sessionTimeAcrossAHoldCountsTheVoiceAtSpeedAndTheSilenceAsItIs() {
        val t = timeline()
        // 50 s to 210 s: 50 s of voice, the 60 s hold, 50 s of voice.
        assertEquals(60 * sec, t.silenceBetweenMs(50 * sec, 210 * sec, media))
        assertEquals(160_000.0, t.sessionDistanceMs(50 * sec, 210 * sec, media, 1.0), 0.5)
        assertEquals(50_000.0 + 60_000.0, t.sessionDistanceMs(50 * sec, 210 * sec, media, 2.0), 0.5)
        assertEquals(-160_000.0, t.sessionDistanceMs(210 * sec, 50 * sec, media, 1.0), 0.5)
        // Into the tail.
        assertEquals(30 * sec, t.silenceBetweenMs(770 * sec, 810 * sec, media))
    }

    // ---- A plan that changes mid-session -------------------------------------------------------

    @Test fun aLateMapOnlyChangesWhatIsAheadAndTheLengthDoesNotJump() {
        // First play of a stream: no map yet, all of Extend at the end.
        val t = timeline(holds = emptyList())
        t.enterVoice(0)
        val before = t.positionMs(150 * sec, media)
        assertEquals(media + 5 * min, t.durationMs(media))
        // The map lands at 150 s: the pause at 100 s is behind, so its share joins the tail.
        t.configure(listOf(PauseHold(100 * sec, 60 * sec), PauseHold(300 * sec, 120 * sec)), 5 * min, 150 * sec, media, live = true)
        assertEquals(listOf(PauseHold(300 * sec, 120 * sec)), t.holds)
        assertEquals(3 * min, t.tailMs)
        assertEquals(media + 5 * min, t.durationMs(media))
        assertEquals(before, t.positionMs(150 * sec, media))
        assertFalse(t.holdDue(150 * sec))
        assertTrue(t.holdDue(300 * sec))
    }

    @Test fun replanningKeepsTheHoldsBehindAndTheOneUnderWay() {
        val t = timeline()
        t.enterHold(1, 30 * sec, running = true)
        val at = t.positionMs(300 * sec, media)
        // A settings edit sends a fresh plan with different lengths.
        t.configure(listOf(PauseHold(100 * sec, 10 * sec), PauseHold(300 * sec, 10 * sec), PauseHold(500 * sec, 30 * sec)), 5 * min, 300 * sec, media, live = true)
        assertEquals(listOf(PauseHold(100 * sec, 60 * sec), PauseHold(300 * sec, 120 * sec), PauseHold(500 * sec, 30 * sec)), t.holds)
        assertEquals(ExtendedTimeline.Part.HOLD, t.part)
        assertEquals(at, t.positionMs(300 * sec, media))
        assertEquals(90 * sec, t.tailMs)
    }

    @Test fun aShorterExtendMidSessionShortensWhatIsAhead() {
        val t = timeline()
        t.enterVoice(1)
        t.configure(listOf(PauseHold(300 * sec, 120 * sec)), 2 * min, 200 * sec, media, live = true)
        // 60 s is already behind; 60 s is left for the hold ahead and none for the tail.
        assertEquals(listOf(PauseHold(100 * sec, 60 * sec), PauseHold(300 * sec, 60 * sec)), t.holds)
        assertEquals(0L, t.tailMs)
        assertEquals(media + 2 * min, t.durationMs(media))
    }

    @Test fun aNewSessionStartsAtTheBeginningOfTheSamePlan() {
        val t = timeline()
        t.enterTail(10 * sec, running = true)
        t.reset()
        assertEquals(ExtendedTimeline.Part.VOICE, t.part)
        assertEquals(0, t.cursor)
        assertEquals(2, t.holds.size)
        assertEquals(0L, t.positionMs(0, media))
    }

    // ---- The channel ----------------------------------------------------------------------

    @Test fun holdsCrossTheChannelAsAList() {
        val config = CueConfig.fromMap(
            mapOf(
                "extendMinutes" to 10,
                "holds" to listOf(
                    mapOf("atMs" to 105_000, "holdMs" to 60_000L),
                    mapOf("atMs" to -1, "holdMs" to 5),
                    mapOf("atMs" to 5, "holdMs" to 0),
                    mapOf("atMs" to "x", "holdMs" to 5),
                    "nonsense",
                    mapOf("atMs" to 215_000L, "holdMs" to 120_000),
                ),
            ),
        )
        assertEquals(listOf(PauseHold(105_000, 60_000), PauseHold(215_000, 120_000)), config.holds)
        assertTrue(CueConfig.fromMap(emptyMap<String, Any?>()).holds.isEmpty())
        assertTrue(CueConfig.fromMap(mapOf("holds" to "nope")).holds.isEmpty())
    }
}
