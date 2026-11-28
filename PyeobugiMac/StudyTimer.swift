import Foundation
import Observation
import PostureCore

enum FastTimers {
    // Debug builds only: launching with `-fastTimers YES` turns the minute-long timers into seconds
    static let scale: Double = {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "fastTimers") ? 1.0 / 60 : 1
        #else
        1
        #endif
    }()
}

// Runs the study timer once a second while it is on
@Observable
final class StudyTimer {
    private(set) var state: PomodoroState
    @ObservationIgnored private var pomodoro = Pomodoro(
        focus: PomodoroTiming.focus * FastTimers.scale,
        rest: PomodoroTiming.rest * FastTimers.scale
    )
    @ObservationIgnored private var ticks: Task<Void, Never>?

    init() {
        state = pomodoro.state
    }

    // Wall clock, so time asleep counts as time passed
    private static func now() -> TimeInterval {
        Date().timeIntervalSinceReferenceDate
    }

    // On starts a fresh focus; off stops and returns to the start
    func setRunning(_ on: Bool) {
        guard on != state.running else { return }
        guard on else {
            ticks?.cancel()
            ticks = nil
            state = pomodoro.stop()
            return
        }
        state = pomodoro.start(at: Self.now())
        ticks = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.state = self.pomodoro.tick(at: Self.now()).state
            }
        }
    }
}
