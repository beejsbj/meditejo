import AVFoundation
import Flutter
import Foundation

// The cue system on iOS. It mirrors CueMath.kt / CueEngine.kt on Android; keep
// the two in step. Playback itself stays with just_audio in Dart, so the
// timeline is driven by `transport` reports instead of a player read: each
// report re-anchors the session clock to the monotonic clock, and the cues
// are timed against that clock, with no per-beat Dart round trip.

// MARK: - Configuration

struct CueConfig {
    var countdownSeconds = 0
    var startSound: String?
    var endSound: String?
    var intervalSound: String?
    var intervalMinutes = 0
    var randomWindowMinutes = 0
    var pulseSound: String?
    var pulseBpm = 60.0
    var pulseEndBpm = 60.0
    var pulseRampMinutes = 0
    var pulseVolume = 1.0
    var bellVolume = 1.0
    /// All the silence a guided session adds: after the recording and in its
    /// pauses (60 minutes each in the app). iOS holds all of it at the end.
    var extendMinutes = 0
    var isTimer = false
    var durationMs: Int64 = 0
    var randomSeed: Int64 = 0
    /// Autoplay is on: the session end holds the app for the interlude.
    var autoplay = false
    var interludeSeconds = 0
    /// The interval bell is "Halfway": one bell at the midpoint, not every N minutes.
    var intervalHalfway = false

    var countdownMs: Double { Double(min(max(countdownSeconds, 0), 10)) * 1000 }
    var extensionMs: Double { Double(min(max(extendMinutes, 0), 120)) * 60_000 }
    var interludeMs: Double { Double(min(max(interludeSeconds, 0), 30)) * 1000 }
    /// Every-N-minutes bells; never alongside the halfway bell.
    var hasInterval: Bool { !intervalHalfway && intervalMinutes > 0 && intervalSound != nil }
    var hasHalfway: Bool { intervalHalfway && intervalSound != nil }
    var hasPulse: Bool { pulseSound != nil }

    init() {}

    init(map: [String: Any]) {
        func int(_ k: String) -> Int { (map[k] as? NSNumber)?.intValue ?? 0 }
        func i64(_ k: String) -> Int64 { (map[k] as? NSNumber)?.int64Value ?? 0 }
        func dbl(_ k: String, _ d: Double) -> Double { (map[k] as? NSNumber)?.doubleValue ?? d }
        func str(_ k: String) -> String? {
            guard let s = map[k] as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return s
        }
        countdownSeconds = int("countdownSeconds")
        startSound = str("startSound")
        endSound = str("endSound")
        intervalSound = str("intervalSound")
        intervalMinutes = min(max(int("intervalMinutes"), 0), 60)
        randomWindowMinutes = min(max(int("randomWindowMinutes"), 0), 60)
        pulseSound = str("pulseSound")
        pulseBpm = dbl("pulseBpm", 60)
        pulseEndBpm = dbl("pulseEndBpm", pulseBpm)
        pulseRampMinutes = min(max(int("pulseRampMinutes"), 0), 60)
        pulseVolume = min(max(dbl("pulseVolume", 1), 0), 1)
        bellVolume = min(max(dbl("bellVolume", 1), 0), 1)
        extendMinutes = min(max(int("extendMinutes"), 0), 120)
        isTimer = (map["isTimer"] as? Bool) ?? false
        durationMs = i64("durationMs")
        randomSeed = i64("randomSeed")
        autoplay = (map["autoplay"] as? Bool) ?? false
        interludeSeconds = min(max(int("interludeSeconds"), 0), 30)
        intervalHalfway = (map["intervalHalfway"] as? Bool) ?? false
    }
}

// MARK: - Maths (pure; same results as CueMath.kt)

enum CueMath {
    static let minBpm = 20.0
    static let maxBpm = 120.0
    static let pulseLateToleranceMs = 400.0
    static let intervalLateToleranceMs = 1500.0
    static let listeningMaxStepMs: Int64 = 5000
    static let listeningThreshold = 0.9

    private static func clampBpm(_ v: Double) -> Double { min(max(v, minBpm), maxBpm) }

    static func bpmAt(_ tMs: Double, start: Double, end: Double, rampMinutes: Int) -> Double {
        let b0 = clampBpm(start), b1 = clampBpm(end)
        let ramp = Double(rampMinutes) * 60_000
        if ramp <= 0 { return b0 }
        if tMs >= ramp { return b1 }
        if tMs <= 0 { return b0 }
        return b0 + (b1 - b0) * (tMs / ramp)
    }

    /// Beats elapsed at session time tMs: the integral of BPM / 60.
    static func pulsePhase(_ tMs: Double, start: Double, end: Double, rampMinutes: Int) -> Double {
        if tMs <= 0 { return 0 }
        let b0 = clampBpm(start), b1 = clampBpm(end)
        let ramp = Double(rampMinutes) * 60_000
        if ramp <= 0 { return b0 * tMs / 60_000 }
        let tr = min(tMs, ramp)
        var beats = (b0 * tr + (b1 - b0) * tr * tr / (2 * ramp)) / 60_000
        if tMs > ramp { beats += b1 * (tMs - ramp) / 60_000 }
        return beats
    }

    /// Session time of beat n (beat 0 is at 0): the analytical inverse of pulsePhase.
    static func beatTime(_ n: Int64, start: Double, end: Double, rampMinutes: Int) -> Double {
        if n <= 0 { return 0 }
        let b0 = clampBpm(start), b1 = clampBpm(end)
        let ramp = Double(rampMinutes) * 60_000
        if ramp <= 0 { return Double(n) * 60_000 / b0 }
        let rampBeats = pulsePhase(ramp, start: b0, end: b1, rampMinutes: rampMinutes)
        if Double(n) >= rampBeats { return ramp + (Double(n) - rampBeats) * 60_000 / b1 }
        let a = (b1 - b0) / (2 * ramp)
        let c = Double(n) * 60_000
        if abs(a) < 1e-15 { return c / b0 }
        return 2 * c / (b0 + (b0 * b0 + 4 * a * c).squareRoot())
    }

    /// Number of the first beat strictly after tMs.
    static func firstBeatAfter(_ tMs: Double, start: Double, end: Double, rampMinutes: Int) -> Int64 {
        if tMs < 0 { return 0 }
        var n = Int64((pulsePhase(tMs, start: start, end: end, rampMinutes: rampMinutes) + 1e-9).rounded(.down)) + 1
        while n > 0 && beatTime(n - 1, start: start, end: end, rampMinutes: rampMinutes) > tMs { n -= 1 }
        while beatTime(n, start: start, end: end, rampMinutes: rampMinutes) <= tMs { n += 1 }
        return n
    }

    private static func mix64(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1); the same for the same seed and index, and the same as on Android.
    static func unit(seed: Int64, index: Int64) -> Double {
        let golden = Int64(bitPattern: 0x9E37_79B9_7F4A_7C15)
        let x = UInt64(bitPattern: seed &* 31 &+ index &* golden)
        return Double(mix64(x) >> 11) / 9_007_199_254_740_992.0
    }

    /// Gap before cue number `index` (1-based): uniform [max(1, I - W), I + W] minutes.
    static func gapMs(intervalMinutes: Int, windowMinutes: Int, seed: Int64, index: Int64) -> Int64 {
        let lo = Double(max(1, intervalMinutes - windowMinutes)) * 60_000
        let hi = Double(intervalMinutes + windowMinutes) * 60_000
        if windowMinutes <= 0 || hi <= lo { return Int64(Double(intervalMinutes) * 60_000) }
        return Int64(lo + unit(seed: seed, index: index) * (hi - lo))
    }

    static func intervalTime(intervalMinutes: Int, windowMinutes: Int, seed: Int64, index: Int64) -> Int64 {
        if windowMinutes <= 0 { return Int64(intervalMinutes) * 60_000 * index }
        var t: Int64 = 0
        var i: Int64 = 1
        while i <= index { t += gapMs(intervalMinutes: intervalMinutes, windowMinutes: windowMinutes, seed: seed, index: i); i += 1 }
        return t
    }

    static func firstIntervalAfter(_ tMs: Double, intervalMinutes: Int, windowMinutes: Int, seed: Int64) -> Int64 {
        if intervalMinutes <= 0 { return Int64.max }
        if windowMinutes <= 0 { return Int64((max(tMs, 0) / (Double(intervalMinutes) * 60_000)).rounded(.down)) + 1 }
        var t: Int64 = 0
        var i: Int64 = 0
        while Double(t) <= tMs {
            i += 1
            t += gapMs(intervalMinutes: intervalMinutes, windowMinutes: windowMinutes, seed: seed, index: i)
        }
        return i
    }

    /// A cue rings only inside the session; the end boundary is excluded. Unknown end: always inside.
    static func insideSession(_ deadlineMs: Double, end: Double?) -> Bool {
        guard let end = end else { return true }
        return deadlineMs < end
    }

    /// Session time of the halfway bell: half of the session end, which already
    /// includes the extension and follows speed. nil when the end is unknown.
    static func halfwayMs(_ endMs: Double?) -> Double? {
        guard let end = endMs, end > 0 else { return nil }
        return end / 2
    }

    /// Session time left in the voice. nil for an endless or unknown-length track.
    static func remainingSessionMs(positionMs: Double, durationMs: Double, speed: Double,
                                   itemsAfterCurrent: Int, endless: Bool, extensionMs: Double) -> Double? {
        if endless || durationMs <= 0 { return nil }
        let media = max(0, durationMs - positionMs) + durationMs * Double(itemsAfterCurrent)
        return media / max(speed, 0.05) + extensionMs
    }

    /// Session time at which a session ends once its extension is under way.
    static func extensionEndMs(extensionStartSessionMs: Double, extensionMs: Double) -> Double {
        extensionStartSessionMs + extensionMs
    }

    static func shouldRingStart(positionMs: Double) -> Bool { positionMs < 2000 }
}

// MARK: - Halfway bell

/// The one halfway bell: pending until crossed, re-armed by a seek. The
/// midpoint is read from the session end on every poll, so a speed change moves it.
struct HalfwayCue {
    private(set) var pending = false

    mutating func arm() { pending = true }
    mutating func disarm() { pending = false }

    /// Session time it is due at, or nil (not pending, or end unknown). For scheduling the next tick.
    func dueAt(endMs: Double?) -> Double? { pending ? CueMath.halfwayMs(endMs) : nil }

    /// True when it should ring now. Once the midpoint is crossed it is consumed,
    /// and rings only if it is on time and inside the session. An unknown end
    /// leaves it pending.
    mutating func poll(sessionMs: Double, endMs: Double?) -> Bool {
        guard let due = dueAt(endMs: endMs) else { return false }
        if sessionMs < due { return false }
        pending = false
        return sessionMs - due <= CueMath.intervalLateToleranceMs && CueMath.insideSession(due, end: endMs)
    }
}

/// What the scheduler does around `HalfwayCue`: re-arm when the cues are
/// re-armed (a seek, a settings change, the extension starting), and say when
/// to look again. Kept out of the scheduler so it can be tested without a player.
struct HalfwayBell {
    private var cue = HalfwayCue()
    var pending: Bool { cue.pending }

    mutating func disarm() { cue.disarm() }

    /// Arms the bell for a session now at `sessionMs` with `endMs` to go. A bell
    /// that is still pending stays pending, so a re-arm between ticks cannot use
    /// up a bell that has not rung yet (`fire` still consumes a late one
    /// silently). A bell that has rung rings again only if the session is back
    /// before the midpoint (a seek back, or a longer extension that moves it
    /// ahead): re-arming within the late tolerance after it rang must not ring
    /// it twice. An unknown end arms it, to be judged once the end is known.
    mutating func rearm(enabled: Bool, sessionMs: Double, endMs: Double?) {
        guard enabled else { cue.disarm(); return }
        if cue.pending { return }
        let beforeMidpoint = CueMath.halfwayMs(endMs).map { sessionMs < $0 } ?? true
        if beforeMidpoint { cue.arm() }
    }

    /// True when the bell should ring now.
    mutating func fire(sessionMs: Double, endMs: Double?) -> Bool { cue.poll(sessionMs: sessionMs, endMs: endMs) }

    /// Session time to look again at: the midpoint while pending, a second on
    /// while pending with no known end yet (a stream whose length arrives late),
    /// and never (`greatestFiniteMagnitude`) when nothing is pending.
    func nextCheckMs(sessionMs: Double, endMs: Double?) -> Double {
        guard cue.pending else { return .greatestFiniteMagnitude }
        return cue.dueAt(endMs: endMs) ?? sessionMs + 1000
    }
}

// MARK: - Real listening

/// Each stretch of media counts once, only when playback walked through it in
/// small steps. A seek is never listening.
final class ListeningTracker {
    private var ranges: [(Int64, Int64)] = []
    private var last: Int64 = -1
    private let maxStepMs: Int64

    init(maxStepMs: Int64 = CueMath.listeningMaxStepMs) { self.maxStepMs = maxStepMs }

    func reset() { ranges.removeAll(); last = -1 }
    func snapshot() -> [[Int64]] { ranges.map { [$0.0, $0.1] } }
    func restore(_ saved: [[Int64]]) {
        reset()
        for r in saved where r.count == 2 && r[0] >= 0 && r[1] > r[0] { add(r[0], r[1]) }
    }
    func rebase(_ positionMs: Int64) { last = positionMs }
    func markNotPlaying() { last = -1 }

    /// A new pass of a looped recording: nothing heard yet, playback at the start.
    func startPass() { ranges.removeAll(); last = 0 }

    func sample(_ positionMs: Int64, playing: Bool, realElapsedMs: Double? = nil, speed: Double = 1) {
        if !playing || positionMs < 0 { last = -1; return }
        let from = last
        last = positionMs
        if from < 0 { return }
        let step = positionMs - from
        if step <= 0 || step > maxStepMs { return }
        if let elapsed = realElapsedMs, Double(step) > max(elapsed, 0) * max(speed, 0.05) + 100 { return }
        add(from, positionMs)
    }

    private func add(_ start: Int64, _ end: Int64) {
        var s = start, e = end
        var merged: [(Int64, Int64)] = []
        var placed = false
        for r in ranges {
            if r.1 < s { merged.append(r) }
            else if r.0 > e {
                if !placed { merged.append((s, e)); placed = true }
                merged.append(r)
            } else { s = min(s, r.0); e = max(e, r.1) }
        }
        if !placed { merged.append((s, e)) }
        ranges = merged
    }

    var heardMs: Int64 { ranges.reduce(0) { $0 + ($1.1 - $1.0) } }

    func completed(durationMs: Int64) -> Bool {
        durationMs > 0 && Double(heardMs) >= (Double(durationMs) * CueMath.listeningThreshold).rounded(.up)
    }

    /// Unfinished tracks leave a receipt (a finished one is removed); only
    /// recent ones are kept. Same rule as ListeningReceipts in CueMath.kt.
    static let receiptMaxAgeSeconds: Double = 180 * 24 * 60 * 60
    static let receiptMaxCount = 200

    /// Receipts to drop, from each one's last save time; an unknown time (0) counts as now.
    static func staleReceipts(_ savedAt: [String: Double], now: Double,
                              maxAgeSeconds: Double, maxCount: Int) -> Set<String> {
        let known = savedAt.mapValues { $0 > 0 ? $0 : now }
        var stale = Set(known.filter { now - $0.value > maxAgeSeconds }.map { $0.key })
        let newestFirst = known.sorted { $0.value > $1.value }
        for entry in newestFirst.dropFirst(maxCount) { stale.insert(entry.key) }
        return stale
    }
}

// MARK: - Sounds

/// Cue sounds decoded once into small AVAudioPlayer pools, so a beat never
/// opens a file. Assets are Flutter asset paths.
final class CueSoundBank {
    private var pools: [String: [AVAudioPlayer]] = [:]
    private var cursor: [String: Int] = [:]
    private var tails: [String: Double] = [:]
    private var silence: AVAudioPlayer?

    func preload(_ asset: String?) {
        guard let asset = asset, pools[asset] == nil else { return }
        let key = FlutterDartProject.lookupKey(forAsset: asset)
        guard let url = Bundle.main.url(forResource: key, withExtension: nil) else {
            NSLog("[Cues] missing asset \(asset)")
            return
        }
        var voices: [AVAudioPlayer] = []
        for _ in 0..<3 {
            if let p = try? AVAudioPlayer(contentsOf: url) {
                p.prepareToPlay()
                voices.append(p)
            }
        }
        if voices.isEmpty { return }
        pools[asset] = voices
        tails[asset] = voices[0].duration * 1000
    }

    func play(_ asset: String?, volume: Double) {
        guard let asset = asset, let voices = pools[asset], !voices.isEmpty else { return }
        let i = (cursor[asset] ?? 0) % voices.count
        cursor[asset] = i + 1
        let p = voices[i]
        p.volume = Float(min(max(volume, 0), 1))
        p.currentTime = 0
        p.play()
    }

    func tailMs(_ asset: String?) -> Double { asset.flatMap { tails[$0] } ?? 0 }

    private var pausedByUs: [AVAudioPlayer] = []

    func pauseAll() {
        for voices in pools.values {
            for p in voices where p.isPlaying { p.pause(); pausedByUs.append(p) }
        }
    }

    func resumeAll() {
        for p in pausedByUs { p.play() }
        pausedByUs.removeAll()
    }

    func stopAll() {
        for voices in pools.values { for p in voices { p.stop() } }
        pausedByUs.removeAll()
        stopKeepAlive()
    }

    /// A looping silent clip keeps the app running in the background while
    /// nothing else is playing (the countdown, the extension, the last bell).
    func startKeepAlive() {
        if silence?.isPlaying == true { return }
        if silence == nil {
            silence = try? AVAudioPlayer(data: CueSoundBank.silentWav(seconds: 1), fileTypeHint: AVFileType.wav.rawValue)
            silence?.numberOfLoops = -1
            silence?.prepareToPlay()
        }
        silence?.play()
    }

    func stopKeepAlive() { silence?.stop() }

    static func silentWav(seconds: Int) -> Data {
        let rate = 8000
        let dataBytes = rate * 2 * seconds
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(36 + dataBytes)
        d.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(dataBytes)
        d.append(Data(count: dataBytes))
        return d
    }
}

// MARK: - Scheduler

final class CueScheduler {
    enum Phase: String { case idle, countdown, playing, extending = "extension", ended }

    /// Called on the main queue; the channel turns them into Dart calls.
    var onCountdownFinished: (() -> Void)?
    var onSessionEnded: ((_ extensionFinished: Bool, _ tailMs: Double) -> Void)?

    private(set) var config: CueConfig?
    private(set) var phase: Phase = .idle
    private var bank = CueSoundBank()
    private var timer: DispatchSourceTimer?
    private var interludeWork: DispatchWorkItem?
    private var interludeReady: (() -> Void)?
    private var interludeHolding = false
    private var interludeGeneration = 0
    // With autoplay the interlude starts at the session end, before Dart has
    // resolved the next session: when it ends (nil: none), and when the end
    // bell stops ringing.
    private var interludeEndsAtMs: Double?
    private var tailEndsAtMs = 0.0

    /// An autoplay interlude began at the session end and is still waiting.
    var holdsInterlude: Bool { interludeEndsAtMs != nil }

    // Countdown and extension run on the monotonic clock. nil anchor means held.
    private var holdRemainingMs = 0.0
    private var holdAnchorMs: Double?

    // Session clock: sessionAnchorMs at anchorUptimeMs, running 1:1 while playing.
    private var started = false
    private var playing = false
    private var speed = 1.0
    private var sessionAnchorMs = 0.0
    private var anchorUptimeMs = 0.0
    private var lastPositionMs = 0.0
    private var durationMs = 0.0
    private var endless = false
    private var itemsAfterCurrent = 0
    private var extensionStartSessionMs = 0.0

    private var intervalAtMs = Double.greatestFiniteMagnitude
    private var beatAtMs = Double.greatestFiniteMagnitude
    private var halfway = HalfwayBell()

    private static func uptimeMs() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }

    // MARK: lifecycle

    func configure(_ cfg: CueConfig) {
        let live = phase == .playing || phase == .countdown || phase == .extending
        if !live { cancelInterlude(); bank.stopKeepAlive(); cancelTimer(); phase = .idle; started = false }
        if phase == .extending {
            let elapsed = (config?.extensionMs ?? 0) - heldRemaining()
            holdRemainingMs = max(cfg.extensionMs - elapsed, 0)
            if holdAnchorMs != nil { holdAnchorMs = CueScheduler.uptimeMs() }
        }
        config = cfg
        [cfg.startSound, cfg.endSound, cfg.intervalSound, cfg.pulseSound].forEach { bank.preload($0) }
        if live && started {
            armAll(at: sessionNow(), fresh: false)
            rearm()
        }
    }

    /// Starts a session: runs the countdown if there is one. Returns its length in ms (0: play now).
    func begin() -> Double {
        guard let cfg = config else { return 0 }
        cancelTimer()
        started = false
        playing = false
        sessionAnchorMs = 0
        phase = .playing
        if cfg.countdownMs <= 0 { return 0 }
        configureAudioSession()
        phase = .countdown
        holdRemainingMs = cfg.countdownMs
        holdAnchorMs = CueScheduler.uptimeMs()
        bank.startKeepAlive()
        rearm()
        return cfg.countdownMs
    }

    func skipCountdown() { if phase == .countdown { finishCountdown() } }

    func holdInterlude(seconds: Int, ready: @escaping () -> Void) {
        // Only a session that has just ended has an interlude: a late call
        // must not hold the app for a session started since.
        guard phase == .ended else { ready(); return }
        // Already counting since the session end: wait only for what is left.
        let full = Double(min(max(seconds, 0), 30)) * 1000
        var delayMs = full
        if let endsAt = interludeEndsAtMs {
            delayMs = min(max(endsAt - CueScheduler.uptimeMs(), 0), full)
        }
        cancelInterlude()
        configureAudioSession()
        bank.startKeepAlive()
        interludeHolding = true
        let generation = interludeGeneration
        interludeReady = ready
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.interludeWork = nil
            let completion = self.interludeReady
            self.interludeReady = nil
            completion?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                if let self = self, self.phase == .ended, self.interludeGeneration == generation {
                    self.interludeHolding = false
                    self.bank.stopKeepAlive()
                }
            }
        }
        interludeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(delayMs)), execute: work)
    }

    /// Dart will not autoplay after all, or the listener left: drop the
    /// interlude (begun at the session end or by holdInterlude) and let only
    /// the end bell ring out.
    func endInterlude() {
        guard phase == .ended else { return }
        cancelInterlude()
        let left = max(tailEndsAtMs - CueScheduler.uptimeMs(), 0)
        let generation = interludeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(left) + 300)) { [weak self] in
            guard let self = self, self.phase == .ended, self.interludeGeneration == generation else { return }
            self.bank.stopKeepAlive()
        }
    }

    private func cancelInterlude() {
        interludeEndsAtMs = nil
        interludeGeneration += 1
        interludeHolding = false
        interludeWork?.cancel()
        interludeWork = nil
        let completion = interludeReady
        interludeReady = nil
        completion?()
    }

    func stop() {
        cancelInterlude()
        cancelTimer()
        phase = .idle
        started = false
        playing = false
        config = nil
        halfway.disarm()
        holdAnchorMs = nil
        bank.stopAll()
        bank = CueSoundBank()
    }

    /// Pauses or resumes the countdown or extension, which have no player to pause.
    func setHeld(_ held: Bool) {
        guard phase == .countdown || phase == .extending else { return }
        if held, holdAnchorMs != nil {
            holdRemainingMs = heldRemaining()
            holdAnchorMs = nil
            cancelTimer()
            bank.pauseAll()
            // A held session must not keep the app alive with silence.
            bank.stopKeepAlive()
        } else if !held, holdAnchorMs == nil {
            // The session may have been deactivated during a long pause, and
            // an interruption stops the silent player: bring both back.
            configureAudioSession()
            bank.startKeepAlive()
            holdAnchorMs = CueScheduler.uptimeMs()
            bank.resumeAll()
            rearm()
        }
    }

    // MARK: queries

    private func heldRemaining() -> Double {
        guard let anchor = holdAnchorMs else { return max(holdRemainingMs, 0) }
        return max(holdRemainingMs - (CueScheduler.uptimeMs() - anchor), 0)
    }

    var countdownRemainingMs: Double { phase == .countdown ? heldRemaining() : 0 }
    var extensionRemainingMs: Double { phase == .extending ? heldRemaining() : 0 }

    func state() -> [String: Any] {
        [
            "phase": phase.rawValue,
            "countdownRemainingMs": Int(countdownRemainingMs),
            "extensionRemainingMs": Int(extensionRemainingMs),
            "sessionMs": Int(sessionNow()),
            "paused": (phase == .countdown || phase == .extending) && holdAnchorMs == nil,
            "endTailMs": Int(bank.tailMs(config?.endSound)),
        ]
    }

    // MARK: transport from just_audio

    /// The voice's state, reported whenever it changes (play, pause, buffering,
    /// seek, speed). `playing` means audibly advancing, not merely requested.
    func transport(positionMs: Double, durationMs: Double, playing nowPlaying: Bool, speed newSpeed: Double,
                   endless: Bool, itemsAfterCurrent: Int, seeking: Bool = false) {
        if phase == .extending && seeking {
            // The listener moved the voice back during the extension: it is
            // playing again, from the session time reached so far (as Android).
            let t = sessionNow()
            cancelTimer()
            holdAnchorMs = nil
            holdRemainingMs = 0
            bank.stopKeepAlive()
            phase = .playing
            started = true
            playing = false
            sessionAnchorMs = t
            anchorUptimeMs = CueScheduler.uptimeMs()
            lastPositionMs = positionMs
        }
        guard let cfg = config, phase == .playing else { return }
        let now = CueScheduler.uptimeMs()
        self.durationMs = durationMs > 0 ? durationMs : Double(cfg.durationMs)
        self.endless = endless
        self.itemsAfterCurrent = itemsAfterCurrent
        let speedNow = max(newSpeed, 0.05)

        if !started {
            if !nowPlaying { speed = speedNow; return }
            started = true
            speed = speedNow
            playing = true
            configureAudioSession()
            sessionAnchorMs = positionMs / speed
            anchorUptimeMs = now
            lastPositionMs = positionMs
            armAll(at: sessionAnchorMs, fresh: sessionAnchorMs <= 0)
            if CueMath.shouldRingStart(positionMs: positionMs) { bank.play(cfg.startSound, volume: cfg.bellVolume) }
            rearm()
            return
        }

        // Where the clock says the voice should be, against where it says it is.
        let t = sessionNow()
        let predicted = playing ? lastPositionMs + (now - anchorUptimeMs) * speed : lastPositionMs
        let jump = positionMs - predicted
        var tNew = t
        var rearmCues = false
        if seeking || abs(jump) > 750 {
            tNew = t + jump / speedNow
            rearmCues = true
        }
        sessionAnchorMs = tNew
        anchorUptimeMs = now
        lastPositionMs = positionMs
        let wasPlaying = playing
        playing = nowPlaying
        speed = speedNow
        if rearmCues { armAll(at: tNew, fresh: false) }
        if nowPlaying {
            if !wasPlaying { bank.resumeAll() }
            rearm()
        } else {
            cancelTimer()
            bank.pauseAll()
        }
    }

    /// The voice reached its true end.
    func voiceEnded() {
        guard let cfg = config, phase == .playing else {
            if config == nil { onSessionEnded?(false, 0) }
            return
        }
        cancelTimer()
        let t = started ? sessionNow() : 0
        sessionAnchorMs = t
        playing = false
        if cfg.extensionMs > 0 {
            phase = .extending
            extensionStartSessionMs = t
            holdRemainingMs = cfg.extensionMs
            holdAnchorMs = CueScheduler.uptimeMs()
            bank.startKeepAlive()
            rearm()
        } else {
            finishSession(extensionFinished: false)
        }
    }

    // MARK: the loop

    private func sessionNow() -> Double {
        if phase == .extending, let cfg = config {
            return extensionStartSessionMs + (cfg.extensionMs - heldRemaining())
        }
        guard started else { return sessionAnchorMs }
        return playing ? sessionAnchorMs + (CueScheduler.uptimeMs() - anchorUptimeMs) : sessionAnchorMs
    }

    private func cancelTimer() { timer?.cancel(); timer = nil }

    private func schedule(afterMs: Double) {
        cancelTimer()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + .milliseconds(Int(max(afterMs, 1))), leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    private func rearm() {
        switch phase {
        case .countdown:
            guard holdAnchorMs != nil else { return }
            schedule(afterMs: min(heldRemaining(), 250))
        case .extending:
            guard holdAnchorMs != nil else { return }
            let next = min(intervalAtMs, beatAtMs, halfwayDeadlineMs())
            let wait = next == .greatestFiniteMagnitude ? 1000 : next - sessionNow()
            schedule(afterMs: min(max(wait, 1), 1000, heldRemaining()))
        case .playing:
            guard started, playing else { return }
            let next = min(intervalAtMs, beatAtMs, halfwayDeadlineMs())
            if next == .greatestFiniteMagnitude { return }
            schedule(afterMs: min(max(next - sessionNow(), 1), 1000))
        default:
            break
        }
    }

    private func tick() {
        switch phase {
        case .countdown:
            if heldRemaining() <= 0 { finishCountdown() } else { rearm() }
        case .playing:
            guard started, playing else { return }
            fireDue(end: sessionEndMs())
            rearm()
        case .extending:
            guard let cfg = config, holdAnchorMs != nil else { return }
            if heldRemaining() <= 0 { finishSession(extensionFinished: true); return }
            fireDue(end: CueMath.extensionEndMs(extensionStartSessionMs: extensionStartSessionMs, extensionMs: cfg.extensionMs))
            rearm()
        default:
            break
        }
    }

    private func finishCountdown() {
        cancelTimer()
        holdAnchorMs = nil
        holdRemainingMs = 0
        bank.stopKeepAlive()
        phase = .playing
        onCountdownFinished?()
    }

    private func sessionEndMs() -> Double? {
        guard let cfg = config else { return nil }
        let now = CueScheduler.uptimeMs()
        let position = lastPositionMs + (playing ? (now - anchorUptimeMs) * speed : 0)
        guard let remaining = CueMath.remainingSessionMs(
            positionMs: position, durationMs: durationMs, speed: speed,
            itemsAfterCurrent: itemsAfterCurrent, endless: endless, extensionMs: cfg.extensionMs) else { return nil }
        return sessionNow() + remaining
    }

    private func armAll(at t: Double, fresh: Bool) {
        armInterval(at: t)
        armPulse(at: t, fresh: fresh)
        armHalfway(at: t)
    }

    /// Re-armed by every arm (a seek back before the midpoint rings it again when
    /// crossed), but left used up when the session is already at or past it.
    private func armHalfway(at t: Double) {
        halfway.rearm(enabled: config?.hasHalfway == true, sessionMs: t, endMs: currentEndMs())
    }

    /// Session time at which the session ends as it stands now (it moves with
    /// speed); nil when unknown.
    private func currentEndMs() -> Double? {
        if phase == .extending, let cfg = config {
            return CueMath.extensionEndMs(extensionStartSessionMs: extensionStartSessionMs, extensionMs: cfg.extensionMs)
        }
        return sessionEndMs()
    }

    /// When the halfway bell is due, against the session end as it stands now.
    /// greatestFiniteMagnitude when nothing is pending.
    private func halfwayDeadlineMs() -> Double {
        halfway.nextCheckMs(sessionMs: sessionNow(), endMs: currentEndMs())
    }

    private func armInterval(at t: Double) {
        guard let cfg = config, cfg.hasInterval else { intervalAtMs = .greatestFiniteMagnitude; return }
        let i = CueMath.firstIntervalAfter(t, intervalMinutes: cfg.intervalMinutes,
                                           windowMinutes: cfg.randomWindowMinutes, seed: cfg.randomSeed)
        intervalAtMs = Double(CueMath.intervalTime(intervalMinutes: cfg.intervalMinutes,
                                                   windowMinutes: cfg.randomWindowMinutes,
                                                   seed: cfg.randomSeed, index: i))
    }

    private func armPulse(at t: Double, fresh: Bool) {
        guard let cfg = config, cfg.hasPulse else { beatAtMs = .greatestFiniteMagnitude; return }
        let n: Int64 = fresh ? 1 : CueMath.firstBeatAfter(t, start: cfg.pulseBpm, end: cfg.pulseEndBpm, rampMinutes: cfg.pulseRampMinutes)
        beatAtMs = CueMath.beatTime(n, start: cfg.pulseBpm, end: cfg.pulseEndBpm, rampMinutes: cfg.pulseRampMinutes)
    }

    /// Rings what is due. A late cue, or one past the end, is consumed silently.
    private func fireDue(end: Double?) {
        guard let cfg = config else { return }
        let t = sessionNow()
        if t >= intervalAtMs {
            if t - intervalAtMs <= CueMath.intervalLateToleranceMs && CueMath.insideSession(intervalAtMs, end: end) {
                bank.play(cfg.intervalSound, volume: cfg.bellVolume)
            }
            armInterval(at: t)
        }
        if t >= beatAtMs {
            if t - beatAtMs <= CueMath.pulseLateToleranceMs && CueMath.insideSession(beatAtMs, end: end) {
                bank.play(cfg.pulseSound, volume: cfg.pulseVolume)
            }
            armPulse(at: t, fresh: false)
        }
        if halfway.fire(sessionMs: t, endMs: end) {
            bank.play(cfg.intervalSound, volume: cfg.bellVolume)
        }
    }

    private func finishSession(extensionFinished: Bool) {
        cancelTimer()
        holdAnchorMs = nil
        holdRemainingMs = 0
        phase = .ended
        let tail = bank.tailMs(config?.endSound)
        tailEndsAtMs = CueScheduler.uptimeMs() + tail
        if let cfg = config, cfg.endSound != nil {
            configureAudioSession()
            bank.play(cfg.endSound, volume: cfg.bellVolume)
        }
        if let cfg = config, cfg.autoplay, !cfg.isTimer {
            // The interlude starts now, so a locked phone is not suspended
            // while Dart resolves the next session. Bounded like holdInterlude.
            interludeEndsAtMs = CueScheduler.uptimeMs() + cfg.interludeMs
            interludeHolding = true
            configureAudioSession()
            bank.startKeepAlive()
            let generation = interludeGeneration
            let holdMs = max(tail + 300, cfg.interludeMs + 30_000)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(holdMs))) { [weak self] in
                guard let self = self, self.phase == .ended, self.interludeGeneration == generation else { return }
                self.interludeEndsAtMs = nil
                self.interludeHolding = false
                self.bank.stopKeepAlive()
            }
        } else if tail > 0 {
            bank.startKeepAlive()
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(tail) + 300)) { [weak self] in
                guard let self = self, self.phase == .ended, !self.interludeHolding else { return }
                self.bank.stopKeepAlive()
            }
        } else {
            bank.stopKeepAlive()
        }
        onSessionEnded?(extensionFinished, tail)
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback { try? session.setCategory(.playback, mode: .default, options: []) }
        try? session.setActive(true)
    }
}

// MARK: - Channel

/// `meditejo/cues` on iOS. Same methods as Android, plus the ones just_audio
/// needs: `begin` (run the countdown), `transport` (report the voice) and
/// `voiceEnded`. Calls back into Dart with `countdownFinished` and `sessionEnded`.
final class CueChannel {
    static let name = "meditejo/cues"
    static let listeningPrefix = "meditejo.cue.listening."

    private let channel: FlutterMethodChannel
    private let scheduler = CueScheduler()
    private let listening = ListeningTracker()
    private var listeningCompleted = false
    private var listeningKey: String?
    private var lastListeningSaveMs = 0.0
    private var lastListeningReportMs: Double?

    private func persistListening(force: Bool = false) {
        guard let key = listeningKey else { return }
        let now = ProcessInfo.processInfo.systemUptime * 1000
        if !force && !listeningCompleted && now - lastListeningSaveMs < 5000 { return }
        lastListeningSaveMs = now
        if listeningCompleted { UserDefaults.standard.removeObject(forKey: key) }
        else {
            let receipt: [String: Any] = ["at": Date().timeIntervalSince1970, "ranges": listening.snapshot()]
            UserDefaults.standard.set(receipt, forKey: key)
        }
    }

    /// Drops receipts of tracks left unfinished long ago (or beyond the most
    /// recent ones), so they cannot pile up for ever.
    private func pruneListening() {
        let defaults = UserDefaults.standard
        var savedAt: [String: Double] = [:]
        var unstamped: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() {
            guard key.hasPrefix(CueChannel.listeningPrefix), key != listeningKey else { continue }
            let receipt = value as? [String: Any]
            let at = (receipt?["at"] as? NSNumber)?.doubleValue ?? 0
            savedAt[key] = at
            if at <= 0 { unstamped[key] = value }
        }
        let now = Date().timeIntervalSince1970
        let stale = ListeningTracker.staleReceipts(
            savedAt, now: now,
            maxAgeSeconds: ListeningTracker.receiptMaxAgeSeconds, maxCount: ListeningTracker.receiptMaxCount)
        for key in stale { defaults.removeObject(forKey: key) }
        // A receipt saved before save times were kept is stamped now, so it is
        // kept and can still age out.
        for (key, value) in unstamped where !stale.contains(key) {
            var receipt = value as? [String: Any] ?? ["ranges": value]
            receipt["at"] = now
            defaults.set(receipt, forKey: key)
        }
    }

    private func restoreListening(_ args: [String: Any]) {
        persistListening(force: true)
        let parts = [args["trackId"] as? String ?? "", args["fileId"] as? String ?? ""]
        let data = try? JSONSerialization.data(withJSONObject: parts)
        listeningKey = CueChannel.listeningPrefix + (data.flatMap { String(data: $0, encoding: .utf8) } ?? "")
        listeningCompleted = false
        lastListeningReportMs = nil
        // ["at": savedAt, "ranges": [[start, end], ...]]; a bare array is read too.
        var stored = UserDefaults.standard.object(forKey: listeningKey!)
        if let receipt = stored as? [String: Any] { stored = receipt["ranges"] }
        let saved = stored as? [[NSNumber]] ?? []
        listening.restore(saved.map { $0.map { $0.int64Value } })
        lastListeningSaveMs = ProcessInfo.processInfo.systemUptime * 1000
        pruneListening()
    }

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: CueChannel.name, binaryMessenger: messenger)
        scheduler.onCountdownFinished = { [weak self] in
            self?.channel.invokeMethod("countdownFinished", arguments: nil)
        }
        scheduler.onSessionEnded = { [weak self] extensionFinished, tailMs in
            self?.channel.invokeMethod("sessionEnded", arguments: [
                "extensionFinished": extensionFinished,
                "tailMs": Int(tailMs),
                "interlude": self?.scheduler.holdsInterlude ?? false,
            ])
        }
        channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    }

    private func num(_ args: [String: Any], _ key: String) -> Double { (args[key] as? NSNumber)?.doubleValue ?? 0 }

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "configure":
            // A Customize edit after the session ended changes nothing now: it
            // must not cut the autoplay interlude or its hold short.
            if (args["update"] as? Bool) == true && scheduler.phase == .ended {
                result(nil)
                return
            }
            scheduler.configure(CueConfig(map: args))
            result(nil)
        case "begin":
            result(Int(scheduler.begin()))
        case "skipCountdown":
            scheduler.skipCountdown()
            result(nil)
        case "holdInterlude":
            scheduler.holdInterlude(seconds: (args["seconds"] as? NSNumber)?.intValue ?? 0) { result(nil) }
        case "endInterlude":
            scheduler.endInterlude()
            result(nil)
        case "setHeld":
            scheduler.setHeld((args["held"] as? Bool) ?? false)
            result(nil)
        case "stop":
            persistListening(force: true)
            scheduler.stop()
            result(nil)
        case "state":
            var s = scheduler.state()
            s["heardMs"] = Int(listening.heardMs)
            s["completionSent"] = listeningCompleted
            result(s)
        case "countdownRemainingMs":
            result(Int(scheduler.countdownRemainingMs))
        case "transport":
            scheduler.transport(
                positionMs: num(args, "positionMs"), durationMs: num(args, "durationMs"),
                playing: (args["playing"] as? Bool) ?? false,
                speed: (args["speed"] as? NSNumber)?.doubleValue ?? 1,
                endless: (args["endless"] as? Bool) ?? false,
                itemsAfterCurrent: (args["itemsAfterCurrent"] as? NSNumber)?.intValue ?? 0,
                seeking: (args["seek"] as? Bool) ?? false)
            result(nil)
        case "voiceEnded":
            scheduler.voiceEnded()
            result(nil)
        case "sampleListening":
            // positionMs, durationMs, playing; Dart reports each change and about once a second.
            let position = Int64(num(args, "positionMs"))
            let duration = Int64(num(args, "durationMs"))
            let now = ProcessInfo.processInfo.systemUptime * 1000
            let elapsed = lastListeningReportMs.map { now - $0 }
            lastListeningReportMs = now
            if (args["seek"] as? Bool) == true {
                listening.rebase(position)
            } else {
                // Include the final rendered stretch when a pause/EOF report arrives.
                listening.sample(position, playing: true, realElapsedMs: elapsed,
                                 speed: (args["speed"] as? NSNumber)?.doubleValue ?? 1)
            }
            let playing = (args["playing"] as? Bool) ?? false
            if !playing { listening.markNotPlaying() }
            if !listeningCompleted && !(scheduler.config?.isTimer ?? false) && listening.completed(durationMs: duration) {
                listeningCompleted = true
            }
            persistListening(force: !playing)
            result(listeningCompleted)
        case "endPass":
            // A pass of a looped recording just finished, after its session was
            // earned. A repeat counts only when 90% of that pass was heard, so
            // the record starts fresh for the next one.
            let duration = Int64(num(args, "durationMs"))
            listening.sample(duration, playing: true)
            let heardPass = listening.completed(durationMs: duration)
            listening.startPass()
            result(heardPass)
        case "resetListening":
            restoreListening(args)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
