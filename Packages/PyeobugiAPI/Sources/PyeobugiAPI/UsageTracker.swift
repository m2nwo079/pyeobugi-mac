import Foundation

// All durations are in seconds
public enum UsageTiming {
    // A segment is closed this often while the face stays in view
    public static let segment: TimeInterval = 60
    // A face missing this long means the user left; the segment ends where the face was last seen
    public static let away: TimeInterval = 30
    // Samples further apart than this are not counted in between (sleep, a stalled camera)
    public static let maxGap: TimeInterval = 5
    // How often the open segment is saved as a snapshot, so a crash loses at most this much
    public static let checkpoint: TimeInterval = 10
}

// Turns detection samples into USAGE_SEGMENT payloads.
//
// A segment closes every minute, when the user leaves, at KST midnight, or when detection stops.
// Each segment starts where the previous one ended, so the server can add them up without overlap.
// The clock is passed in, so tests drive it directly.
public struct UsageTracker: Sendable {
    private let segmentLength: TimeInterval
    private let awayAfter: TimeInterval
    private let maxGap: TimeInterval

    // Start of the open segment, whole seconds; nil when there is none
    private var startedAt: Date?
    private var lastAt = Date.distantPast
    private var bad: TimeInterval = 0
    // The part of bad that was mild
    private var mild: TimeInterval = 0
    // When the face went missing, for telling a glance away from leaving
    private var lostAt: Date?

    public init(segment: TimeInterval = UsageTiming.segment,
                away: TimeInterval = UsageTiming.away,
                maxGap: TimeInterval = UsageTiming.maxGap) {
        segmentLength = segment
        awayAfter = away
        self.maxGap = maxGap
    }

    public var hasSegment: Bool { startedAt != nil }

    // Feeds one sample and returns the segments it closed. mild counts only while bad
    public mutating func update(at now: Date, face: Bool, bad isBad: Bool, mild isMild: Bool = false) -> [UsageSegment] {
        guard startedAt != nil else {
            if face { begin(at: now) }
            return []
        }

        let gap = now.timeIntervalSince(lastAt)
        if gap < 0 || gap > maxGap {
            // The clock jumped (wake from sleep and the like): count up to the last sample and cut there
            let segments = close(at: lastAt)
            if face { begin(at: now) }
            return segments
        }

        if !face {
            let lost = lostAt ?? lastAt
            lostAt = lost
            if now.timeIntervalSince(lost) >= awayAfter {
                // Left: close where the face disappeared and count nothing after it
                return close(at: lost)
            }
            // Not yet known whether this is a glance away or leaving. Emitting now would make it impossible
            // to cut back to where the face disappeared, so wait, even past a minute boundary
            lastAt = now
            return []
        }

        lostAt = nil
        return advance(to: now, bad: isBad, mild: isBad && isMild)
    }

    // Closes the open segment when detection pauses, stops or the app quits
    public mutating func flush(at now: Date) -> [UsageSegment] {
        guard startedAt != nil else { return [] }
        if let lostAt, now.timeIntervalSince(lostAt) >= awayAfter {
            // Left before stopping: count only up to where the face disappeared
            return close(at: lostAt)
        }
        // Never past the last sample plus the allowed gap, so a stop right after waking does not count the sleep
        return close(at: min(now, lastAt.addingTimeInterval(maxGap)))
    }

    // The open segment as it would close now, without changing the tracker. It ends where the face was
    // last seen, so a snapshot saved before a crash never counts time that was not observed
    public func snapshot() -> [UsageSegment] {
        var copy = self
        return copy.close(at: lostAt ?? lastAt)
    }

    private mutating func begin(at now: Date) {
        startedAt = KST.floorToSecond(now)
        lastAt = now
        bad = 0
        mild = 0
        lostAt = nil
    }

    // Counts from lastAt to now, cutting at segment boundaries and midnight
    private mutating func advance(to now: Date, bad isBad: Bool, mild isMild: Bool) -> [UsageSegment] {
        var segments: [UsageSegment] = []
        var from = lastAt

        while let start = startedAt {
            let boundary = min(start.addingTimeInterval(segmentLength), KST.nextMidnight(after: start))
            if now < boundary { break }

            // A boundary may have passed while a missing face was deferred, so never go negative
            let span = max(0, boundary.timeIntervalSince(from))
            if isBad { bad += span }
            if isMild { mild += span }
            if let segment = makeSegment(from: start, to: boundary, bad: bad, mild: mild) { segments.append(segment) }
            // The next segment starts where this one ended
            startedAt = boundary
            bad = 0
            mild = 0
            from = boundary
        }

        let rest = max(0, now.timeIntervalSince(from))
        if isBad { bad += rest }
        if isMild { mild += rest }
        lastAt = now
        return segments
    }

    private mutating func close(at end: Date) -> [UsageSegment] {
        let start = startedAt
        let badTotal = bad
        let mildTotal = mild
        startedAt = nil
        lostAt = nil
        bad = 0
        mild = 0
        guard let start else { return [] }

        // Cut again at midnight if the open segment crossed it, sharing bad time by length
        // instead of piling it into the last piece
        var segments: [UsageSegment] = []
        var from = start
        var remaining = badTotal
        var remainingMild = mildTotal
        while from < end {
            let to = min(KST.nextMidnight(after: from), end)
            let ratio = to.timeIntervalSince(from) / end.timeIntervalSince(from)
            let share = remaining * ratio
            let shareMild = min(remainingMild * ratio, share)
            if let segment = makeSegment(from: from, to: to, bad: share, mild: shareMild) { segments.append(segment) }
            remaining -= share
            remainingMild -= shareMild
            from = to
        }
        return segments
    }

    private func makeSegment(from start: Date, to end: Date, bad: TimeInterval, mild: TimeInterval) -> UsageSegment? {
        let startedAt = KST.floorToSecond(start)
        let endedAt = KST.floorToSecond(end)
        let duration = Int(endedAt.timeIntervalSince(startedAt).rounded())
        guard duration >= 1 else { return nil }
        // Rounded once from the accumulated time, and kept within mild <= bad <= duration as the server requires
        let badSec = min(max(Int(bad.rounded()), 0), duration)
        let mildSec = min(max(Int(mild.rounded()), 0), badSec)
        return UsageSegment(startedAt: startedAt, endedAt: endedAt, durationSec: duration,
                            badDurationSec: badSec, mildDurationSec: mildSec)
    }
}
