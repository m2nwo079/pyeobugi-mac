import Testing
import PostureCore

// Times are in seconds
private let baseline = Baseline(pitch: 0, size: 0.3)

private func run(_ size: Double, until end: Int = 8) -> DistanceState {
    (0...end).reduce(DistanceState.initial) { stepDistance($0, at: Double($1), size: size, baseline: baseline) }
}

@Suite struct DistanceTests {
    @Test func waitsForSustainedChangeInEitherDirection() {
        #expect(run(0.4, until: 7).suggested == false)
        let closer = run(0.4)
        #expect(closer.suggested == true)
        #expect(closer.direction == .closer)
        let farther = run(0.2)
        #expect(farther.suggested == true)
        #expect(farther.direction == .farther)
        #expect(run(0.33).suggested == false)
    }

    @Test func hysteresisKeepsSuggestionStableAndClearsNearBaseline() {
        let nearThreshold = stepDistance(run(0.4), at: 9, size: 0.36, baseline: baseline)
        #expect(nearThreshold.suggested == true)
        #expect(stepDistance(nearThreshold, at: 10, size: 0.32, baseline: baseline).suggested == false)
    }

    @Test func doesNotAccumulateMissingTimeOrOppositeChanges() {
        let pending = run(0.4, until: 7)
        #expect(stepDistance(pending, at: 8, size: nil, baseline: baseline) == .initial)
        #expect(stepDistance(pending, at: 10, size: 0.4, baseline: baseline).suggested == false)
        #expect(stepDistance(pending, at: 8, size: 0.2, baseline: baseline).suggested == false)
    }

    @Test func clearsAfterRecalibration() {
        let changed = run(0.4)
        #expect(stepDistance(changed, at: 9, size: 0.4, baseline: Baseline(pitch: 0, size: 0.4)).suggested == false)
        #expect(stepDistance(changed, at: 9, size: 0.4, baseline: nil) == .initial)
    }
}
