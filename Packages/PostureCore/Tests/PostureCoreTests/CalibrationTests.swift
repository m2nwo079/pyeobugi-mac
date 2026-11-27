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

// Feeds samples every 0.25 s (the calibration rate) and returns the verdict after each one
private func feed(_ run: inout CalibrationRun, from start: Double, count: Int,
                  face: (Int) -> FaceSample? = { _ in FaceSample(pitch: 10, size: 0.3) }) -> [CalibrationVerdict] {
    (0..<count).map { run.add(Sample(at: start + Double($0) * 0.25, face: face($0))) }
}

@Suite struct CalibrationRunTests {
    @Test func completesAfterFiveSecondsOfSteadySamples() {
        var run = CalibrationRun(startedAt: 0)
        #expect(run.evaluate(at: 0).result == .collecting(remainingSeconds: 5))
        let verdicts = feed(&run, from: 0, count: 21)
        #expect(verdicts[19].result == .collecting(remainingSeconds: 1))
        #expect(verdicts[20].result == expectedBaseline)
        #expect(verdicts[20].failure == nil)
    }

    @Test func failsWhenTheHeadMoves() {
        var run = CalibrationRun(startedAt: 0)
        let verdicts = feed(&run, from: 0, count: 8) { $0 == 7 ? FaceSample(pitch: 18, size: 0.3) : FaceSample(pitch: 10, size: 0.3) }
        #expect(verdicts[6].result == .collecting(remainingSeconds: 4))
        #expect(verdicts[7].result == .failed)
        #expect(verdicts[7].failure == .moved)
    }

    @Test func timesOutWhenSamplesStop() {
        var run = CalibrationRun(startedAt: 0)
        _ = feed(&run, from: 0, count: 3)
        // The latest sample is at 0.5 s, so the deadline is 0.5 + 1.6 s
        #expect(run.deadline == 2.1)
        #expect(run.evaluate(at: 2.0).result == .collecting(remainingSeconds: 5))
        #expect(run.evaluate(at: 2.2).result == .failed)
        #expect(run.evaluate(at: 2.2).failure == .timedOut)
    }

    @Test func timesOutWhenNoSampleEverArrives() {
        let run = CalibrationRun(startedAt: 10)
        #expect(run.evaluate(at: 11.5).failure == nil)
        #expect(run.evaluate(at: 11.75).result == .failed)
        #expect(run.evaluate(at: 11.75).failure == .timedOut)
    }
}
