import Foundation
import Testing
@testable import PyeobugiAPI

private let minute: TimeInterval = 60

private func kst(_ string: String) -> Date {
    KST.date(from: string)!
}

private let start = kst("2026-10-27T10:00:00+09:00")

// A fake clock that feeds one sample per step
private final class Clock {
    var tracker: UsageTracker
    var now: Date
    var step: TimeInterval = 1
    var segments: [UsageSegment] = []

    init(_ tracker: UsageTracker = UsageTracker(), at now: Date = start) {
        self.tracker = tracker
        self.now = now
    }

    // Feeds a sample now, then one every step until the time has passed
    @discardableResult
    func run(_ seconds: TimeInterval, face: Bool = true, bad: Bool = false, mild: Bool = false) -> Self {
        let until = now.addingTimeInterval(seconds)
        segments += tracker.update(at: now, face: face, bad: bad, mild: mild)
        while now < until {
            now = min(now.addingTimeInterval(step), until)
            segments += tracker.update(at: now, face: face, bad: bad, mild: mild)
        }
        return self
    }

    @discardableResult
    func flush() -> Self {
        segments += tracker.flush(at: now)
        return self
    }
}

private func total(_ segments: [UsageSegment]) -> Int { segments.reduce(0) { $0 + $1.durationSec } }
private func totalBad(_ segments: [UsageSegment]) -> Int { segments.reduce(0) { $0 + $1.badDurationSec } }
private func totalMild(_ segments: [UsageSegment]) -> Int { segments.reduce(0) { $0 + ($1.mildDurationSec ?? 0) } }

// The server's USAGE_SEGMENT rules
private func isValid(_ s: UsageSegment) -> Bool {
    let mild = s.mildDurationSec ?? 0
    let sameDay = KST.dayString(of: s.startedAt) == KST.dayString(of: s.endedAt)
        || s.endedAt == KST.nextMidnight(after: s.startedAt)
    return s.badDurationSec >= 0 && s.badDurationSec <= s.durationSec
        && mild >= 0 && mild <= s.badDurationSec
        && s.durationSec <= 3600
        && s.startedAt < s.endedAt
        && sameDay
        && abs(Double(s.durationSec) - s.endedAt.timeIntervalSince(s.startedAt)) <= 1
}

@Suite struct Segments {
    @Test func closesEveryMinute() {
        let c = Clock()
        c.run(3 * minute + 10)
        #expect(c.segments.map(\.durationSec) == [60, 60, 60])
        #expect(KST.string(from: c.segments[0].startedAt) == "2026-10-27T10:00:00+09:00")
        #expect(KST.string(from: c.segments[0].endedAt) == "2026-10-27T10:01:00+09:00")
    }

    @Test func nextStartsWhereThePreviousEnded() {
        let c = Clock()
        c.run(5 * minute)
        for (previous, next) in zip(c.segments, c.segments.dropFirst()) {
            #expect(next.startedAt == previous.endedAt)
        }
    }

    @Test func onlyBadTimeCountsAsBad() {
        let c = Clock()
        c.run(20).run(15, bad: true).run(25)
        #expect(c.segments.count == 1)
        #expect(c.segments[0].durationSec == 60)
        #expect(c.segments[0].badDurationSec == 15)
    }

    @Test func flushClosesTheRest() {
        let c = Clock()
        c.run(90).flush()
        #expect(c.segments.map(\.durationSec) == [60, 30])
    }

    @Test func flushWithoutSegmentMakesNothing() {
        let c = Clock()
        c.flush()
        #expect(c.segments.isEmpty)
    }

    @Test func everySegmentPassesServerRules() {
        let c = Clock()
        c.run(2 * minute, bad: true).run(30, face: false).run(3 * minute, bad: true, mild: true).flush()
        #expect(!c.segments.isEmpty)
        #expect(c.segments.allSatisfy(isValid))
    }
}

@Suite struct Mild {
    @Test func countsOnlyWhileMild() {
        let c = Clock()
        c.run(30).run(20, bad: true, mild: true).run(10, bad: true).flush()
        #expect(totalBad(c.segments) == 30)
        #expect(totalMild(c.segments) == 20)
    }

    @Test func ignoredWhenNotBad() {
        let c = Clock()
        c.run(minute, mild: true).flush()
        #expect(totalMild(c.segments) == 0)
    }

    @Test func zeroIsWrittenNotOmitted() {
        let c = Clock()
        c.run(minute).flush()
        #expect(c.segments[0].mildDurationSec == 0)
    }

    @Test func neverExceedsBad() {
        let c = Clock()
        c.run(90, bad: true, mild: true).run(90, bad: true).flush()
        #expect(c.segments.allSatisfy { ($0.mildDurationSec ?? 0) <= $0.badDurationSec })
    }

    @Test func sharedWithBadAtMidnight() {
        let c = Clock(UsageTracker(segment: 10 * minute), at: kst("2026-10-27T23:59:00+09:00"))
        c.run(2 * minute, bad: true, mild: true).flush()
        #expect(c.segments.count == 2)
        #expect(totalMild(c.segments) == totalBad(c.segments))
        #expect(c.segments.allSatisfy { ($0.mildDurationSec ?? 0) <= $0.badDurationSec })
    }
}

@Suite struct MissingFace {
    @Test func shortLossCountsAsUseButNotAsBad() {
        let c = Clock()
        c.run(20, bad: true).run(10, face: false, bad: true).run(30)
        #expect(c.segments.count == 1)
        #expect(c.segments[0].durationSec == 60)
        #expect(c.segments[0].badDurationSec == 20)
    }

    @Test func leavingClosesWhereTheFaceDisappeared() {
        let c = Clock()
        c.run(40).run(2 * minute, face: false)
        #expect(c.segments.map(\.durationSec) == [40])
    }

    @Test func comingBackStartsANewSegment() {
        let c = Clock()
        c.run(40).run(2 * minute, face: false).run(70)
        #expect(c.segments.map(\.durationSec) == [40, 60])
        // The two minutes away are left out
        #expect(c.segments[1].startedAt.timeIntervalSince(c.segments[0].endedAt) == 2 * minute)
    }

    @Test func stoppingWhileAwayCountsUntilTheFaceDisappeared() {
        let c = Clock()
        c.run(40).run(45, face: false).flush()
        #expect(total(c.segments) == 40)
    }
}

@Suite struct Midnight {
    @Test func cutsAtMidnight() {
        let c = Clock(at: kst("2026-10-27T23:59:30+09:00"))
        c.run(60)
        #expect(c.segments.count == 1)
        #expect(KST.string(from: c.segments[0].endedAt) == "2026-10-28T00:00:00+09:00")
        #expect(c.segments[0].durationSec == 30)
    }

    @Test func flushCutsAtMidnightToo() {
        let c = Clock(at: kst("2026-10-27T23:59:40+09:00"))
        c.run(20, bad: true).run(10, bad: true).flush()
        #expect(c.segments.count == 2)
        #expect(KST.string(from: c.segments[0].endedAt) == "2026-10-28T00:00:00+09:00")
        #expect(KST.string(from: c.segments[1].startedAt) == "2026-10-28T00:00:00+09:00")
        #expect(total(c.segments) == 30)
        #expect(totalBad(c.segments) == 30)
    }

    @Test func segmentsStayWithinOneDay() {
        let c = Clock(at: kst("2026-10-27T23:58:00+09:00"))
        c.run(5 * minute).flush()
        #expect(c.segments.allSatisfy(isValid))
    }
}

@Suite struct Sleep {
    @Test func timeAsleepIsNotCounted() {
        let c = Clock()
        c.run(40)
        // Wakes three hours later
        c.now = c.now.addingTimeInterval(3 * 60 * minute)
        c.run(0).flush()
        #expect(total(c.segments) == 40)
    }

    // Stopping right after waking, before any new sample, must not count the sleep either
    @Test func stopRightAfterWakingIsCapped() {
        let c = Clock()
        c.run(40)
        c.now = c.now.addingTimeInterval(3 * 60 * minute)
        c.flush()
        #expect(total(c.segments) == 40 + Int(UsageTiming.maxGap))
    }
}

@Suite struct Snapshot {
    @Test func matchesWhatAFlushWouldWriteAndChangesNothing() {
        let c = Clock()
        c.run(75, bad: true)
        let snapshot = c.tracker.snapshot()
        #expect(snapshot.map(\.durationSec) == [15])
        #expect(snapshot[0].badDurationSec == 15)
        // The tracker carries on as if nothing happened
        c.run(45).flush()
        #expect(c.segments.map(\.durationSec) == [60, 60])
        #expect(c.segments[1].startedAt == snapshot[0].startedAt)
    }

    @Test func endsWhereTheFaceWasLastSeen() {
        let c = Clock()
        c.run(20).run(15, face: false)
        #expect(c.tracker.snapshot().map(\.durationSec) == [20])
    }

    @Test func emptyWithoutSegment() {
        let c = Clock()
        c.run(minute).run(minute, face: false)
        #expect(c.tracker.snapshot().isEmpty)
    }

    @Test func splitsAtMidnight() {
        let c = Clock(at: kst("2026-10-27T23:59:50+09:00"))
        c.run(20)
        let snapshot = c.tracker.snapshot()
        #expect(snapshot.allSatisfy(isValid))
        #expect(total(c.segments + snapshot) == 20)
    }
}
