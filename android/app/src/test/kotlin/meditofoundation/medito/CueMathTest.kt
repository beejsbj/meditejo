package meditofoundation.medito

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.abs

class CueMathTest {
    private val tol = 100.0 // ms: the accuracy the cues promise

    // ---- Pulse ----------------------------------------------------------

    @Test fun constantBpmBeatsAreEvenlySpaced() {
        for (n in 0L..20L) assertEquals(n * 1000.0, CueMath.beatTime(n, 60.0, 60.0, 0), 0.001)
        assertEquals(500.0, CueMath.beatTime(1, 120.0, 60.0, 0), 0.001) // no ramp: the start BPM holds
    }

    @Test fun phaseAndBeatTimeAreInverses() {
        for ((b0, b1, ramp) in listOf(Triple(80.0, 40.0, 10), Triple(40.0, 100.0, 5), Triple(60.0, 60.0, 3), Triple(120.0, 20.0, 60))) {
            for (n in listOf(1L, 2L, 7L, 50L, 300L, 1000L, 5000L)) {
                val t = CueMath.beatTime(n, b0, b1, ramp)
                assertEquals("b0=$b0 b1=$b1 ramp=$ramp n=$n", n.toDouble(), CueMath.pulsePhase(t, b0, b1, ramp), 1e-6)
            }
        }
    }

    @Test fun rampSettlesLinearlyThenHoldsTheEndBpm() {
        assertEquals(80.0, CueMath.bpmAt(0.0, 80.0, 40.0, 10), 1e-9)
        assertEquals(60.0, CueMath.bpmAt(5 * 60_000.0, 80.0, 40.0, 10), 1e-9)
        assertEquals(40.0, CueMath.bpmAt(10 * 60_000.0, 80.0, 40.0, 10), 1e-9)
        assertEquals(40.0, CueMath.bpmAt(45 * 60_000.0, 80.0, 40.0, 10), 1e-9)
        // 10 minutes ramping 80 -> 40 is 600 beats; then 40 BPM.
        assertEquals(600.0, CueMath.pulsePhase(10 * 60_000.0, 80.0, 40.0, 10), 1e-6)
        assertEquals(640.0, CueMath.pulsePhase(11 * 60_000.0, 80.0, 40.0, 10), 1e-6)
        assertEquals(11 * 60_000.0, CueMath.beatTime(640, 80.0, 40.0, 10), 1e-3)
    }

    @Test fun beatGapsGrowAsThePulseSlows() {
        val gaps = (1L..200L).map { CueMath.beatTime(it, 90.0, 50.0, 20) - CueMath.beatTime(it - 1, 90.0, 50.0, 20) }
        assertTrue(gaps.zipWithNext().all { (a, b) -> b >= a - 1e-6 })
        assertEquals(60_000.0 / 90.0, gaps.first(), 20.0)
    }

    @Test fun bpmIsClamped() {
        assertEquals(60_000.0 / 120.0, CueMath.beatTime(1, 500.0, 500.0, 0), 1e-6)
        assertEquals(60_000.0 / 20.0, CueMath.beatTime(1, 1.0, 1.0, 0), 1e-6)
    }

    @Test fun firstBeatAfterIsStrictlyAfter() {
        assertEquals(1L, CueMath.firstBeatAfter(0.0, 60.0, 60.0, 0))
        assertEquals(1L, CueMath.firstBeatAfter(999.0, 60.0, 60.0, 0))
        assertEquals(2L, CueMath.firstBeatAfter(1000.0, 60.0, 60.0, 0))
        val t = CueMath.beatTime(37, 100.0, 45.0, 12)
        assertEquals(38L, CueMath.firstBeatAfter(t, 100.0, 45.0, 12))
        assertEquals(37L, CueMath.firstBeatAfter(t - 1, 100.0, 45.0, 12))
    }

    // ---- Interval gaps ----------------------------------------------------

    @Test fun fixedIntervalsWithoutAWindow() {
        assertEquals(300_000L, CueMath.gapMs(5, 0, 7, 1))
        assertEquals(900_000L, CueMath.intervalTime(5, 0, 7, 3))
        assertEquals(1L, CueMath.firstIntervalAfter(0.0, 5, 0, 7))
        assertEquals(1L, CueMath.firstIntervalAfter(299_999.0, 5, 0, 7))
        assertEquals(2L, CueMath.firstIntervalAfter(300_000.0, 5, 0, 7))
        assertEquals(Long.MAX_VALUE, CueMath.firstIntervalAfter(0.0, 0, 0, 7))
    }

    @Test fun randomGapsStayInsideTheWindowAndAreRepeatable() {
        for (seed in listOf(0L, 1L, 42L, -9L, Long.MAX_VALUE)) {
            for (i in 1L..300L) {
                val g = CueMath.gapMs(10, 4, seed, i)
                assertTrue("gap $g", g in 6 * 60_000L..14 * 60_000L)
                assertEquals(g, CueMath.gapMs(10, 4, seed, i))
            }
        }
        // The window is clamped to a minute from below.
        for (i in 1L..300L) assertTrue(CueMath.gapMs(2, 5, 3, i) in 60_000L..7 * 60_000L)
        // Different seeds give different sequences.
        assertNotEquals(CueMath.gapMs(10, 4, 1, 1), CueMath.gapMs(10, 4, 2, 1))
    }

    @Test fun gapsMatchTheSwiftImplementation() {
        // Pinned values, also asserted in CueSchedulerTests.swift: the generators must agree.
        assertEquals(listOf(448_678L, 652_441L, 726_809L), (1L..3L).map { CueMath.gapMs(10, 4, 42, it) })
        assertEquals(409_580L, CueMath.gapMs(10, 4, -9, 1))
    }

    @Test fun randomGapsAreSpreadAcrossTheWindow() {
        val gaps = (1L..400L).map { CueMath.gapMs(10, 5, 99, it) }
        assertTrue(gaps.min() < 6 * 60_000L)
        assertTrue(gaps.max() > 14 * 60_000L)
        assertEquals(10 * 60_000.0, gaps.average(), 30_000.0)
    }

    @Test fun firstIntervalAfterMatchesTheRunningSum() {
        for (t in listOf(0.0, 1.0, 400_000.0, 3_000_000.0, 9_999_999.0)) {
            val i = CueMath.firstIntervalAfter(t, 7, 3, 5)
            assertTrue(CueMath.intervalTime(7, 3, 5, i) > t)
            if (i > 1) assertTrue(CueMath.intervalTime(7, 3, 5, i - 1) <= t)
        }
    }

    // ---- End, seek, speed ---------------------------------------------------

    @Test fun cuesAtOrAfterTheEndAreExcluded() {
        assertTrue(CueMath.insideSession(599_999.0, 600_000.0))
        assertFalse(CueMath.insideSession(600_000.0, 600_000.0))
        assertFalse(CueMath.insideSession(700_000.0, 600_000.0))
        assertTrue(CueMath.insideSession(1e12, null))
    }

    @Test fun remainingSessionTimeFollowsSpeedAndExtension() {
        assertEquals(60_000.0, CueMath.remainingSessionMs(540_000, 600_000, 1.0, 0, false, 0)!!, 1e-6)
        assertEquals(30_000.0, CueMath.remainingSessionMs(540_000, 600_000, 2.0, 0, false, 0)!!, 1e-6)
        assertEquals(60_000.0 + 120_000.0, CueMath.remainingSessionMs(540_000, 600_000, 1.0, 0, false, 120_000)!!, 1e-6)
        assertEquals(60_000.0 + 600_000.0, CueMath.remainingSessionMs(540_000, 600_000, 1.0, 1, false, 0)!!, 1e-6)
        assertNull(CueMath.remainingSessionMs(0, 600_000, 1.0, 0, true, 0))
        assertNull(CueMath.remainingSessionMs(0, 0, 1.0, 0, false, 0))
    }

    @Test fun sessionTimeAdvancesByMediaOverSpeed() {
        assertEquals(10_000.0, CueMath.advance(0.0, 0, 10_000, 1.0), 1e-9)
        assertEquals(5_000.0, CueMath.advance(0.0, 0, 10_000, 2.0), 1e-9)
        assertEquals(20_000.0, CueMath.advance(0.0, 0, 10_000, 0.5), 1e-9)
        assertEquals(-2_000.0, CueMath.advance(0.0, 10_000, 8_000, 1.0), 1e-9) // a seek back rewinds the session
    }

    @Test fun seeksAreToldFromPlayback() {
        assertFalse(CueMath.isSeek(100, 100, 1.0))
        assertFalse(CueMath.isSeek(0, 5000, 1.0)) // paused
        assertFalse(CueMath.isSeek(1500, 250, 2.0)) // fast playback with a late tick
        assertTrue(CueMath.isSeek(30_000, 250, 1.0))
        assertTrue(CueMath.isSeek(-5000, 250, 1.0))
    }

    @Test fun seekingForwardConsumesSkippedCuesWithoutABurst() {
        // A seek from 0 to 25 minutes with 5-minute bells: the next is the 30-minute one.
        val t = CueMath.advance(0.0, 0, 25 * 60_000, 1.0)
        val i = CueMath.firstIntervalAfter(t, 5, 0, 1)
        assertEquals(6L, i)
        assertEquals(30 * 60_000L, CueMath.intervalTime(5, 0, 1, i))
        // And back to the start re-arms the first one.
        assertEquals(1L, CueMath.firstIntervalAfter(CueMath.advance(t, 25 * 60_000, 0, 1.0), 5, 0, 1))
    }

    @Test fun startBellOnlyForAFreshStart() {
        assertTrue(CueMath.shouldRingStart(0))
        assertTrue(CueMath.shouldRingStart(1999))
        assertFalse(CueMath.shouldRingStart(2000))
    }

    // ---- Config ---------------------------------------------------------------

    @Test fun configReadsTheChannelMapAndClamps() {
        val cfg = CueConfig.fromMap(mapOf(
            "countdownSeconds" to 99, "startSound" to "assets/audio/a.wav", "endSound" to null,
            "intervalSound" to "assets/audio/b.wav", "intervalMinutes" to 12, "randomWindowMinutes" to 3,
            "pulseSound" to "assets/audio/pulse_click.wav", "pulseBpm" to 70, "pulseEndBpm" to 40.0,
            "pulseRampMinutes" to 10, "pulseVolume" to 3.0, "bellVolume" to 0.5, "extendMinutes" to 5,
            "isTimer" to true, "durationMs" to 600000, "randomSeed" to 12345,
            "autoplay" to true, "interludeSeconds" to 99,
        ))
        assertEquals(10_000L, cfg.countdownMs)
        assertEquals(300_000L, cfg.extensionMs)
        assertTrue(cfg.hasInterval); assertTrue(cfg.hasPulse); assertTrue(cfg.isTimer)
        assertEquals(1.0, cfg.pulseVolume, 0.0)
        assertEquals(12345L, cfg.randomSeed)
        assertNull(cfg.endSound)
        assertTrue(cfg.autoplay)
        assertEquals(30_000L, cfg.interludeMs)
        assertFalse(CueConfig.fromMap(emptyMap<String, Any?>()).hasInterval)
        assertFalse(CueConfig.fromMap(emptyMap<String, Any?>()).autoplay)
    }

    // ---- Halfway bell -----------------------------------------------------------

    private val min = 60_000.0

    /** Polls once a second from [from] to [to]; the session times at which it rang. */
    private fun ringsWhilePlaying(cue: HalfwayCue, from: Double, to: Double, endMs: (Double) -> Double?): List<Double> {
        val rang = ArrayList<Double>()
        var t = from
        while (t <= to) { if (cue.poll(t, endMs(t))) rang.add(t); t += 1000.0 }
        return rang
    }

    @Test fun halfwayIsHalfTheSessionEnd() {
        assertEquals(15 * min, CueMath.halfwayMs(20 * min + 10 * min)!!, 1e-9) // recording + extension
        assertEquals(12.5 * min, CueMath.halfwayMs(25 * min)!!, 1e-9) // timer
        assertNull(CueMath.halfwayMs(null))
        assertNull(CueMath.halfwayMs(0.0))
        assertNull(CueMath.halfwayMs(-5.0))
    }

    @Test fun configReadsHalfwayAndItReplacesTheIntervalBells() {
        val on = CueConfig.fromMap(mapOf("intervalSound" to "assets/audio/b.wav", "intervalMinutes" to 5, "intervalHalfway" to true))
        assertTrue(on.intervalHalfway); assertTrue(on.hasHalfway); assertFalse(on.hasInterval)
        val off = CueConfig.fromMap(mapOf("intervalSound" to "assets/audio/b.wav", "intervalMinutes" to 5, "intervalHalfway" to false))
        assertFalse(off.hasHalfway); assertTrue(off.hasInterval)
        val unset = CueConfig.fromMap(mapOf("intervalSound" to "assets/audio/b.wav", "intervalMinutes" to 5))
        assertFalse(unset.intervalHalfway); assertFalse(unset.hasHalfway); assertTrue(unset.hasInterval)
        val noSound = CueConfig.fromMap(mapOf("intervalMinutes" to 5, "intervalHalfway" to true))
        assertFalse(noSound.hasHalfway); assertFalse(noSound.hasInterval)
    }

    @Test fun halfwayRingsOnceWhenCrossed() {
        val cue = HalfwayCue().apply { arm() }
        val rang = ringsWhilePlaying(cue, 0.0, 20 * min) { 20 * min }
        assertEquals(listOf(10 * min), rang)
        assertFalse(cue.pending)
    }

    @Test fun nothingRingsUntilArmed() {
        val cue = HalfwayCue()
        assertTrue(ringsWhilePlaying(cue, 0.0, 20 * min) { 20 * min }.isEmpty())
        assertNull(cue.dueAt(20 * min))
    }

    @Test fun aPauseAcrossTheMidpointRingsOnceAndNeverEarly() {
        val cue = HalfwayCue().apply { arm() }
        val end = 20 * min
        // Played to just before the midpoint, then paused: session time is frozen.
        assertTrue(ringsWhilePlaying(cue, 0.0, 10 * min - 2000.0) { end }.isEmpty())
        repeat(50) { assertFalse(cue.poll(10 * min - 1000.0, end)) }
        assertTrue(cue.pending)
        // Resumed: it rings once when crossed.
        assertEquals(listOf(10 * min), ringsWhilePlaying(cue, 10 * min - 1000.0, 12 * min) { end })
    }

    @Test fun seekingForwardPastTheMidpointConsumesItSilently() {
        val cue = HalfwayCue().apply { arm() }
        val end = 20 * min
        assertFalse(cue.poll(10 * min + CueMath.INTERVAL_LATE_TOLERANCE_MS + 1, end))
        assertFalse(cue.pending)
        assertTrue(ringsWhilePlaying(cue, 10 * min + 2000.0, 20 * min) { end }.isEmpty())
        // A cue a hair late (inside the tolerance) still rings.
        val near = HalfwayCue().apply { arm() }
        assertTrue(near.poll(10 * min + CueMath.INTERVAL_LATE_TOLERANCE_MS, end))
    }

    @Test fun seekingBackAfterItRangRingsItAgain() {
        val cue = HalfwayCue().apply { arm() }
        val end = 20 * min
        assertEquals(1, ringsWhilePlaying(cue, 0.0, 12 * min) { end }.size)
        cue.arm() // the engine re-arms after a seek, back to 5 minutes
        assertEquals(listOf(10 * min), ringsWhilePlaying(cue, 5 * min, 12 * min) { end })
    }

    @Test fun theMidpointCanFallInTheExtension() {
        // A 10-minute recording heard in full, then a 30-minute extension: 40 minutes, halfway at 20.
        val extensionStart = 10 * min
        val end = extensionStart + 30 * min
        val cue = HalfwayCue().apply { arm() }
        assertEquals(20 * min, cue.dueAt(end)!!, 1e-9)
        assertEquals(listOf(20 * min), ringsWhilePlaying(cue, 0.0, end - 1000.0) { end })
    }

    @Test fun aSpeedChangeMovesTheMidpoint() {
        val cue = HalfwayCue().apply { arm() }
        // 20 minutes at 1x: due at 10. At 4 minutes the listener doubles the speed: the end
        // drops from 20 to 12 minutes of session time, so it is now due at 6.
        assertTrue(ringsWhilePlaying(cue, 0.0, 4 * min) { 20 * min }.isEmpty())
        assertEquals(6 * min, cue.dueAt(12 * min)!!, 1e-9)
        assertEquals(listOf(6 * min), ringsWhilePlaying(cue, 4 * min + 1000.0, 12 * min) { 12 * min })
    }

    @Test fun aMidpointAtOrPastTheEndNeverRings() {
        // Only a non-positive end puts the midpoint at or past it; it is unknown, so nothing rings.
        val cue = HalfwayCue().apply { arm() }
        assertTrue(ringsWhilePlaying(cue, 0.0, 5 * min) { 0.0 }.isEmpty())
        assertTrue(cue.pending)
        // And the end rule itself, as the engine applies it to every cue.
        val due = CueMath.halfwayMs(20 * min)!!
        assertTrue(CueMath.insideSession(due, 20 * min))
        assertFalse(CueMath.insideSession(20 * min, 20 * min))
        assertFalse(CueMath.insideSession(due, due))
    }

    @Test fun anUnknownEndNeverRingsAndStaysPending() {
        val cue = HalfwayCue().apply { arm() }
        assertTrue(ringsWhilePlaying(cue, 0.0, 60 * min) { null }.isEmpty())
        assertTrue(cue.pending)
        assertNull(cue.dueAt(null))
        // Once the end is known it rings (or is consumed as late), as normal.
        assertTrue(cue.poll(10 * min, 20 * min))
    }

    @Test fun disarmedHalfwayStaysSilent() {
        val cue = HalfwayCue().apply { arm(); disarm() }
        assertTrue(ringsWhilePlaying(cue, 0.0, 20 * min) { 20 * min }.isEmpty())
    }

    // ---- Halfway bell: engine wiring ----------------------------------------------

    private val tolerance = CueMath.INTERVAL_LATE_TOLERANCE_MS

    @Test fun reArmingJustAfterItRangDoesNotRingItTwice() {
        val bell = HalfwayBell()
        val end = 20 * min
        bell.rearm(true, 0.0, end)
        assertTrue(bell.fire(10 * min, end)) // rang on time
        // A settings change, a small seek, or an iOS jump over 750 ms lands inside the late tolerance.
        listOf(1.0, 500.0, tolerance).forEach { after ->
            bell.rearm(true, 10 * min + after, end)
            assertFalse("re-armed ${after}ms after it rang", bell.pending)
            assertFalse(bell.fire(10 * min + after, end))
        }
    }

    @Test fun reArmingBeforeTheMidpointRingsItWhenCrossed() {
        val bell = HalfwayBell()
        val end = 20 * min
        bell.rearm(true, 0.0, end)
        assertTrue(bell.fire(10 * min, end))
        bell.rearm(true, 5 * min, end) // seek back
        assertTrue(bell.pending)
        assertFalse(bell.fire(9 * min, end))
        assertTrue(bell.fire(10 * min, end))
        assertFalse(bell.pending)
    }

    @Test fun reArmingAtTheMidpointExactlyLeavesItUsedUp() {
        val bell = HalfwayBell()
        bell.rearm(true, 10 * min, 20 * min)
        assertFalse(bell.pending)
    }

    @Test fun aSettingsChangeTurnsHalfwayOnAndOffMidSession() {
        val bell = HalfwayBell()
        val end = 20 * min
        // Off at the start, switched on at 4 minutes: it rings at 10.
        bell.rearm(false, 0.0, end)
        assertFalse(bell.pending)
        assertFalse(bell.fire(10 * min, end))
        bell.rearm(true, 4 * min, end)
        assertTrue(bell.fire(10 * min, end))
        // Switched off again before it is due (or its sound removed: hasHalfway is false): silent.
        bell.rearm(true, 4 * min, end)
        bell.rearm(false, 6 * min, end)
        assertFalse(bell.pending)
        assertFalse(bell.fire(10 * min, end))
        // Switched on after the midpoint: it is not due, and never rings late.
        bell.rearm(true, 12 * min, end)
        assertFalse(bell.pending)
    }

    @Test fun reArmingWithAnUnknownEndWaitsForTheEnd() {
        val bell = HalfwayBell()
        bell.rearm(true, 3 * min, null)
        assertTrue(bell.pending)
        assertFalse(bell.fire(3 * min, null))
        assertTrue(bell.fire(10 * min, 20 * min))
    }

    @Test fun theExtensionPhaseUsesTheExtensionEnd() {
        // A 10-minute recording heard in full, then a 30-minute extension: halfway at minute 20.
        val extStart = 10 * min
        val extMs = (30 * min).toLong()
        val end = CueMath.extensionEndMs(extStart, extMs)
        assertEquals(40 * min, end, 1e-9)
        val bell = HalfwayBell()
        bell.rearm(true, 0.0, end)
        assertEquals(20 * min, bell.nextCheckMs(0.0, end), 1e-9)
        assertEquals(listOf(20 * min), (0..40 * 60).map { it * 1000.0 }.filter { bell.fire(it, end) })
    }

    @Test fun anExtensionEditedAfterItRangRingsAgainOnlyWhenTheMidpointMovesAhead() {
        val extStart = 10 * min
        val end = CueMath.extensionEndMs(extStart, (30 * min).toLong()) // halfway at 20
        val bell = HalfwayBell()
        bell.rearm(true, 0.0, end)
        assertTrue(bell.fire(20 * min, end))
        // Same length re-applied right after it rang: silent.
        val justAfter = 20 * min + 500
        bell.rearm(true, justAfter, end)
        assertFalse(bell.pending)
        // Longer (60 minutes: end 70, halfway 35): the midpoint is ahead again, so it rings again.
        val longer = CueMath.extensionEndMs(extStart, (60 * min).toLong())
        bell.rearm(true, justAfter, longer)
        assertEquals(35 * min, bell.nextCheckMs(justAfter, longer), 1e-9)
        assertTrue(bell.fire(35 * min, longer))
        // Shorter (10 minutes: end 20, halfway 10) once the session is past it: used up, silent.
        val shorter = CueMath.extensionEndMs(extStart, (10 * min).toLong())
        bell.rearm(true, 36 * min, shorter)
        assertFalse(bell.pending)
    }

    @Test fun nextCheckFollowsTheMidpointAndStopsWhenNothingIsPending() {
        val bell = HalfwayBell()
        assertEquals(Double.MAX_VALUE, bell.nextCheckMs(0.0, 20 * min), 0.0) // never armed
        bell.rearm(true, 0.0, 20 * min)
        assertEquals(10 * min, bell.nextCheckMs(0.0, 20 * min), 1e-9)
        // The end moves with speed: the next check follows it.
        assertEquals(6 * min, bell.nextCheckMs(4 * min, 12 * min), 1e-9)
        // End not known yet: look again a second on, rather than stop ticking.
        assertEquals(4 * min + 1000.0, bell.nextCheckMs(4 * min, null), 1e-9)
        // Crossed: nothing more to schedule.
        assertTrue(bell.fire(10 * min, 20 * min))
        assertEquals(Double.MAX_VALUE, bell.nextCheckMs(10 * min, 20 * min), 0.0)
        bell.rearm(false, 0.0, 20 * min)
        assertEquals(Double.MAX_VALUE, bell.nextCheckMs(0.0, 20 * min), 0.0)
    }

    // ---- Real listening ---------------------------------------------------------

    private fun play(tracker: ListeningTracker, from: Long, to: Long, step: Long = 1000) {
        var p = from
        tracker.rebase(p)
        while (p < to) { p = minOf(p + step, to); tracker.sample(p, true) }
    }

    @Test fun ninetyPercentListenedCompletes() {
        val duration = 600_000L
        val t = ListeningTracker()
        play(t, 0, 539_000)
        assertFalse(t.completed(duration))
        play(t, 539_000, 540_000)
        assertTrue(t.completed(duration))
        assertFalse(ListeningTracker().completed(0))
    }

    @Test fun seekingToTheEndIsNotListening() {
        val t = ListeningTracker()
        play(t, 0, 60_000)
        t.sample(599_000, true) // a jump, not a step
        t.sample(600_000, true)
        assertFalse(t.completed(600_000))
        assertEquals(61_000L, t.heardMs())
    }

    @Test fun hearingAStretchAgainAddsNothing() {
        val t = ListeningTracker()
        play(t, 0, 100_000)
        play(t, 0, 100_000)
        play(t, 50_000, 100_000)
        assertEquals(100_000L, t.heardMs())
        play(t, 100_000, 200_000)
        assertEquals(200_000L, t.heardMs())
    }

    @Test fun pausedTimeAndGapsDoNotCount() {
        val t = ListeningTracker()
        play(t, 0, 10_000)
        t.markNotPlaying()
        t.sample(10_500, false)
        t.sample(11_000, true) // first sample after resuming only rebases
        assertEquals(10_000L, t.heardMs())
        t.sample(12_000, true)
        assertEquals(11_000L, t.heardMs())
    }

    @Test fun skippingBackAndForthBy15SecondsIsNotListening() {
        val t = ListeningTracker()
        play(t, 0, 30_000)
        t.rebase(45_000) // skip forward 15 s
        play(t, 45_000, 60_000)
        assertEquals(45_000L, t.heardMs())
    }

    @Test fun fastPlaybackCountsMediaTime() {
        val t = ListeningTracker()
        play(t, 0, 540_000, step = 2000) // 2x, sampled each second
        assertTrue(t.completed(600_000))
    }
    @Test fun coverageRestoresAcrossResumedSessionsAndMergesRanges() {
        val tracker = ListeningTracker()
        tracker.restore(listOf(listOf(0L, 40_000L), listOf(30_000L, 80_000L)))
        assertEquals(80_000L, tracker.heardMs())
        val resumed = ListeningTracker()
        resumed.restore(tracker.snapshot())
        resumed.rebase(80_000L)
        for (position in 81_000L..90_000L step 1000L) resumed.sample(position, true)
        assertTrue(resumed.completed(100_000L))
    }
    @Test fun onlyHeardRecordingsAndFinishedTimersEarnCompletion() {
        // A recording opened and seeked to the end, then sat through its whole
        // extension: the extension does not stand in for listening.
        val t = ListeningTracker()
        play(t, 0, 60_000)
        t.rebase(3_600_000)
        assertFalse(CueMath.earnsCompletion(isTimer = false, heardEnough = t.completed(3_600_000), extensionFinished = true))
        assertFalse(CueMath.earnsCompletion(isTimer = false, heardEnough = t.completed(3_600_000), extensionFinished = false))
        // 90% really heard counts, with or without an extension after it.
        play(t, 60_000, 3_240_000)
        assertTrue(CueMath.earnsCompletion(isTimer = false, heardEnough = t.completed(3_600_000), extensionFinished = true))
        assertTrue(CueMath.earnsCompletion(isTimer = false, heardEnough = t.completed(3_600_000), extensionFinished = false))
        // A timer's silent file counts at its natural end.
        assertTrue(CueMath.earnsCompletion(isTimer = true, heardEnough = false, extensionFinished = false))
    }

    @Test fun onlyRecentListeningReceiptsAreKept() {
        val day = 24 * 60 * 60 * 1000L
        val now = 1000 * day
        val saved = mapOf("recent" to now - day, "old" to now - 181 * day, "unknown" to 0L)
        // A receipt with no save time (older format) is kept, as if saved now.
        assertEquals(setOf("old"), ListeningReceipts.stale(saved, now))
        assertEquals(setOf("t3"), ListeningReceipts.stale(mapOf("t1" to 0L, "t2" to now - day, "t3" to now - 2 * day), now, maxCount = 2))
        // Past the count, the oldest go first.
        val many = (1..5).associate { "t$it" to now - it * day }
        assertEquals(setOf("t4", "t5"), ListeningReceipts.stale(many, now, maxCount = 3))
        assertTrue(ListeningReceipts.stale(emptyMap(), now).isEmpty())
    }

    @Test fun malformedPersistedRangesCannotInventListening() {
        val tracker = ListeningTracker()
        tracker.restore(listOf(emptyList(), listOf(-1L, 100_000L), listOf(10L, 5L)))
        assertEquals(0L, tracker.heardMs())
        assertFalse(tracker.completed(100_000L))
    }

}
