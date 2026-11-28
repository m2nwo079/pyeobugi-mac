import Foundation

// Study timer: focus and break alternate. All times are in seconds; the clock is passed in
public enum PomodoroPhase: Sendable, Equatable {
    case focus, rest
}

public enum PomodoroTiming {
    public static let focus: TimeInterval = 25 * 60
    public static let rest: TimeInterval = 5 * 60
}

public struct PomodoroState: Sendable, Equatable {
    public var phase: PomodoroPhase
    public var remaining: TimeInterval
    public var running: Bool
    // Focus sessions finished so far
    public var completed: Int

    public init(phase: PomodoroPhase, remaining: TimeInterval, running: Bool, completed: Int) {
        self.phase = phase
        self.remaining = remaining
        self.running = running
        self.completed = completed
    }
}

// Only a finished focus counts as completed; a finished break moves on to the next focus
public struct Pomodoro: Sendable {
    private let focus: TimeInterval
    private let rest: TimeInterval
    private var phase = PomodoroPhase.focus
    private var completed = 0
    // When the current phase ends; nil while stopped or paused
    private var endsAt: TimeInterval?
    // Time left, kept while paused
    private var left: TimeInterval

    public init(focus: TimeInterval = PomodoroTiming.focus, rest: TimeInterval = PomodoroTiming.rest) {
        self.focus = focus
        self.rest = rest
        left = focus
    }

    public var state: PomodoroState {
        PomodoroState(phase: phase, remaining: left, running: endsAt != nil, completed: completed)
    }

    @discardableResult
    public mutating func start(at now: TimeInterval) -> PomodoroState {
        if endsAt == nil { endsAt = now + left }
        return snapshot(at: now)
    }

    @discardableResult
    public mutating func pause(at now: TimeInterval) -> PomodoroState {
        if let endsAt {
            left = max(0, endsAt - now)
            self.endsAt = nil
        }
        return state
    }

    // Back to a fresh focus; the completed count is kept
    @discardableResult
    public mutating func stop() -> PomodoroState {
        phase = .focus
        endsAt = nil
        left = focus
        return state
    }

    // Called every second. Moves on when a phase has ended
    public mutating func tick(at now: TimeInterval) -> (state: PomodoroState, focusCompleted: Bool) {
        guard endsAt != nil else { return (state, false) }
        var focusCompleted = false
        // After a long sleep several phases may have passed at once
        while let end = endsAt, now >= end {
            if phase == .focus {
                completed += 1
                focusCompleted = true
                phase = .rest
                endsAt = end + rest
            } else {
                phase = .focus
                endsAt = end + focus
            }
        }
        return (snapshot(at: now), focusCompleted)
    }

    private mutating func snapshot(at now: TimeInterval) -> PomodoroState {
        if let endsAt { left = max(0, endsAt - now) }
        return state
    }
}

// "25:00", or "1:05:00" past an hour. Seconds round up so half a second left does not read 00:00
public func formatRemaining(_ seconds: TimeInterval) -> String {
    let total = Int(max(0, seconds).rounded(.up))
    let hours = total / 3600, minutes = total / 60 % 60, secs = total % 60
    let tail = String(format: "%02d:%02d", minutes, secs)
    return hours > 0 ? "\(hours):\(tail)" : tail
}
