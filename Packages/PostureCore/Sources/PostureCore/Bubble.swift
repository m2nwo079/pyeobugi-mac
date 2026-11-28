import Foundation

// Speech bubbles over the turtle. All times are in seconds
public enum BubbleKind: Sendable, Equatable, CaseIterable {
    case posture, distance, timerBreak, encourage, greeting, stretch

    // When bubbles overlap only the first of these is shown
    static let priority: [BubbleKind] = [.posture, .timerBreak, .encourage, .distance, .greeting, .stretch]

    var rank: Int { Self.priority.firstIndex(of: self)! }

    // Tapping it opens calibration
    public var isTappable: Bool { self == .distance }

    // Held by a condition (shown while it lasts) rather than triggered once
    var isHeld: Bool { self == .posture || self == .distance }

    // Still shown while the study timer runs, since the timer takes the spot over the head
    var showsDuringTimer: Bool { self == .posture || self == .timerBreak }
}

public enum BubbleTiming {
    // A triggered bubble stays this long; held ones stay while their condition lasts
    public static let showDuration: TimeInterval = 6
    // Gap after a bubble ends before the next one, so they do not pour out one after another
    public static let minGap: TimeInterval = 5
    // Wait before the same kind shows again
    public static let cooldowns: [BubbleKind: TimeInterval] = [
        .posture: 0,
        .distance: 0,
        .timerBreak: 60,
        .encourage: 30,
        .greeting: 10 * 60,
        .stretch: 20 * 60,
    ]
    // Stretch reminder interval while detecting, when the reminder is on
    public static let stretchInterval: TimeInterval = 30 * 60
}

// Conditions that last
public struct BubbleConditions: Sendable, Equatable {
    // Bad posture is confirmed
    public var posture: Bool
    // Recalibration is suggested because the sitting distance changed
    public var distance: Bool
    // The study timer is running
    public var timer: Bool

    public init(posture: Bool = false, distance: Bool = false, timer: Bool = false) {
        self.posture = posture
        self.distance = distance
        self.timer = timer
    }
}

// Picks the bubble to show.
// Held kinds (posture, distance) stay while their condition is true; one-off kinds are triggered and stay showDuration.
// Overlaps show the highest priority only, each kind waits out its cooldown, and bubbles keep minGap between them
public struct BubblePicker: Sendable {
    private let cooldowns: [BubbleKind: TimeInterval]
    private var shownAt: [BubbleKind: TimeInterval] = [:]
    // When the last bubble ended; no gap applies before the first one
    private var lastEndedAt = -TimeInterval.infinity
    private var pending: [BubbleKind] = []
    private var current: (kind: BubbleKind, until: TimeInterval)?

    public init(cooldowns: [BubbleKind: TimeInterval] = BubbleTiming.cooldowns) {
        self.cooldowns = cooldowns
    }

    private func coolingDown(_ kind: BubbleKind, at now: TimeInterval) -> Bool {
        guard let last = shownAt[kind] else { return false }
        return now - last < cooldowns[kind, default: 0]
    }

    // Queues a one-off bubble
    public mutating func trigger(_ kind: BubbleKind, at now: TimeInterval) {
        guard !coolingDown(kind, at: now), !pending.contains(kind) else { return }
        pending.append(kind)
    }

    // The bubble to show now, if any
    public mutating func update(at now: TimeInterval, conditions: BubbleConditions) -> BubbleKind? {
        let allowed = { (kind: BubbleKind) in !conditions.timer || kind.showsDuringTimer }
        var holding: [BubbleKind] = []
        if conditions.posture { holding.append(.posture) }
        if conditions.distance, allowed(.distance) { holding.append(.distance) }
        let waiting = holding + pending.filter(allowed)

        if let current {
            let alive = current.kind.isHeld ? holding.contains(current.kind) : now < current.until
            guard alive else {
                // It has run its course; the next one waits minGap
                self.current = nil
                lastEndedAt = now
                return nil
            }
            // Something more urgent replaces it right away, without the gap
            guard waiting.contains(where: { $0.rank < current.kind.rank }) else { return current.kind }
            self.current = nil
        }

        guard now - lastEndedAt >= BubbleTiming.minGap else { return nil }
        for kind in waiting.sorted(by: { $0.rank < $1.rank }) where !coolingDown(kind, at: now) {
            pending.removeAll { $0 == kind }
            shownAt[kind] = now
            current = (kind, now + BubbleTiming.showDuration)
            return kind
        }
        return nil
    }

    // When the overlay closes or detection stops; cooldowns are kept
    public mutating func reset() {
        pending = []
        current = nil
    }
}
