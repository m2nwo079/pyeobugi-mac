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

private func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
}

private func usableFace(_ sample: Sample) -> FaceSample? {
    guard let face = sample.face, face.pitch.isFinite, face.size.isFinite, face.size > 0 else { return nil }
    return face
}

public func evaluateCalibration(_ samples: [Sample], startedAt: TimeInterval) -> CalibrationResult {
    if zip(samples, samples.dropFirst()).contains(where: { $1.at - $0.at > calibrationMaxGap }) { return .failed }
    let faces = samples.compactMap(usableFace)
    // Face detectors drop the odd frame even when the user sits still, so a few misses must not fail the attempt
    if samples.count - faces.count > calibrationMaxMissing { return .failed }
    guard let first = samples.first, let last = samples.last else {
        return .collecting(remainingSeconds: Int(calibrationDuration.rounded(.up)))
    }
    if first.at - startedAt > calibrationMaxGap { return .failed }

    let elapsed = last.at - startedAt
    let collecting = CalibrationResult.collecting(remainingSeconds: Int((calibrationDuration - elapsed).rounded(.up)))
    if faces.isEmpty { return collecting }

    let pitches = faces.map(\.pitch)
    let sizes = faces.map(\.size)
    let size = median(sizes)
    if pitches.max()! - pitches.min()! > calibrationMaxPitchRange
        || (sizes.max()! - sizes.min()!) / size > calibrationMaxSizeRange {
        return .failed
    }
    if elapsed < calibrationDuration { return collecting }
    if faces.count < calibrationMinSamples { return .failed }
    return .complete(Baseline(pitch: median(pitches), size: size))
}
