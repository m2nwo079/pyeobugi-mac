import Foundation
import Testing
import PostureCore

// All times are in seconds

private let good: EngineState = {
    var state = EngineState.initial
    state.present = true
    state.tracking = true
    state.pitch = 0
    state.size = 0.3
    return state
}()

private let bad: EngineState = {
    var state = good
    state.bad = true
    state.badSince = 1
    state.score = 12
    return state
}()

private func with(_ state: EngineState, _ change: (inout EngineState) -> Void) -> EngineState {
    var copy = state
    change(&copy)
    return copy
}

@Suite struct FeedbackPhaseTests {
    @Test func startsUnavailable() {
        #expect(PostureFeedback.initial.phase == .unavailable)
    }

    @Test func exposesPendingBadAndRecoveringWithSustainedDuration() {
        let pending = with(good) { $0.pendingSince = 1 }
        #expect(updateFeedback(.initial, engine: pending, at: 2, calibrated: true, transitions: []).phase == .pendingBad)

        let confirmed = updateFeedback(.initial, engine: bad, at: 6, calibrated: true, transitions: [])
        #expect(confirmed.phase == .bad)
        #expect(confirmed.score == 12)
        #expect(confirmed.severity == .moderate)
        #expect(confirmed.badSince == 1)
        #expect(confirmed.badDuration == 5)

        let recovering = with(bad) { $0.pendingSince = 5 }
        #expect(updateFeedback(.initial, engine: recovering, at: 6, calibrated: true, transitions: []).phase == .recovering)
    }

    @Test func suppressesFeedbackOnlyWhenFaceIsLostOrUncalibrated() {
        #expect(updateFeedback(.initial, engine: bad, at: 6, calibrated: true, transitions: []).phase == .bad)

        let lost = updateFeedback(.initial, engine: with(bad) { $0.present = false }, at: 6, calibrated: true, transitions: [])
        #expect(lost.phase == .unavailable)
        #expect(lost.score == nil)
        #expect(lost.severity == nil)
        #expect(lost.badSince == nil)
        #expect(lost.badDuration == 0)

        #expect(updateFeedback(.initial, engine: good, at: 6, calibrated: false, transitions: []).phase == .uncalibrated)
    }
}

@Suite struct FeedbackExitTests {
    @Test func distinguishesExitReasonsWithIncreasingIds() {
        let recovered = updateFeedback(
            .initial, engine: good, at: 6, calibrated: true,
            transitions: [.badExit(at: 4, reason: .recovered)]
        )
        #expect(recovered.lastExit == FeedbackExit(id: 1, reason: .recovered, occurredAt: 4, detectedAt: 6))

        let next = updateFeedback(recovered, engine: good, at: 7, calibrated: true, transitions: [])
        #expect(next.lastExit == recovered.lastExit)

        let absent = updateFeedback(
            next, engine: .initial, at: 8, calibrated: true,
            transitions: [.badExit(at: 5, reason: .faceLost)]
        )
        #expect(absent.lastExit?.id == 2)
        #expect(absent.lastExit?.reason == .faceLost)

        let reset = updateFeedback(
            absent, engine: good, at: 9, calibrated: true,
            transitions: [.badExit(at: 9, reason: .recalibrated)]
        )
        #expect(reset.lastExit?.id == 3)
        #expect(reset.lastExit?.reason == .recalibrated)
    }

    @Test func keepsSequenceAfterSessionResetClearsLastExit() {
        var reset = PostureFeedback.initial
        reset.exitSequence = 8
        let feedback = updateFeedback(
            reset, engine: good, at: 9, calibrated: true,
            transitions: [.badExit(at: 7, reason: .recovered)]
        )
        #expect(feedback.lastExit?.id == 9)
    }
}
