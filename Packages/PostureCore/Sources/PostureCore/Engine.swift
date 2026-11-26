import Foundation

public struct FaceSample: Sendable, Equatable {
    public var pitch: Double
    public var size: Double

    public init(pitch: Double, size: Double) {
        self.pitch = pitch
        self.size = size
    }
}

public struct Sample: Sendable, Equatable {
    public var at: TimeInterval
    public var face: FaceSample?

    public init(at: TimeInterval, face: FaceSample?) {
        self.at = at
        self.face = face
    }
}

public enum ExitReason: Sendable, Equatable {
    case recovered, faceLost, recalibrated
}

public enum Transition: Sendable, Equatable {
    case presenceFound(at: TimeInterval)
    case presenceLost(at: TimeInterval)
    case badEnter(at: TimeInterval, severity: Severity)
    case badExit(at: TimeInterval, reason: ExitReason)
}

public struct EngineState: Sendable, Equatable {
    public var present = false
    public var tracking = false
    public var lastSeenAt: TimeInterval?
    public var lostAt: TimeInterval?
    public var bad = false
    public var pendingSince: TimeInterval?
    public var pendingSeverity: Severity?
    public var badSince: TimeInterval?
    public var pitch: Double?
    public var size: Double?
    public var score = 0.0

    public init() {}

    public static let initial = EngineState()
}

public typealias StepResult = (state: EngineState, transitions: [Transition])

// All durations are in seconds
public enum Timing {
    public static let lostAfter: TimeInterval = 3
    public static let enterAfter: TimeInterval = 3
    public static let exitAfter: TimeInterval = 2
    public static let idleInterval: TimeInterval = 1
    public static let pendingInterval: TimeInterval = 0.25
    public static let awayInterval: TimeInterval = 3
    public static let awaySlowdownAfter: TimeInterval = 60
    public static let smoothingTime: TimeInterval = 1
}

public func smoothSignal(_ previous: Double?, _ value: Double, elapsed: TimeInterval) -> Double {
    guard let previous else { return value }
    let alpha = -expm1(-max(0, elapsed) / Timing.smoothingTime)
    return previous + alpha * (value - previous)
}

private func stepMissing(_ state: EngineState, at: TimeInterval) -> StepResult {
    guard state.present, let lastSeenAt = state.lastSeenAt, at - lastSeenAt >= Timing.lostAfter else {
        return (state, [])
    }
    // Absence is dated from the last confirmed face so undetected time is excluded from usage
    var transitions: [Transition] = state.bad ? [.badExit(at: lastSeenAt, reason: .faceLost)] : []
    if state.tracking { transitions.append(.presenceLost(at: lastSeenAt)) }
    var next = EngineState.initial
    next.lostAt = lastSeenAt
    return (next, transitions)
}

private func stepPosture(_ state: EngineState, at: TimeInterval, score: Double) -> StepResult {
    var next = state
    let wantsBad = state.bad ? score >= badExitScore : score >= badEnterScore
    if wantsBad == state.bad {
        next.pendingSince = nil
        next.pendingSeverity = nil
        return (next, [])
    }

    let pendingSince = state.pendingSince ?? at
    let pendingSeverity = wantsBad ? maxSeverity(state.pendingSeverity, severity(of: score)) : nil
    let hold = wantsBad ? Timing.enterAfter : Timing.exitAfter
    if at - pendingSince < hold {
        next.pendingSince = pendingSince
        next.pendingSeverity = pendingSeverity
        return (next, [])
    }

    // Transitions are backdated to when the change started, so bad-posture time is not cut short by the hold
    let transition: Transition = wantsBad
        ? .badEnter(at: pendingSince, severity: pendingSeverity ?? severity(of: score))
        : .badExit(at: pendingSince, reason: .recovered)
    next.bad = wantsBad
    next.badSince = wantsBad ? pendingSince : nil
    next.pendingSince = nil
    next.pendingSeverity = nil
    return (next, [transition])
}

public func stepEngine(_ state: EngineState, sample: Sample, baseline: Baseline?) -> StepResult {
    guard let face = sample.face else { return stepMissing(state, at: sample.at) }

    let elapsed = state.lastSeenAt.map { sample.at - $0 } ?? 0
    let stale = elapsed >= Timing.lostAfter
    var seen = state
    seen.present = true
    seen.lastSeenAt = sample.at
    seen.lostAt = nil
    seen.pitch = smoothSignal(stale ? nil : state.pitch, face.pitch, elapsed: elapsed)
    seen.size = smoothSignal(stale ? nil : state.size, face.size, elapsed: elapsed)
    if stale {
        seen.pendingSince = nil
        seen.pendingSeverity = nil
    }

    guard let baseline, let pitch = seen.pitch, let size = seen.size else {
        seen.score = 0
        return (seen, [])
    }

    // Usage is only tracked once a baseline exists; uncalibrated time would count as perfect posture
    let found: [Transition] = state.tracking ? [] : [.presenceFound(at: sample.at)]
    let score = postureScore(pitch: pitch, size: size, baseline: baseline)
    seen.tracking = true
    seen.score = score
    let posture = stepPosture(seen, at: sample.at, score: score)
    return (posture.state, found + posture.transitions)
}

public func resetPosture(_ state: EngineState, at: TimeInterval) -> StepResult {
    var next = state
    next.bad = false
    next.badSince = nil
    next.pendingSince = nil
    next.pendingSeverity = nil
    next.pitch = nil
    next.size = nil
    next.score = 0
    return (next, state.bad ? [.badExit(at: at, reason: .recalibrated)] : [])
}

public func nextInterval(_ state: EngineState, now: TimeInterval) -> TimeInterval {
    if state.pendingSince != nil { return Timing.pendingInterval }
    if !state.present, let lostAt = state.lostAt, now - lostAt >= Timing.awaySlowdownAfter {
        return Timing.awayInterval
    }
    return Timing.idleInterval
}
