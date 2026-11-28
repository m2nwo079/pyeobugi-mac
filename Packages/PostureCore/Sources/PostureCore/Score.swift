import Foundation

public struct Baseline: Sendable, Equatable {
    public var pitch: Double
    public var size: Double

    public init(pitch: Double, size: Double) {
        self.pitch = pitch
        self.size = size
    }
}

// Declaration order defines the synthesized Comparable ranking
public enum Severity: Sendable, Comparable {
    case mild, moderate, severe
}

private let pitchDeadzone = 1.5
private let pitchWeight = 1.4
private let sizeWeight = 120.0
private let sizeGateStart = 6.0
private let sizeGateSpan = 5.0
private let scoreDeadzone = 4.0
private let moderateMinScore = 10.0
private let severeMinScore = 18.0

public let badEnterScore = 3.0
public let badExitScore = 2.0

// Pitch past the baseline at which the pitch term alone reaches badEnterScore
public let baseEnterPitch = pitchDeadzone + (badEnterScore + scoreDeadzone) / pitchWeight

// Baseline fed to scoring for a sensitivity. Only the pitch moves, so the whole pitch curve
// (entry, recovery, size gate, severity) shifts together; the stored baseline and its size stay as they are
public func tunedBaseline(_ baseline: Baseline, sensitivity: Sensitivity) -> Baseline {
    Baseline(pitch: baseline.pitch + sensitivity.enterPitch - baseEnterPitch, size: baseline.size)
}

public func postureScore(pitch: Double, size: Double, baseline: Baseline) -> Double {
    let dPitch = pitch - baseline.pitch
    let pitchTerm = dPitch > pitchDeadzone ? (dPitch - pitchDeadzone) * pitchWeight : 0
    // Face size also grows when simply leaning toward the screen, so it only counts once the head is pitched down
    let gate = dPitch > sizeGateStart ? min(1, (dPitch - sizeGateStart) / sizeGateSpan) : 0
    let sizeTerm = max(0, (size - baseline.size) * sizeWeight) * gate
    let total = pitchTerm + sizeTerm
    return total < scoreDeadzone ? 0 : total - scoreDeadzone
}

public func severity(of score: Double) -> Severity {
    if score >= severeMinScore { return .severe }
    if score >= moderateMinScore { return .moderate }
    return .mild
}

public func maxSeverity(_ a: Severity?, _ b: Severity) -> Severity {
    a.map { max($0, b) } ?? b
}
