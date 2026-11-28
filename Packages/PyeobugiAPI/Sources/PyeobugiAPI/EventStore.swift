import Foundation

// Where events are kept on the device. Code that records events knows only this protocol.
// Implementations are not thread-safe; use one from a single actor.
public protocol EventStore: AnyObject {
    // Adds one event, unsent. Throws EventStoreError.dayFull when its report day is at the cap
    func append(_ event: Event) throws
    // Replaces the saved snapshot of the open usage segment; an empty list clears it.
    // A snapshot left behind by a crash is stored as ordinary events the next time the store opens
    func savePending(_ events: [Event]) throws
    // Events whose report day (Event.reportDay) is within the KST dates, `YYYY-MM-DD`, in stored order
    func events(from firstDay: String, through lastDay: String) throws -> [Event]
}

public enum EventStoreError: Error, Equatable {
    // The event was dropped because its day already holds the maximum number of events
    case dayFull(day: String)
}

// One JSON file per KST report day, `<directory>/2026-11-28.json`, holding `[{"event": {...}, "sent": false}]`.
// Every write replaces the whole file atomically, so a crash leaves either the old file or the new one.
// `sent` is kept for the server upload, which will read unsent events and mark them; nothing sets it yet.
public final class FileEventStore: EventStore {
    public static let retentionDays = 90
    public static let maxEventsPerDay = 5_000

    private struct Record: Codable {
        var event: Event
        var sent: Bool
    }

    private let directory: URL
    private let maxEventsPerDay: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var pendingURL: URL { directory.appending(path: "pending.json") }

    // Opening recovers a pending snapshot from the last run and deletes days older than the retention period
    public init(directory: URL,
                retentionDays: Int = FileEventStore.retentionDays,
                maxEventsPerDay: Int = FileEventStore.maxEventsPerDay,
                now: Date = .now) throws {
        self.directory = directory
        self.maxEventsPerDay = maxEventsPerDay
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try recoverPending()
        try removeDays(before: KST.dayString(of: KST.startOfDay(now).addingTimeInterval(-Double(retentionDays - 1) * KST.day)))
    }

    // Reads and rewrites the whole day file on every append, a few hundred KB at most.
    // Keep the current day in memory if appends ever show up in profiles
    public func append(_ event: Event) throws {
        let day = event.reportDay
        var records = try load(day)
        guard records.count < maxEventsPerDay else { throw EventStoreError.dayFull(day: day) }
        records.append(Record(event: event, sent: false))
        try encoder.encode(records).write(to: url(of: day), options: .atomic)
    }

    public func savePending(_ events: [Event]) throws {
        try encoder.encode(events).write(to: pendingURL, options: .atomic)
    }

    public func events(from firstDay: String, through lastDay: String) throws -> [Event] {
        try days().filter { $0 >= firstDay && $0 <= lastDay }.flatMap { try load($0).map(\.event) }
    }

    // A snapshot segment whose closed version was already stored (same session and start) is a duplicate:
    // the app crashed between storing the closed segment and replacing the snapshot
    private func recoverPending() throws {
        guard let data = try? Data(contentsOf: pendingURL) else { return }
        for event in (try? decoder.decode([Event].self, from: data)) ?? [] {
            guard case .usageSegment(let segment) = event.payload else { continue }
            let stored = try load(event.reportDay).contains { record in
                guard case .usageSegment(let other) = record.event.payload else { return false }
                return record.event.sessionId == event.sessionId && other.startedAt == segment.startedAt
            }
            if stored { continue }
            do {
                try append(event)
            } catch EventStoreError.dayFull {
                // Dropped like any other event over the cap
                continue
            }
        }
        try FileManager.default.removeItem(at: pendingURL)
    }

    private func removeDays(before cutoff: String) throws {
        for day in try days() where day < cutoff {
            try FileManager.default.removeItem(at: url(of: day))
        }
    }

    private func url(of day: String) -> URL {
        directory.appending(path: "\(day).json")
    }

    // Report days that have a file, oldest first
    private func days() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .compactMap { name -> String? in
                guard name.hasSuffix(".json") else { return nil }
                let day = String(name.dropLast(5))
                return day.count == 10 && KST.date(from: "\(day)T00:00:00+09:00") != nil ? day : nil
            }
            .sorted()
    }

    // A file that does not decode is moved aside to `<day>.json.corrupt`, so the day can keep recording
    private func load(_ day: String) throws -> [Record] {
        let file = url(of: day)
        guard let data = try? Data(contentsOf: file) else { return [] }
        if let records = try? decoder.decode([Record].self, from: data) { return records }
        let aside = directory.appending(path: "\(day).json.corrupt")
        try? FileManager.default.removeItem(at: aside)
        try FileManager.default.moveItem(at: file, to: aside)
        return []
    }
}
