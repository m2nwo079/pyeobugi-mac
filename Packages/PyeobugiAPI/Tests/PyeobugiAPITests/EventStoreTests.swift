import Foundation
import Testing
@testable import PyeobugiAPI

private func kst(_ string: String) -> Date {
    KST.date(from: string)!
}

// A fresh folder per test, removed afterwards
private final class Folder {
    let url = FileManager.default.temporaryDirectory.appending(path: "EventStoreTests-\(UUID().uuidString)")

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func file(_ name: String) -> URL { url.appending(path: name) }

    func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)).sorted()
    }
}

private let now = kst("2026-11-28T12:00:00+09:00")
private let session = UUID()

private func event(_ payload: EventPayload = .sessionStart, at string: String = "2026-11-28T10:00:00+09:00") -> Event {
    Event(sessionId: session, payload: payload, occurredAt: kst(string))
}

private func segment(from start: String, to end: String) -> Event {
    let startedAt = kst(start), endedAt = kst(end)
    let duration = Int(endedAt.timeIntervalSince(startedAt))
    return event(.usageSegment(UsageSegment(startedAt: startedAt, endedAt: endedAt, durationSec: duration,
                                            badDurationSec: 0, mildDurationSec: 0)))
}

@Test func appendedEventsReadBackByDay() throws {
    let folder = Folder()
    let store = try FileEventStore(directory: folder.url, now: now)
    let first = event(at: "2026-11-27T09:00:00+09:00")
    let second = event(.postureBad(.mild), at: "2026-11-28T09:00:00+09:00")
    let third = event(.pomodoroCompleted, at: "2026-11-28T11:00:00+09:00")
    for e in [first, second, third] { try store.append(e) }

    #expect(try store.events(from: "2026-11-28", through: "2026-11-28") == [second, third])
    #expect(try store.events(from: "2026-11-27", through: "2026-11-28") == [first, second, third])
    #expect(try store.events(from: "2026-11-01", through: "2026-11-26").isEmpty)
    #expect(try folder.names() == ["2026-11-27.json", "2026-11-28.json"])
}

@Test func storedAsUnsentWireEvents() throws {
    let folder = Folder()
    let store = try FileEventStore(directory: folder.url, now: now)
    let e = event(.bubbleShown(.greeting))
    try store.append(e)

    let data = try Data(contentsOf: folder.file("2026-11-28.json"))
    let records = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    #expect(records.count == 1)
    #expect(records[0]["sent"] as? Bool == false)
    // The stored event is exactly what the server receives
    let stored = try #require(records[0]["event"] as? NSDictionary)
    let wire = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as? NSDictionary)
    #expect(stored == wire)
}

@Test func segmentEndingAtMidnightStaysOnItsStartDay() throws {
    let folder = Folder()
    let store = try FileEventStore(directory: folder.url, now: now)
    let late = segment(from: "2026-11-27T23:59:10+09:00", to: "2026-11-28T00:00:00+09:00")
    try store.append(late)
    #expect(try store.events(from: "2026-11-27", through: "2026-11-27") == [late])
    #expect(try store.events(from: "2026-11-28", through: "2026-11-28").isEmpty)
}

@Test func dropsEventsOverTheDailyCap() throws {
    let folder = Folder()
    let store = try FileEventStore(directory: folder.url, maxEventsPerDay: 2, now: now)
    try store.append(event())
    try store.append(event())
    #expect(throws: EventStoreError.dayFull(day: "2026-11-28")) { try store.append(event()) }
    #expect(try store.events(from: "2026-11-28", through: "2026-11-28").count == 2)
    // Other days are not affected
    try store.append(event(at: "2026-11-27T10:00:00+09:00"))
}

@Test func removesDaysPastRetentionWhenOpened() throws {
    let folder = Folder()
    let store = try FileEventStore(directory: folder.url, now: now)
    // With 90 days kept, 2026-11-28 keeps 2026-08-31 and later
    try store.append(event(at: "2026-08-30T10:00:00+09:00"))
    try store.append(event(at: "2026-08-31T10:00:00+09:00"))
    try store.append(event(at: "2026-11-28T10:00:00+09:00"))
    try Data().write(to: folder.file("notes.txt"))

    _ = try FileEventStore(directory: folder.url, now: now)
    #expect(try folder.names() == ["2026-08-31.json", "2026-11-28.json", "notes.txt"])
}

@Test func recoversPendingSnapshotOnNextOpen() throws {
    let folder = Folder()
    let crashed = try FileEventStore(directory: folder.url, now: now)
    let open = segment(from: "2026-11-28T10:01:00+09:00", to: "2026-11-28T10:01:40+09:00")
    try crashed.savePending([open])
    #expect(try crashed.events(from: "2026-11-28", through: "2026-11-28").isEmpty)

    let reopened = try FileEventStore(directory: folder.url, now: now)
    #expect(try reopened.events(from: "2026-11-28", through: "2026-11-28") == [open])
    #expect(!FileManager.default.fileExists(atPath: folder.file("pending.json").path(percentEncoded: false)))
    // Opening again does not add it twice
    _ = try FileEventStore(directory: folder.url, now: now)
    #expect(try reopened.events(from: "2026-11-28", through: "2026-11-28") == [open])
}

@Test func pendingDuplicateOfAStoredSegmentIsDropped() throws {
    let folder = Folder()
    let store = try FileEventStore(directory: folder.url, now: now)
    let closed = segment(from: "2026-11-28T10:00:00+09:00", to: "2026-11-28T10:01:00+09:00")
    try store.append(closed)
    // Crash before the snapshot of the same segment was replaced
    try store.savePending([segment(from: "2026-11-28T10:00:00+09:00", to: "2026-11-28T10:00:50+09:00")])

    let reopened = try FileEventStore(directory: folder.url, now: now)
    #expect(try reopened.events(from: "2026-11-28", through: "2026-11-28") == [closed])
}

@Test func emptyPendingClearsTheSnapshot() throws {
    let folder = Folder()
    let store = try FileEventStore(directory: folder.url, now: now)
    try store.savePending([segment(from: "2026-11-28T10:00:00+09:00", to: "2026-11-28T10:00:30+09:00")])
    try store.savePending([])

    let reopened = try FileEventStore(directory: folder.url, now: now)
    #expect(try reopened.events(from: "2026-11-28", through: "2026-11-28").isEmpty)
}

@Test func corruptDayFileIsMovedAside() throws {
    let folder = Folder()
    let store = try FileEventStore(directory: folder.url, now: now)
    try Data("{not json".utf8).write(to: folder.file("2026-11-28.json"))
    let e = event()
    try store.append(e)
    #expect(try store.events(from: "2026-11-28", through: "2026-11-28") == [e])
    #expect(try folder.names() == ["2026-11-28.json", "2026-11-28.json.corrupt"])
}
