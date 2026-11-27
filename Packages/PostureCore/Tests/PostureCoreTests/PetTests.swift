import Foundation
import Testing
import PostureCore

// All times are in seconds

private let t0: TimeInterval = 1000
private let grow = PetTiming.neckGrowInterval

@Suite struct NeckLengthTests {
    @Test func zeroWithoutCandidate() {
        #expect(neckLength(candidateSince: nil, sensitivity: .normal, at: t0) == 0)
    }

    @Test func strictGrowsFromCandidateTime() {
        #expect(neckLength(candidateSince: t0, sensitivity: .strict, at: t0) == 0)
        #expect(abs(neckLength(candidateSince: t0, sensitivity: .strict, at: t0 + grow) - 1) < 1e-9)
    }

    @Test func normalGrowsAfterOneAndHalfSeconds() {
        #expect(neckLength(candidateSince: t0, sensitivity: .normal, at: t0 + 1.4) == 0)
        #expect(neckLength(candidateSince: t0, sensitivity: .normal, at: t0 + 1.5) == 0)
        #expect(abs(neckLength(candidateSince: t0, sensitivity: .normal, at: t0 + 1.5 + grow) - 1) < 1e-9)
    }

    @Test func looseGrowsFromConfirmation() {
        let confirmed = t0 + Timing.enterAfter
        #expect(neckLength(candidateSince: t0, sensitivity: .loose, at: confirmed) == 0)
        #expect(abs(neckLength(candidateSince: t0, sensitivity: .loose, at: confirmed + grow) - 1) < 1e-9)
    }

    @Test func strongerSensitivityGivesLongerNeck() {
        let now = t0 + 4
        #expect(neckLength(candidateSince: t0, sensitivity: .strict, at: now) > neckLength(candidateSince: t0, sensitivity: .normal, at: now))
        #expect(neckLength(candidateSince: t0, sensitivity: .normal, at: now) > neckLength(candidateSince: t0, sensitivity: .loose, at: now))
    }

    @Test func delayDerivesFromEnterAfter() {
        #expect(Sensitivity.loose.neckStartDelay == Timing.enterAfter)
        #expect(Sensitivity.strict.neckStartDelay == 0)
    }

    @Test func capsAtNeckMax() {
        #expect(neckLength(candidateSince: t0, sensitivity: .strict, at: t0 + grow * 1000) == PetTiming.neckMax)
    }

    @Test func defaultSensitivityIsNormal() {
        #expect(Sensitivity.default == .normal)
        #expect(neckLength(candidateSince: t0, at: t0 + 1.5) == 0)
    }
}

@Suite struct PetMoodTests {
    @Test(arguments: [
        (FeedbackPhase?.none, PetMood.away),
        (.unavailable, .away),
        (.uncalibrated, .away),
        (.good, .good),
        (.pendingBad, .good),
        (.bad, .bad),
        (.recovering, .good),
    ])
    func moodFromPhase(phase: FeedbackPhase?, mood: PetMood) {
        #expect(petMood(from: phase) == mood)
    }
}
