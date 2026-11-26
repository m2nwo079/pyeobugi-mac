import Foundation

public enum FeedbackPhase: Sendable, Equatable {
    case uncalibrated, unavailable, good, pendingBad, bad, recovering
}

public struct FeedbackExit: Sendable, Equatable {
    public var id: Int
    public var reason: ExitReason
    public var occurredAt: TimeInterval
    public var detectedAt: TimeInterval

    public init(id: Int, reason: ExitReason, occurredAt: TimeInterval, detectedAt: TimeInterval) {
        self.id = id
        self.reason = reason
        self.occurredAt = occurredAt
        self.detectedAt = detectedAt
    }
}

public struct PostureFeedback: Sendable, Equatable {
    public var phase: FeedbackPhase = .unavailable
    public var score: Double?
    public var severity: Severity?
    public var badSince: TimeInterval?
    public var badDuration: TimeInterval = 0
    // Survives session resets so each exit id is consumed exactly once
    public var exitSequence = 0
    public var lastExit: FeedbackExit?

    public init() {}

    public static let initial = PostureFeedback()
}

public func updateFeedback(
    _ previous: PostureFeedback,
    engine: EngineState,
    at: TimeInterval,
    calibrated: Bool,
    transitions: [Transition]
) -> PostureFeedback {
    var next = PostureFeedback()
    next.exitSequence = previous.exitSequence
    next.lastExit = previous.lastExit
    for case let .badExit(occurredAt, reason) in transitions {
        next.exitSequence += 1
        next.lastExit = FeedbackExit(id: next.exitSequence, reason: reason, occurredAt: occurredAt, detectedAt: at)
    }

    // A single dropped frame keeps the last state; the engine's own loss timeout decides when feedback stops
    guard engine.present else { return next }
    guard calibrated else {
        next.phase = .uncalibrated
        return next
    }

    let pending = engine.pendingSince != nil
    next.score = engine.score
    guard engine.bad else {
        next.phase = pending ? .pendingBad : .good
        return next
    }
    next.phase = pending ? .recovering : .bad
    next.severity = severity(of: engine.score)
    next.badSince = engine.badSince
    next.badDuration = engine.badSince.map { max(0, at - $0) } ?? 0
    return next
}
