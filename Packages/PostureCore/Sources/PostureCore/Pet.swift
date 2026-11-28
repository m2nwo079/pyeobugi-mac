import Foundation

// What the pet shows. Priority: away > bad > good
public enum PetMood: Sendable, Equatable {
    case away, bad, good
}

// How far the head must drop before posture counts as bad, and how quickly on-screen correction kicks in.
// Raw values are stable for persistence
public enum Sensitivity: Int, Sendable, Equatable, CaseIterable {
    case loose = 0
    case normal = 1
    case strict = 2

    public static let `default`: Sensitivity = .normal

    // Pitch past the stored baseline at which the score reaches the entry line (see tunedBaseline)
    public var enterPitch: Double {
        switch self {
        case .loose: 15
        case .normal: 10
        case .strict: baseEnterPitch
        }
    }

    // Wait after the score crosses the entry line before the neck starts growing.
    // Only the on-screen feedback is brought forward; bad-posture confirmation stays at Timing.enterAfter
    public var neckStartDelay: TimeInterval {
        switch self {
        case .loose: Timing.enterAfter
        case .normal: Timing.enterAfter / 2
        case .strict: 0
        }
    }
}

public enum PetTiming {
    // While bad, the neck grows by one drawing length every interval
    public static let neckGrowInterval: TimeInterval = 0.9
    // Past roughly a screen width of wrapping, extra length is no longer visible
    public static let neckMax: Double = 24
}

// No face or no calibration means the pet just wanders.
// pendingBad is not bad yet; recovering already starts shrinking the neck
public func petMood(from phase: FeedbackPhase?) -> PetMood {
    switch phase {
    case nil, .unavailable, .uncalibrated: .away
    case .bad: .bad
    case .good, .pendingBad, .recovering: .good
    }
}

// Neck length: 0 is resting, 1 is one drawing length, above 1 wraps into the next column.
// candidateSince is when the score crossed the entry line. Computed from the current time so it
// grows every frame instead of stepping once per detection. Engine badSince is not used because it is
// backdated to the candidate time, which would make the neck jump on confirmation
public func neckLength(
    candidateSince: TimeInterval?,
    sensitivity: Sensitivity = .default,
    at now: TimeInterval
) -> Double {
    guard let candidateSince else { return 0 }
    let startAt = candidateSince + sensitivity.neckStartDelay
    guard now > startAt else { return 0 }
    return min(PetTiming.neckMax, (now - startAt) / PetTiming.neckGrowInterval)
}
