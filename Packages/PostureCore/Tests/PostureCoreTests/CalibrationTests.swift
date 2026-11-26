import Testing
import PostureCore

// Times are in seconds
private func stable() -> [Sample] {
    (0...10).map { Sample(at: Double($0) * 0.5, face: FaceSample(pitch: $0 == 5 ? 12 : 10, size: 0.3)) }
}

private let expectedBaseline = CalibrationResult.complete(Baseline(pitch: 10, size: 0.3))

@Suite struct CalibrationTests {
    @Test func waitsForFullPeriodAndSavesMedian() {
        #expect(evaluateCalibration(Array(stable().prefix(10)), startedAt: 0) == .collecting(remainingSeconds: 1))
        #expect(evaluateCalibration(stable(), startedAt: 0) == expectedBaseline)
    }

    @Test func rejectsHeadMotionAndDistanceChanges() {
        var samples = stable()
        samples[5].face?.pitch = 18
        #expect(evaluateCalibration(samples, startedAt: 0) == .failed)
        samples[5].face = FaceSample(pitch: 10, size: 0.4)
        #expect(evaluateCalibration(samples, startedAt: 0) == .failed)
    }

    @Test func toleratesFewDroppedOrInvalidFramesButRejectsMore() {
        var tolerated = stable()
        tolerated[3].face = nil
        tolerated[7].face?.pitch = .nan
        #expect(evaluateCalibration(tolerated, startedAt: 0) == expectedBaseline)

        var missing = stable()
        for i in [2, 4, 6] { missing[i].face = nil }
        #expect(evaluateCalibration(missing, startedAt: 0) == .failed)

        let twoMisses = stable().prefix(2).map { Sample(at: $0.at, face: nil) }
        #expect(evaluateCalibration(twoMisses, startedAt: 0) == .collecting(remainingSeconds: 5))
    }

    @Test func rejectsInterruptedSampling() {
        #expect(evaluateCalibration([stable()[0], stable()[10]], startedAt: 0) == .failed)
        let lateStart = stable().map { Sample(at: $0.at + 2, face: $0.face) }
        #expect(evaluateCalibration(lateStart, startedAt: 0) == .failed)
    }
}
