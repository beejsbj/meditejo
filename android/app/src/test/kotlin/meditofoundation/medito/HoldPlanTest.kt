package meditofoundation.medito

import org.junit.Assert.*
import org.junit.Test

/** Extend placed in the guide's pauses: where the voice stops, and the budget it spends. */
class HoldPlanTest {
    private val sec = 1000L

    private fun plan(vararg holds: PauseHold) = HoldPlan().apply { configure(holds.toList()) }

    /**
     * Walks a recording of [durationMs] in one-second steps the way the engine
     * does: take the hold the playhead reached, wait it out (adding its length
     * to session time), carry on. Returns session time at the end of the
     * recording and the end extension still to hold.
     */
    private fun play(p: HoldPlan, extensionMs: Long, durationMs: Long, taken: MutableList<Long> = mutableListOf()): Pair<Long, Long> {
        var position = 0L
        var session = 0L
        while (position < durationMs) {
            val due = p.dueAt(position)
            if (due != null) {
                val length = p.lengthOf(due, extensionMs)
                p.begin(due)
                if (length > 0) { taken += due.atMs; session += length; p.spend(length) }
            }
            position += sec
            session += sec
        }
        return session to p.endExtensionMs(extensionMs, Long.MAX_VALUE)
    }

    @Test fun aHoldIsDueWhenThePlayheadReachesItAndOnlyOnce() {
        val p = plan(PauseHold(100 * sec, 30 * sec))
        assertNull(p.dueAt(99_999))
        assertEquals(PauseHold(100 * sec, 30 * sec), p.dueAt(100_000))
        assertNotNull(p.dueAt(101_500))
        p.begin(p.dueAt(100_000)!!)
        assertNull(p.dueAt(100_200))
        assertNull(p.dueAt(101_000))
    }

    @Test fun aSeekLandingLongPastAHoldDoesNotTakeIt() {
        val p = plan(PauseHold(100 * sec, 30 * sec))
        assertNull(p.dueAt(100 * sec + HoldPlan.LATE_TOLERANCE_MS + 1))
        assertNull(p.dueAt(400 * sec))
    }

    @Test fun holdsAreTakenInOrderWhateverOrderTheyArrivedIn() {
        val p = plan(PauseHold(300 * sec, 10 * sec), PauseHold(100 * sec, 20 * sec), PauseHold(200 * sec, 30 * sec))
        assertEquals(100 * sec, p.nextAfter(0)!!.atMs)
        assertEquals(200 * sec, p.nextAfter(100 * sec)!!.atMs)
        assertNull(p.nextAfter(300 * sec))
    }

    @Test fun severalHoldsAddUpToTheExtendMinutesAndTheRestIsHeldAtTheEnd() {
        val extension = 5 * 60 * sec
        val p = plan(PauseHold(100 * sec, 120 * sec), PauseHold(200 * sec, 90 * sec), PauseHold(300 * sec, 45 * sec))
        val taken = mutableListOf<Long>()
        val (session, endExtension) = play(p, extension, 400 * sec, taken)
        assertEquals(listOf(100 * sec, 200 * sec, 300 * sec), taken)
        assertEquals(255 * sec, p.spentMs)
        assertEquals(45 * sec, endExtension)
        // The recording, every hold, and the end extension: recording length plus Extend.
        assertEquals(400 * sec + extension, session + endExtension)
    }

    @Test fun withNoHoldsEverythingIsHeldAtTheEnd() {
        val p = plan()
        val (session, endExtension) = play(p, 10 * 60 * sec, 60 * sec)
        assertEquals(60 * sec, session)
        assertEquals(10 * 60 * sec, endExtension)
    }

    @Test fun aHoldNeverTakesMoreThanTheExtendTimeLeft() {
        val p = plan(PauseHold(100 * sec, 90 * sec), PauseHold(200 * sec, 90 * sec))
        val taken = mutableListOf<Long>()
        val (_, endExtension) = play(p, 120 * sec, 300 * sec, taken)
        assertEquals(2, taken.size)
        assertEquals(120 * sec, p.spentMs) // 90 + the 30 that was left
        assertEquals(0L, endExtension)
    }

    @Test fun noExtendMeansNoHolds() {
        val p = plan(PauseHold(100 * sec, 30 * sec))
        val taken = mutableListOf<Long>()
        play(p, 0, 300 * sec, taken)
        assertTrue(taken.isEmpty())
        assertEquals(0L, p.spentMs)
    }

    @Test fun aHoldAlreadyTakenIsNotTakenAgainAfterSeekingBack() {
        val p = plan(PauseHold(100 * sec, 30 * sec))
        p.begin(p.dueAt(100 * sec)!!)
        p.spend(30 * sec)
        assertNull(p.dueAt(100 * sec)) // played back over
        assertNull(p.nextAfter(50 * sec))
        assertEquals(0L, p.endExtensionMs(30 * sec, 50 * sec)) // its time is spent, not owed again
    }

    @Test fun seekingPastAHoldLeavesItsTimeForTheEnd() {
        val p = plan(PauseHold(100 * sec, 30 * sec), PauseHold(300 * sec, 30 * sec))
        // The listener jumps from 10 s to 250 s: the first hold is behind the playhead.
        assertEquals(30 * sec, p.plannedAheadMs(250 * sec))
        assertEquals(60 * sec - 30 * sec, p.endExtensionMs(60 * sec, 250 * sec))
        val taken = mutableListOf<Long>()
        // Played on from 250 s: only the second hold is taken; the end holds the first one's time.
        var position = 250 * sec
        while (position < 400 * sec) {
            val due = p.dueAt(position)
            if (due != null) { p.begin(due); p.spend(p.lengthOf(due, 60 * sec)); taken += due.atMs }
            position += sec
        }
        assertEquals(listOf(300 * sec), taken)
        assertEquals(30 * sec, p.endExtensionMs(60 * sec, Long.MAX_VALUE))
    }

    @Test fun aSeekLandingJustPastAHoldDoesNotTakeIt() {
        val p = plan(PauseHold(100 * sec, 30 * sec), PauseHold(300 * sec, 30 * sec))
        // Within the late tolerance, playback arriving late would take it...
        assertEquals(100 * sec, p.dueAt(100 * sec + 1500)?.atMs)
        // ...but a seek from 10 s that lands there jumped over it.
        p.passOver(10 * sec, 100 * sec + 1500)
        assertNull(p.dueAt(100 * sec + 1500))
        assertEquals(30 * sec, p.endExtensionMs(60 * sec, 100 * sec + 1500))
        // A seek back does not mark anything; the second hold is still ahead.
        p.passOver(250 * sec, 200 * sec)
        assertEquals(300 * sec, p.dueAt(300 * sec)?.atMs)
    }

    @Test fun skippingAHoldSpendsItsTimeWithoutMovingItToTheEnd() {
        val p = plan(PauseHold(100 * sec, 60 * sec))
        val hold = p.dueAt(100 * sec)!!
        p.begin(hold)
        // Skipped a few seconds in: its planned length is spent all the same.
        p.spend(60 * sec)
        assertEquals(60 * sec, p.spentMs)
        assertEquals(40 * sec, p.endExtensionMs(100 * sec, Long.MAX_VALUE))
    }

    @Test fun theEndExtensionCountsAHoldUnderWayAndTheOnesAhead() {
        val p = plan(PauseHold(100 * sec, 30 * sec), PauseHold(200 * sec, 20 * sec))
        // Before anything: 50 s are planned ahead, the rest of 120 s is the end's.
        assertEquals(70 * sec, p.endExtensionMs(120 * sec, 0))
        val hold = p.dueAt(100 * sec)!!
        p.begin(hold)
        // Under way: its 30 s belong to it, 20 s are ahead.
        assertEquals(70 * sec, p.endExtensionMs(120 * sec, 100 * sec, inHoldMs = 30 * sec))
    }

    @Test fun reconfiguringKeepsTheHoldsAlreadyTaken() {
        val p = plan(PauseHold(100 * sec, 30 * sec), PauseHold(200 * sec, 30 * sec))
        p.begin(p.dueAt(100 * sec)!!)
        p.spend(30 * sec)
        // The listener changes Extend mid-session: the plan is sent again in full.
        p.configure(listOf(PauseHold(100 * sec, 60 * sec), PauseHold(200 * sec, 60 * sec)))
        assertNull(p.dueAt(100 * sec))
        assertEquals(60 * sec, p.nextAfter(150 * sec)!!.holdMs)
        assertEquals(30 * sec, p.spentMs)
    }

    @Test fun aNewSessionStartsWithNothingTakenOrSpent() {
        val p = plan(PauseHold(100 * sec, 30 * sec))
        p.begin(p.dueAt(100 * sec)!!)
        p.spend(30 * sec)
        p.resetSession()
        assertEquals(0L, p.spentMs)
        assertNotNull(p.dueAt(100 * sec))
        p.clear()
        assertTrue(p.isEmpty)
    }

    @Test fun duplicateAndUnorderedHoldsAreTidied() {
        val p = plan(PauseHold(200 * sec, 10 * sec), PauseHold(100 * sec, 10 * sec), PauseHold(100 * sec, 99 * sec))
        assertEquals(100 * sec, p.nextAfter(0)!!.atMs)
        assertEquals(20 * sec, p.plannedAheadMs(0))
    }

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
