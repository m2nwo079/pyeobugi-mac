import Foundation
import Testing
import PostureCore

// All times are in seconds

private let t0: TimeInterval = 1000
private let focus = PomodoroTiming.focus
private let rest = PomodoroTiming.rest

@Suite struct PomodoroTests {
    @Test func startsStoppedWithFullFocus() {
        #expect(Pomodoro().state == PomodoroState(phase: .focus, remaining: focus, running: false, completed: 0))
    }

    @Test func countsDownOnceStarted() {
        var p = Pomodoro()
        p.start(at: t0)
        #expect(p.tick(at: t0 + 60).state.remaining == focus - 60)
    }

    @Test func finishedFocusCountsAndStartsBreak() {
        var p = Pomodoro()
        p.start(at: t0)
        let result = p.tick(at: t0 + focus)
        #expect(result.focusCompleted)
        #expect(result.state.phase == .rest)
        #expect(result.state.completed == 1)
        #expect(result.state.remaining == rest)
    }

    @Test func finishedBreakStartsNextFocusWithoutCounting() {
        var p = Pomodoro()
        p.start(at: t0)
        p.tick(at: t0 + focus)
        let result = p.tick(at: t0 + focus + rest)
        #expect(!result.focusCompleted)
        #expect(result.state.phase == .focus)
        #expect(result.state.completed == 1)
    }

    @Test func unfinishedFocusDoesNotCount() {
        var p = Pomodoro()
        p.start(at: t0)
        #expect(!p.tick(at: t0 + focus - 0.001).focusCompleted)
        #expect(p.state.completed == 0)
    }

    @Test func pauseKeepsRemainingTime() {
        var p = Pomodoro()
        p.start(at: t0)
        p.pause(at: t0 + 10 * 60)
        #expect(p.state.remaining == focus - 10 * 60)
        #expect(!p.state.running)

        // Time passing while paused changes nothing
        #expect(p.tick(at: t0 + 60 * 60).state.remaining == focus - 10 * 60)

        p.start(at: t0 + 60 * 60)
        #expect(p.tick(at: t0 + 60 * 60 + 60).state.remaining == focus - 11 * 60)
    }

    @Test func stopReturnsToFocusAndKeepsCount() {
        var p = Pomodoro()
        p.start(at: t0)
        p.tick(at: t0 + focus)
        #expect(p.stop() == PomodoroState(phase: .focus, remaining: focus, running: false, completed: 1))
    }

    @Test func lateTickSkipsPassedPhases() {
        var p = Pomodoro()
        p.start(at: t0)
        // Past focus, break and into the next focus
        let result = p.tick(at: t0 + focus + rest + 60)
        #expect(result.state.phase == .focus)
        #expect(result.state.completed == 1)
        #expect(result.state.remaining == focus - 60)
    }

    @Test func twoFocusesCountTwice() {
        var p = Pomodoro()
        p.start(at: t0)
        p.tick(at: t0 + focus)
        p.tick(at: t0 + focus + rest)
        #expect(p.tick(at: t0 + 2 * focus + rest).state.completed == 2)
    }

    @Test func shortDurationsAreUsed() {
        var p = Pomodoro(focus: 10, rest: 5)
        p.start(at: t0)
        #expect(p.tick(at: t0 + 10).focusCompleted)
        #expect(p.state.phase == .rest)
        #expect(p.state.remaining == 5)
    }
}

@Suite struct FormatRemainingTests {
    @Test func minutesAndSeconds() {
        #expect(formatRemaining(focus) == "25:00")
        #expect(formatRemaining(61) == "01:01")
        #expect(formatRemaining(0) == "00:00")
        #expect(formatRemaining(-0.005) == "00:00")
    }

    @Test func hoursPastAnHour() {
        #expect(formatRemaining(3900) == "1:05:00")
    }

    @Test func secondsRoundUp() {
        #expect(formatRemaining(0.5) == "00:01")
    }
}
