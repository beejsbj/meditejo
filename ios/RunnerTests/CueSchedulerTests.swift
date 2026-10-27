import XCTest
@testable import Runner

/// Same cases as CueMathTest.kt: the two platforms must agree.
class CueSchedulerTests: XCTestCase {

    func testConstantBpmBeatsAreEvenlySpaced() {
        for n in 0...20 {
            XCTAssertEqual(CueMath.beatTime(Int64(n), start: 60, end: 60, rampMinutes: 0), Double(n) * 1000, accuracy: 0.001)
        }
        XCTAssertEqual(CueMath.beatTime(1, start: 120, end: 60, rampMinutes: 0), 500, accuracy: 0.001)
    }

    func testPhaseAndBeatTimeAreInverses() {
        for (b0, b1, ramp) in [(80.0, 40.0, 10), (40.0, 100.0, 5), (60.0, 60.0, 3), (120.0, 20.0, 60)] {
            for n in [Int64(1), 2, 7, 50, 300, 1000, 5000] {
                let t = CueMath.beatTime(n, start: b0, end: b1, rampMinutes: ramp)
                XCTAssertEqual(CueMath.pulsePhase(t, start: b0, end: b1, rampMinutes: ramp), Double(n), accuracy: 1e-6)
            }
        }
    }

    func testRampSettlesThenHoldsTheEndBpm() {
        XCTAssertEqual(CueMath.bpmAt(5 * 60_000, start: 80, end: 40, rampMinutes: 10), 60, accuracy: 1e-9)
        XCTAssertEqual(CueMath.bpmAt(45 * 60_000, start: 80, end: 40, rampMinutes: 10), 40, accuracy: 1e-9)
        XCTAssertEqual(CueMath.pulsePhase(10 * 60_000, start: 80, end: 40, rampMinutes: 10), 600, accuracy: 1e-6)
        XCTAssertEqual(CueMath.beatTime(640, start: 80, end: 40, rampMinutes: 10), 11 * 60_000, accuracy: 1e-3)
    }

    func testFirstBeatAfterIsStrictlyAfter() {
        XCTAssertEqual(CueMath.firstBeatAfter(0, start: 60, end: 60, rampMinutes: 0), 1)
        XCTAssertEqual(CueMath.firstBeatAfter(999, start: 60, end: 60, rampMinutes: 0), 1)
        XCTAssertEqual(CueMath.firstBeatAfter(1000, start: 60, end: 60, rampMinutes: 0), 2)
    }

    func testRandomGapsStayInsideTheWindowAndRepeat() {
        for seed in [Int64(0), 1, 42, -9] {
            for i in 1...300 {
                let g = CueMath.gapMs(intervalMinutes: 10, windowMinutes: 4, seed: seed, index: Int64(i))
                XCTAssertTrue(g >= 6 * 60_000 && g <= 14 * 60_000)
                XCTAssertEqual(g, CueMath.gapMs(intervalMinutes: 10, windowMinutes: 4, seed: seed, index: Int64(i)))
            }
        }
    }

    func testGapsMatchAndroid() {
        // Pinned values, also asserted in CueMathTest.kt: the generators must agree.
        let gaps = (1...3).map { CueMath.gapMs(intervalMinutes: 10, windowMinutes: 4, seed: 42, index: Int64($0)) }
        XCTAssertEqual(gaps, [448_678, 652_441, 726_809])
        XCTAssertEqual(CueMath.gapMs(intervalMinutes: 10, windowMinutes: 4, seed: -9, index: 1), 409_580)
        XCTAssertEqual(CueMath.gapMs(intervalMinutes: 5, windowMinutes: 0, seed: 7, index: 1), 300_000)
    }

    func testEndBoundaryIsExcluded() {
        XCTAssertTrue(CueMath.insideSession(599_999, end: 600_000))
        XCTAssertFalse(CueMath.insideSession(600_000, end: 600_000))
        XCTAssertTrue(CueMath.insideSession(1e12, end: nil))
    }

    // MARK: Halfway bell

    private let minute = 60_000.0

    /// Polls once a second from `from` to `to`; the session times at which it rang.
    private func rings(_ cue: inout HalfwayCue, from: Double, to: Double, end: (Double) -> Double?) -> [Double] {
        var rang: [Double] = []
        var t = from
        while t <= to {
            if cue.poll(sessionMs: t, endMs: end(t)) { rang.append(t) }
            t += 1000
        }
        return rang
    }

    func testHalfwayIsHalfTheSessionEnd() {
        XCTAssertEqual(CueMath.halfwayMs(30 * minute)!, 15 * minute, accuracy: 1e-9)
        XCTAssertEqual(CueMath.halfwayMs(25 * minute)!, 12.5 * minute, accuracy: 1e-9)
        XCTAssertNil(CueMath.halfwayMs(nil))
        XCTAssertNil(CueMath.halfwayMs(0))
        XCTAssertNil(CueMath.halfwayMs(-5))
    }

    func testConfigReadsHalfwayAndItReplacesTheIntervalBells() {
        let on = CueConfig(map: ["intervalSound": "assets/audio/b.wav", "intervalMinutes": 5, "intervalHalfway": true])
        XCTAssertTrue(on.intervalHalfway)
        XCTAssertTrue(on.hasHalfway)
        XCTAssertFalse(on.hasInterval)
        let off = CueConfig(map: ["intervalSound": "assets/audio/b.wav", "intervalMinutes": 5, "intervalHalfway": false])
        XCTAssertFalse(off.hasHalfway)
        XCTAssertTrue(off.hasInterval)
        let unset = CueConfig(map: ["intervalSound": "assets/audio/b.wav", "intervalMinutes": 5])
        XCTAssertFalse(unset.hasHalfway)
        XCTAssertTrue(unset.hasInterval)
        let noSound = CueConfig(map: ["intervalMinutes": 5, "intervalHalfway": true])
        XCTAssertFalse(noSound.hasHalfway)
        XCTAssertFalse(noSound.hasInterval)
    }

    func testHalfwayRingsOnceWhenCrossed() {
        var cue = HalfwayCue()
        cue.arm()
        let rang = rings(&cue, from: 0, to: 20 * minute) { _ in 20 * minute }
        XCTAssertEqual(rang, [10 * minute])
        XCTAssertFalse(cue.pending)
        var idle = HalfwayCue()
        let silent = rings(&idle, from: 0, to: 20 * minute) { _ in 20 * minute }
        XCTAssertTrue(silent.isEmpty)
    }

    func testPauseAcrossTheMidpointRingsOnceAndNeverEarly() {
        var cue = HalfwayCue()
        cue.arm()
        let end = 20 * minute
        let silent = rings(&cue, from: 0, to: 10 * minute - 2000) { _ in end }
        XCTAssertTrue(silent.isEmpty)
        for _ in 0..<50 { XCTAssertFalse(cue.poll(sessionMs: 10 * minute - 1000, endMs: end)) }
        XCTAssertTrue(cue.pending)
        let rang = rings(&cue, from: 10 * minute - 1000, to: 12 * minute) { _ in end }
        XCTAssertEqual(rang, [10 * minute])
    }

    func testSeekingForwardPastTheMidpointConsumesItSilently() {
        var cue = HalfwayCue()
        cue.arm()
        let end = 20 * minute
        XCTAssertFalse(cue.poll(sessionMs: 10 * minute + CueMath.intervalLateToleranceMs + 1, endMs: end))
        XCTAssertFalse(cue.pending)
        let silent = rings(&cue, from: 10 * minute + 2000, to: 20 * minute) { _ in end }
        XCTAssertTrue(silent.isEmpty)
        var near = HalfwayCue()
        near.arm()
        XCTAssertTrue(near.poll(sessionMs: 10 * minute + CueMath.intervalLateToleranceMs, endMs: end))
    }

    func testSeekingBackAfterItRangRingsItAgain() {
        var cue = HalfwayCue()
        cue.arm()
        let end = 20 * minute
        let rang = rings(&cue, from: 0, to: 12 * minute) { _ in end }
        XCTAssertEqual(rang.count, 1)
        cue.arm()
        let again = rings(&cue, from: 5 * minute, to: 12 * minute) { _ in end }
        XCTAssertEqual(again, [10 * minute])
    }

    func testTheMidpointCanFallInTheExtension() {
        let end = 10 * minute + 30 * minute
        var cue = HalfwayCue()
        cue.arm()
        XCTAssertEqual(cue.dueAt(endMs: end)!, 20 * minute, accuracy: 1e-9)
        let rang = rings(&cue, from: 0, to: end - 1000) { _ in end }
        XCTAssertEqual(rang, [20 * minute])
    }

    func testASpeedChangeMovesTheMidpoint() {
        var cue = HalfwayCue()
        cue.arm()
        let silent = rings(&cue, from: 0, to: 4 * minute) { _ in 20 * minute }
        XCTAssertTrue(silent.isEmpty)
        XCTAssertEqual(cue.dueAt(endMs: 12 * minute)!, 6 * minute, accuracy: 1e-9)
        let rang = rings(&cue, from: 4 * minute + 1000, to: 12 * minute) { _ in 12 * minute }
        XCTAssertEqual(rang, [6 * minute])
    }

    func testAMidpointAtOrPastTheEndNeverRings() {
        var cue = HalfwayCue()
        cue.arm()
        let silent = rings(&cue, from: 0, to: 5 * minute) { _ in 0 }
        XCTAssertTrue(silent.isEmpty)
        XCTAssertTrue(cue.pending)
        let due = CueMath.halfwayMs(20 * minute)!
        XCTAssertTrue(CueMath.insideSession(due, end: 20 * minute))
        XCTAssertFalse(CueMath.insideSession(20 * minute, end: 20 * minute))
        XCTAssertFalse(CueMath.insideSession(due, end: due))
    }

    func testAnUnknownEndNeverRingsAndStaysPending() {
        var cue = HalfwayCue()
        cue.arm()
        let silent = rings(&cue, from: 0, to: 60 * minute) { _ in nil }
        XCTAssertTrue(silent.isEmpty)
        XCTAssertTrue(cue.pending)
        XCTAssertNil(cue.dueAt(endMs: nil))
        XCTAssertTrue(cue.poll(sessionMs: 10 * minute, endMs: 20 * minute))
    }

    // MARK: Halfway bell: scheduler wiring

    private let tolerance = CueMath.intervalLateToleranceMs

    func testReArmingJustAfterItRangDoesNotRingItTwice() {
        var bell = HalfwayBell()
        let end = 20 * minute
        bell.rearm(enabled: true, sessionMs: 0, endMs: end)
        XCTAssertTrue(bell.fire(sessionMs: 10 * minute, endMs: end))
        for after in [1.0, 500.0, tolerance] {
            bell.rearm(enabled: true, sessionMs: 10 * minute + after, endMs: end)
            XCTAssertFalse(bell.pending, "re-armed \(after)ms after it rang")
            XCTAssertFalse(bell.fire(sessionMs: 10 * minute + after, endMs: end))
        }
    }

    func testReArmingBeforeTheMidpointRingsItWhenCrossed() {
        var bell = HalfwayBell()
        let end = 20 * minute
        bell.rearm(enabled: true, sessionMs: 0, endMs: end)
        XCTAssertTrue(bell.fire(sessionMs: 10 * minute, endMs: end))
        bell.rearm(enabled: true, sessionMs: 5 * minute, endMs: end)
        XCTAssertTrue(bell.pending)
        XCTAssertFalse(bell.fire(sessionMs: 9 * minute, endMs: end))
        XCTAssertTrue(bell.fire(sessionMs: 10 * minute, endMs: end))
        XCTAssertFalse(bell.pending)
    }

    func testReArmingAtTheMidpointExactlyLeavesItUsedUp() {
        var bell = HalfwayBell()
        bell.rearm(enabled: true, sessionMs: 10 * minute, endMs: 20 * minute)
        XCTAssertFalse(bell.pending)
    }

    func testASettingsChangeTurnsHalfwayOnAndOffMidSession() {
        var bell = HalfwayBell()
        let end = 20 * minute
        bell.rearm(enabled: false, sessionMs: 0, endMs: end)
        XCTAssertFalse(bell.pending)
        XCTAssertFalse(bell.fire(sessionMs: 10 * minute, endMs: end))
        bell.rearm(enabled: true, sessionMs: 4 * minute, endMs: end)
        XCTAssertTrue(bell.fire(sessionMs: 10 * minute, endMs: end))
        bell.rearm(enabled: true, sessionMs: 4 * minute, endMs: end)
        bell.rearm(enabled: false, sessionMs: 6 * minute, endMs: end)
        XCTAssertFalse(bell.pending)
        XCTAssertFalse(bell.fire(sessionMs: 10 * minute, endMs: end))
        bell.rearm(enabled: true, sessionMs: 12 * minute, endMs: end)
        XCTAssertFalse(bell.pending)
    }

    func testReArmingWithAnUnknownEndWaitsForTheEnd() {
        var bell = HalfwayBell()
        bell.rearm(enabled: true, sessionMs: 3 * minute, endMs: nil)
        XCTAssertTrue(bell.pending)
        XCTAssertFalse(bell.fire(sessionMs: 3 * minute, endMs: nil))
        XCTAssertTrue(bell.fire(sessionMs: 10 * minute, endMs: 20 * minute))
    }

    func testTheExtensionPhaseUsesTheExtensionEnd() {
        let end = CueMath.extensionEndMs(extensionStartSessionMs: 10 * minute, extensionMs: 30 * minute)
        XCTAssertEqual(end, 40 * minute, accuracy: 1e-9)
        var bell = HalfwayBell()
        bell.rearm(enabled: true, sessionMs: 0, endMs: end)
        XCTAssertEqual(bell.nextCheckMs(sessionMs: 0, endMs: end), 20 * minute, accuracy: 1e-9)
        let rang = stride(from: 0.0, through: 40 * minute, by: 1000).filter { bell.fire(sessionMs: $0, endMs: end) }
        XCTAssertEqual(rang, [20 * minute])
    }

    func testAnExtensionEditedAfterItRangRingsAgainOnlyWhenTheMidpointMovesAhead() {
        let start = 10 * minute
        let end = CueMath.extensionEndMs(extensionStartSessionMs: start, extensionMs: 30 * minute)
        var bell = HalfwayBell()
        bell.rearm(enabled: true, sessionMs: 0, endMs: end)
        XCTAssertTrue(bell.fire(sessionMs: 20 * minute, endMs: end))
        let justAfter = 20 * minute + 500
        bell.rearm(enabled: true, sessionMs: justAfter, endMs: end)
        XCTAssertFalse(bell.pending)
        let longer = CueMath.extensionEndMs(extensionStartSessionMs: start, extensionMs: 60 * minute)
        bell.rearm(enabled: true, sessionMs: justAfter, endMs: longer)
        XCTAssertEqual(bell.nextCheckMs(sessionMs: justAfter, endMs: longer), 35 * minute, accuracy: 1e-9)
        XCTAssertTrue(bell.fire(sessionMs: 35 * minute, endMs: longer))
        let shorter = CueMath.extensionEndMs(extensionStartSessionMs: start, extensionMs: 10 * minute)
        bell.rearm(enabled: true, sessionMs: 36 * minute, endMs: shorter)
        XCTAssertFalse(bell.pending)
    }

    func testNextCheckFollowsTheMidpointAndStopsWhenNothingIsPending() {
        var bell = HalfwayBell()
        XCTAssertEqual(bell.nextCheckMs(sessionMs: 0, endMs: 20 * minute), .greatestFiniteMagnitude)
        bell.rearm(enabled: true, sessionMs: 0, endMs: 20 * minute)
        XCTAssertEqual(bell.nextCheckMs(sessionMs: 0, endMs: 20 * minute), 10 * minute, accuracy: 1e-9)
        XCTAssertEqual(bell.nextCheckMs(sessionMs: 4 * minute, endMs: 12 * minute), 6 * minute, accuracy: 1e-9)
        XCTAssertEqual(bell.nextCheckMs(sessionMs: 4 * minute, endMs: nil), 4 * minute + 1000, accuracy: 1e-9)
        XCTAssertTrue(bell.fire(sessionMs: 10 * minute, endMs: 20 * minute))
        XCTAssertEqual(bell.nextCheckMs(sessionMs: 10 * minute, endMs: 20 * minute), .greatestFiniteMagnitude)
        bell.rearm(enabled: false, sessionMs: 0, endMs: 20 * minute)
        XCTAssertEqual(bell.nextCheckMs(sessionMs: 0, endMs: 20 * minute), .greatestFiniteMagnitude)
    }

    func testNinetyPercentListenedCompletes() {
        let t = ListeningTracker()
        var p: Int64 = 0
        t.rebase(0)
        while p < 539_000 { p += 1000; t.sample(p, playing: true) }
        XCTAssertFalse(t.completed(durationMs: 600_000))
        p += 1000; t.sample(p, playing: true)
        XCTAssertTrue(t.completed(durationMs: 600_000))
    }

    func testSeekingToTheEndIsNotListening() {
        let t = ListeningTracker()
        t.rebase(0)
        var p: Int64 = 0
        while p < 60_000 { p += 1000; t.sample(p, playing: true) }
        t.sample(599_000, playing: true)
        XCTAssertFalse(t.completed(durationMs: 600_000))
        XCTAssertEqual(t.heardMs, 60_000)
    }
    func testARepeatPassMustBeNinetyPercentHeardOnItsOwn() {
        let t = ListeningTracker()
        t.rebase(0)
        var p: Int64 = 0
        while p < 600_000 { p += 1000; t.sample(p, playing: true) }
        XCTAssertTrue(t.completed(durationMs: 600_000))
        // Pass two: a jump to the end of the loop is not listening, although
        // the whole recording was heard before.
        t.startPass()
        t.sample(599_000, playing: true)
        t.sample(600_000, playing: true)
        XCTAssertFalse(t.completed(durationMs: 600_000))
        XCTAssertEqual(t.heardMs, 1_000) // only the last step after the jump
        // A pass heard in full starts from the first step.
        t.startPass()
        p = 0
        while p < 600_000 { p += 1000; t.sample(p, playing: true) }
        XCTAssertTrue(t.completed(durationMs: 600_000))
    }

    func testCoverageRestoresAcrossResumedSessions() {
        let first = ListeningTracker()
        first.restore([[0, 40_000], [30_000, 80_000]])
        XCTAssertEqual(first.heardMs, 80_000)
        let resumed = ListeningTracker()
        resumed.restore(first.snapshot())
        resumed.rebase(80_000)
        for p in stride(from: Int64(81_000), through: Int64(90_000), by: 1000) { resumed.sample(p, playing: true) }
        XCTAssertTrue(resumed.completed(durationMs: 100_000))
    }

    func testShortSeekDoesNotCountAsRenderedAudio() {
        let tracker = ListeningTracker()
        tracker.rebase(0)
        tracker.sample(3000, playing: true, realElapsedMs: 10, speed: 1)
        XCTAssertEqual(tracker.heardMs, 0)
    }

    func testOnlyRecentListeningReceiptsAreKept() {
        let day = 24.0 * 60 * 60
        let now = 1000 * day
        let saved = ["recent": now - day, "old": now - 181 * day, "unknown": 0.0]
        XCTAssertEqual(ListeningTracker.staleReceipts(saved, now: now,
                                                      maxAgeSeconds: ListeningTracker.receiptMaxAgeSeconds,
                                                      maxCount: ListeningTracker.receiptMaxCount),
                       ["old"])
        var many: [String: Double] = [:]
        for i in 1...5 { many["t\(i)"] = now - Double(i) * day }
        XCTAssertEqual(ListeningTracker.staleReceipts(many, now: now, maxAgeSeconds: ListeningTracker.receiptMaxAgeSeconds,
                                                      maxCount: 3),
                       ["t4", "t5"])
    }
}
