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

}
