import Foundation

private let calibrationDuration: TimeInterval = 5
private let calibrationMaxGap: TimeInterval = 1.6
private let calibrationMinSamples = 6
private let calibrationMaxMissing = 2
private let calibrationMaxPitchRange = 6.0
private let calibrationMaxSizeRange = 0.12

public enum CalibrationResult: Sendable, Equatable {
    case collecting(remainingSeconds: Int)
    case failed
    case complete(Baseline)
}

// Why an attempt failed; used for diagnostics only
public enum CalibrationFailure: String, Sendable {
    // Two samples, or the start and the first sample, are further apart than the max gap
    case sampleGap
    case tooManyMissing
    // Pitch or face size moved beyond the allowed range
    case moved
    case tooFewFaces
    // No sample arrived within the max gap before the time of evaluation
    case timedOut
}

public typealias CalibrationVerdict = (result: CalibrationResult, failure: CalibrationFailure?)

private func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
}

private func usableFace(_ sample: Sample) -> FaceSample? {
    guard let face = sample.face, face.pitch.isFinite, face.size.isFinite, face.size > 0 else { return nil }
    return face
}

private func judgeCalibration(_ samples: [Sample], startedAt: TimeInterval) -> CalibrationVerdict {
    if zip(samples, samples.dropFirst()).contains(where: { $1.at - $0.at > calibrationMaxGap }) {
        return (.failed, .sampleGap)
    }
    let faces = samples.compactMap(usableFace)
    // Face detectors drop the odd frame even when the user sits still, so a few misses must not fail the attempt
    if samples.count - faces.count > calibrationMaxMissing { return (.failed, .tooManyMissing) }
    guard let first = samples.first, let last = samples.last else {
        return (.collecting(remainingSeconds: Int(calibrationDuration.rounded(.up))), nil)
    }
    if first.at - startedAt > calibrationMaxGap { return (.failed, .sampleGap) }

    let elapsed = last.at - startedAt
    let collecting: CalibrationVerdict = (.collecting(remainingSeconds: Int((calibrationDuration - elapsed).rounded(.up))), nil)
    if faces.isEmpty { return collecting }

    let pitches = faces.map(\.pitch)
    let sizes = faces.map(\.size)
    let size = median(sizes)
    if pitches.max()! - pitches.min()! > calibrationMaxPitchRange
        || (sizes.max()! - sizes.min()!) / size > calibrationMaxSizeRange {
        return (.failed, .moved)
    }
    if elapsed < calibrationDuration { return collecting }
    if faces.count < calibrationMinSamples { return (.failed, .tooFewFaces) }
    return (.complete(Baseline(pitch: median(pitches), size: size)), nil)
}

public func evaluateCalibration(_ samples: [Sample], startedAt: TimeInterval) -> CalibrationResult {
    judgeCalibration(samples, startedAt: startedAt).result
}

// One calibration attempt. Samples are judged as they arrive, and the app also asks for a verdict
// at the deadline so the attempt ends even when samples stop coming.
public struct CalibrationRun: Sendable {
    public let startedAt: TimeInterval
    public private(set) var samples: [Sample] = []

    public init(startedAt: TimeInterval) {
        self.startedAt = startedAt
    }

    // The next sample must arrive by this time, measured from the latest sample or the start
    public var deadline: TimeInterval {
        (samples.last?.at ?? startedAt) + calibrationMaxGap
    }

    public mutating func add(_ sample: Sample) -> CalibrationVerdict {
        samples.append(sample)
        return judgeCalibration(samples, startedAt: startedAt)
    }

    public func evaluate(at now: TimeInterval) -> CalibrationVerdict {
        if now > deadline { return (.failed, .timedOut) }
        return judgeCalibration(samples, startedAt: startedAt)
    }
}
