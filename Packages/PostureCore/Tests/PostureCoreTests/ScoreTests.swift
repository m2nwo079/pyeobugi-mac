import Testing
import PostureCore

private let baseline = Baseline(pitch: 0, size: 0.3)

private func score(_ pitch: Double, _ size: Double = 0.3) -> Double {
    postureScore(pitch: pitch, size: size, baseline: baseline)
}

private func isClose(_ a: Double, _ b: Double) -> Bool {
    abs(a - b) < 1e-9
}

// Score added by a face 0.1 larger than baseline (max 0.1 * 120 = 12)
private func sizeContribution(atPitch pitch: Double) -> Double {
    score(pitch, 0.4) - score(pitch)
}

@Suite struct PostureScoreTests {
    @Test func isZeroAtBaseline() {
        #expect(score(0) == 0)
    }

    @Test func ignoresLargerFaceWhenNotPitchedDown() {
        #expect(score(3, 0.5) == score(3))
    }

    @Test func pitchDeadzoneEndsAt1_5() {
        #expect(score(1.5, 0.9) == 0)
        // Above the score deadzone the pitch term is (dPitch - 1.5) * 1.4
        #expect(isClose(score(5.5), 4 * 1.4 - 4))
        #expect(isClose(score(7.5), 6 * 1.4 - 4))
    }

    @Test func scoreDeadzoneSubtracts4() {
        // total 3.5
        #expect(score(4) == 0)
        // total 4.2
        #expect(isClose(score(4.5), 0.2))
    }

    @Test func sizeGateOpensAfter6AndSaturatesAt11() {
        #expect(sizeContribution(atPitch: 6) == 0)
        #expect(isClose(sizeContribution(atPitch: 6.5), 1.2))
        #expect(isClose(sizeContribution(atPitch: 8.5), 6))
        #expect(isClose(sizeContribution(atPitch: 11), 12))
        #expect(isClose(sizeContribution(atPitch: 16), 12))
    }

    @Test func smallerFaceDoesNotReduceScore() {
        #expect(score(11, 0.2) == score(11))
    }

    @Test func headRaisedAboveBaselineScoresZero() {
        #expect(score(-10) == 0)
        #expect(score(-10, 0.9) == 0)
        #expect(postureScore(pitch: 0, size: 0.5, baseline: Baseline(pitch: 8, size: 0.3)) == 0)
    }

    @Test func badThresholds() {
        #expect(badEnterScore == 3)
        #expect(badExitScore == 2)
    }
}

@Suite struct SensitivityTests {
    // Score when the head is deg past the stored baseline, scored against the tuned baseline
    private func tunedScore(_ deg: Double, _ sensitivity: Sensitivity) -> Double {
        postureScore(pitch: baseline.pitch + deg, size: baseline.size, baseline: tunedBaseline(baseline, sensitivity: sensitivity))
    }

    @Test func baseEnterPitchIs6_5() {
        #expect(isClose(baseEnterPitch, 6.5))
        #expect(Sensitivity.allCases.map(\.enterPitch) == [15, 10, baseEnterPitch])
    }

    @Test func entryAngleFollowsSensitivity() {
        for sensitivity in Sensitivity.allCases {
            let enter = sensitivity.enterPitch
            #expect(tunedScore(enter - 0.01, sensitivity) < badEnterScore)
            #expect(tunedScore(enter + 0.01, sensitivity) >= badEnterScore)
        }
    }

    @Test func recoveryAngleShiftsWithEntry() {
        // Unshifted, the score falls below badExitScore under 1.5 + 6 / 1.4 degrees
        for sensitivity in Sensitivity.allCases {
            let exit = sensitivity.enterPitch - baseEnterPitch + 1.5 + 6 / 1.4
            #expect(tunedScore(exit - 0.01, sensitivity) < badExitScore)
            #expect(tunedScore(exit + 0.01, sensitivity) >= badExitScore)
        }
    }

    @Test func stricterIsMoreSensitive() {
        #expect(tunedScore(12, .loose) < tunedScore(12, .normal))
        #expect(tunedScore(12, .normal) < tunedScore(12, .strict))
    }

    @Test func keepsBaselineSize() {
        for sensitivity in Sensitivity.allCases {
            #expect(tunedBaseline(baseline, sensitivity: sensitivity).size == baseline.size)
        }
    }

    @Test func strictKeepsStoredBaseline() {
        #expect(tunedBaseline(baseline, sensitivity: .strict) == baseline)
    }
}

@Suite struct SeverityTests {
    @Test func mapsScoresToBands() {
        #expect([severity(of: 3), severity(of: 10), severity(of: 18)] == [.mild, .moderate, .severe])
    }

    @Test func bandBoundaries() {
        #expect(severity(of: 0) == .mild)
        #expect(severity(of: 9.999) == .mild)
        #expect(severity(of: 17.999) == .moderate)
        #expect(severity(of: 100) == .severe)
    }

    @Test func maxSeverityKeepsTheWorse() {
        #expect(maxSeverity(nil, .mild) == .mild)
        #expect(maxSeverity(.mild, .severe) == .severe)
        #expect(maxSeverity(.severe, .mild) == .severe)
        #expect(maxSeverity(.moderate, .moderate) == .moderate)
    }
}
