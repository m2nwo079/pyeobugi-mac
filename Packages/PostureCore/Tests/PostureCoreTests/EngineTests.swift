import Foundation
import Testing
import PostureCore

// All times are in seconds

private let baseline = Baseline(pitch: 0, size: 0.3)
private let good = FaceSample(pitch: 0, size: 0.3)
private let bad = FaceSample(pitch: 20, size: 0.3)

private func run(
    _ samples: [Sample],
    from start: EngineState = .initial,
    baseline: Baseline? = baseline
) -> StepResult {
    samples.reduce((state: start, transitions: [Transition]())) { acc, sample in
        let step = stepEngine(acc.state, sample: sample, baseline: baseline)
        return (step.state, acc.transitions + step.transitions)
    }
}

private func series(_ from: TimeInterval, _ to: TimeInterval, _ step: TimeInterval, _ face: FaceSample?) -> [Sample] {
    (0...Int(((to - from) / step).rounded(.down))).map { Sample(at: from + Double($0) * step, face: face) }
}

private func isClose(_ a: Double?, _ b: Double?, _ tolerance: Double = 1e-12) -> Bool {
    guard let a, let b else { return false }
    return abs(a - b) < tolerance
}

private func badEnters(_ transitions: [Transition]) -> [Transition] {
    transitions.filter { if case .badEnter = $0 { true } else { false } }
}

@Suite struct EnginePresenceTests {
    @Test func reportsPresenceOnFirstFace() {
        #expect(run([Sample(at: 0, face: good)]).transitions == [.presenceFound(at: 0)])
    }

    @Test func ignoresShortDetectionMiss() {
        let result = run(series(0, 2, 1, good) + series(3, 4, 1, nil))
        #expect(result.transitions == [.presenceFound(at: 0)])
    }

    @Test func reportsAbsenceDatedToLastSeenFace() {
        let result = run(series(0, 2, 1, good) + series(3, 5, 1, nil))
        #expect(result.transitions.last == .presenceLost(at: 2))
        #expect(result.state.present == false)
    }

    @Test func closesBadPostureBeforeReportingAbsence() {
        let badRun = run(series(0, 4, 0.25, bad))
        let result = run(series(5, 8, 1, nil), from: badRun.state)
        #expect(result.transitions == [.badExit(at: 4, reason: .faceLost), .presenceLost(at: 4)])
    }
}

@Suite struct EnginePostureTests {
    @Test func doesNotCountShortBadSpike() {
        let samples = series(0, 2, 1, good) + series(2.25, 4, 0.25, bad) + series(4.25, 8, 0.25, good)
        #expect(badEnters(run(samples).transitions) == [])
    }

    @Test func entersOnceBackdatedWithWorstSeverity() {
        let result = run(series(0, 2, 1, good) + series(3, 8, 0.25, bad))
        #expect(badEnters(result.transitions) == [.badEnter(at: 3, severity: .severe)])
    }

    @Test func staysBadBetweenExitAndEntryThresholds() {
        let between = FaceSample(pitch: 6, size: 0.3)
        let betweenScore = postureScore(pitch: between.pitch, size: between.size, baseline: baseline)
        #expect(betweenScore >= badExitScore)
        #expect(betweenScore < badEnterScore)
        let badRun = run(series(0, 4, 0.25, bad))
        #expect(run(series(4.25, 12, 0.25, between), from: badRun.state).transitions == [])
    }

    @Test func exitsAfterGoodHoldBackdatedToRecovery() {
        let badRun = run(series(0, 4, 0.25, bad))
        let result = run(series(5, 9, 0.25, good), from: badRun.state)
        #expect(result.transitions == [.badExit(at: 5.25, reason: .recovered)])
        #expect(result.state.bad == false)
    }

    @Test func doesNotTrackBeforeCalibration() {
        let result = run(series(0, 8, 0.25, bad), baseline: nil)
        #expect(result.transitions == [])
        #expect(result.state.present == true)
    }

    @Test func startsTrackingOnFirstSampleAfterCalibration() {
        let uncalibrated = run(series(0, 2, 1, good), baseline: nil)
        let result = run([Sample(at: 3, face: good)], from: uncalibrated.state)
        #expect(result.transitions == [.presenceFound(at: 3)])
    }

    @Test func reportsNoAbsenceForUntrackedFace() {
        let uncalibrated = run(series(0, 2, 1, good), baseline: nil)
        let result = run(series(3, 6, 1, nil), from: uncalibrated.state, baseline: nil)
        #expect(result.transitions == [])
        #expect(result.state.present == false)
    }

    @Test func closesBadPostureOnReset() {
        let badRun = run(series(0, 4, 0.25, bad))
        #expect(resetPosture(badRun.state, at: 4.1).transitions == [.badExit(at: 4.1, reason: .recalibrated)])
    }
}

@Suite struct NextIntervalTests {
    @Test func samplesFastOnlyWhileChangePending() {
        let idle = run(series(0, 2, 1, good))
        let pending = run([Sample(at: 3, face: bad)], from: idle.state)
        #expect(nextInterval(idle.state, now: 2) == Timing.idleInterval)
        #expect(nextInterval(pending.state, now: 3) == Timing.pendingInterval)
    }

    @Test func slowsDownAfterLongAbsence() {
        let away = run(series(0, 1, 1, good) + series(2, 5, 1, nil))
        #expect(nextInterval(away.state, now: 30) == Timing.idleInterval)
        #expect(nextInterval(away.state, now: 70) == Timing.awayInterval)
    }
}

@Suite struct SmoothingTests {
    @Test func sameStepResponseAtAnyRate() {
        let smooth = { (intervals: [TimeInterval]) in
            intervals.reduce(0.0) { smoothSignal($0, 20, elapsed: $1) }
        }
        let oneHz = smooth([1, 1])
        #expect(isClose(smooth(Array(repeating: 0.25, count: 8)), oneHz))
        #expect(isClose(smooth([0.1, 0.65, 1.25]), oneHz))
        #expect(isClose(oneHz, 20 * (1 - exp(-2))))
    }

    @Test func engineUsesElapsedTimeForPitchAndSize() {
        let initial = run([Sample(at: 0, face: good)]).state
        let face = FaceSample(pitch: 20, size: 0.5)
        let slow = run(series(1, 2, 1, face), from: initial).state
        let fast = run(series(0.25, 2, 0.25, face), from: initial).state
        #expect(isClose(fast.pitch, slow.pitch))
        #expect(isClose(fast.size, slow.size))
    }

    @Test func initializesFreshSignalsAndIgnoresNonPositiveElapsed() {
        #expect(smoothSignal(nil, 20, elapsed: 0) == 20)
        #expect(smoothSignal(10, 20, elapsed: 0) == 10)
        #expect(smoothSignal(10, 20, elapsed: -0.1) == 10)
        let pending = run([Sample(at: 0, face: bad)]).state
        let resumed = run([Sample(at: 10, face: bad)], from: pending).state
        #expect(resumed.pitch == 20)
        #expect(resumed.bad == false)
        #expect(resumed.pendingSince == 10)
    }

    @Test func keepsBadOnsetUntilRecoveryAndClearsFiltersOnReset() {
        let badState = run(series(0, 4, 0.25, bad)).state
        #expect(badState.badSince == 0)
        let reset = resetPosture(badState, at: 4.1).state
        #expect(reset.badSince == nil)
        #expect(reset.pitch == nil)
        #expect(run([Sample(at: 4.25, face: good)], from: reset).state.pitch == 0)
    }
}
