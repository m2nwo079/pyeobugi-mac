import Foundation

// Korea Standard Time helpers. The server accepts only `2026-11-26T14:03:00+09:00`:
// a fixed +09:00 offset, seconds precision, no `Z` and no fractional seconds.
// KST has no daylight saving time, so plain offset arithmetic is exact.
public enum KST {
    static let offset: TimeInterval = 9 * 60 * 60
    static let day: TimeInterval = 24 * 60 * 60
    private static let style = Date.ISO8601FormatStyle(
        dateSeparator: .dash,
        dateTimeSeparator: .standard,
        timeSeparator: .colon,
        timeZoneSeparator: .colon,
        includingFractionalSeconds: false,
        timeZone: TimeZone(secondsFromGMT: Int(offset))!
    )

    // Drops fractional seconds, the same way the string form does
    public static func floorToSecond(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970).rounded(.down))
    }

    public static func string(from date: Date) -> String {
        floorToSecond(date).formatted(style)
    }

    // Only the exact server form parses; anything else is nil
    public static func date(from string: String) -> Date? {
        guard string.count == 25, string.hasSuffix("+09:00"), let date = try? style.parse(string) else { return nil }
        return date
    }

    // The KST calendar date as `YYYY-MM-DD`; strings of this form sort in date order
    public static func dayString(of date: Date) -> String {
        String(string(from: date).prefix(10))
    }

    public static func startOfDay(_ date: Date) -> Date {
        let shifted = date.timeIntervalSince1970 + offset
        return Date(timeIntervalSince1970: (shifted / day).rounded(.down) * day - offset)
    }

    public static func nextMidnight(after date: Date) -> Date {
        startOfDay(date).addingTimeInterval(day)
    }
}

public enum Severity: String, Codable, Sendable {
    case mild = "MILD"
    case moderate = "MODERATE"
    case severe = "SEVERE"
}

public enum BubbleType: String, Codable, Sendable {
    case posture = "POSTURE"
    case stretch = "STRETCH"
    case timerBreak = "TIMER_BREAK"
    case encourage = "ENCOURAGE"
    case greeting = "GREETING"
}

// USAGE_SEGMENT payload. The server requires mild <= bad <= duration <= 3600, startedAt < endedAt,
// and both ends on the same KST date, except that a segment may end exactly at the next midnight
public struct UsageSegment: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    public var durationSec: Int
    public var badDurationSec: Int
    // Optional on the wire: when nil the key is left out, because the server rejects null
    public var mildDurationSec: Int?

    public init(startedAt: Date, endedAt: Date, durationSec: Int, badDurationSec: Int, mildDurationSec: Int?) {
        self.startedAt = KST.floorToSecond(startedAt)
        self.endedAt = KST.floorToSecond(endedAt)
        self.durationSec = durationSec
        self.badDurationSec = badDurationSec
        self.mildDurationSec = mildDurationSec
    }

    private enum CodingKeys: String, CodingKey {
        case startedAt, endedAt, durationSec, badDurationSec, mildDurationSec
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = try c.decodeKST(forKey: .startedAt)
        endedAt = try c.decodeKST(forKey: .endedAt)
        durationSec = try c.decode(Int.self, forKey: .durationSec)
        badDurationSec = try c.decode(Int.self, forKey: .badDurationSec)
        mildDurationSec = try c.decodeIfPresent(Int.self, forKey: .mildDurationSec)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(KST.string(from: startedAt), forKey: .startedAt)
        try c.encode(KST.string(from: endedAt), forKey: .endedAt)
        try c.encode(durationSec, forKey: .durationSec)
        try c.encode(badDurationSec, forKey: .badDurationSec)
        try c.encodeIfPresent(mildDurationSec, forKey: .mildDurationSec)
    }
}

// SETTINGS_CHANGED payload: only these four on/off switches, never sensitivity or baseline values
public struct FeatureToggles: Codable, Equatable, Sendable {
    public var studyTimer: Bool
    public var stretch: Bool
    public var awayPause: Bool
    public var overlay: Bool

    public init(studyTimer: Bool, stretch: Bool, awayPause: Bool, overlay: Bool) {
        self.studyTimer = studyTimer
        self.stretch = stretch
        self.awayPause = awayPause
        self.overlay = overlay
    }
}

public enum EventPayload: Equatable, Sendable {
    case sessionStart
    case sessionEnd
    case usageSegment(UsageSegment)
    case postureBad(Severity)
    case pomodoroCompleted
    case calibrationCompleted(isRecalibration: Bool)
    case bubbleShown(BubbleType)
    case settingsChanged(FeatureToggles)

    public var type: String {
        switch self {
        case .sessionStart: "SESSION_START"
        case .sessionEnd: "SESSION_END"
        case .usageSegment: "USAGE_SEGMENT"
        case .postureBad: "POSTURE_BAD"
        case .pomodoroCompleted: "POMODORO_COMPLETED"
        case .calibrationCompleted: "CALIBRATION_COMPLETED"
        case .bubbleShown: "BUBBLE_SHOWN"
        case .settingsChanged: "SETTINGS_CHANGED"
        }
    }
}

// One anonymous event, encoded exactly as POST /api/events expects. The server rejects unknown fields,
// so the wire form has only these keys and the payload keys of its type
public struct Event: Codable, Equatable, Sendable {
    public let eventId: UUID
    public let sessionId: UUID
    public let occurredAt: Date
    public let payload: EventPayload

    // A usage segment always occurs at its end, as the server requires, whatever occurredAt says
    public init(sessionId: UUID, payload: EventPayload, occurredAt: Date = .now, eventId: UUID = UUID()) {
        self.eventId = eventId
        self.sessionId = sessionId
        self.payload = payload
        if case .usageSegment(let segment) = payload {
            self.occurredAt = segment.endedAt
        } else {
            self.occurredAt = KST.floorToSecond(occurredAt)
        }
    }

    // The KST date a local report counts this event on. A segment counts on the day it started,
    // so one ending at midnight stays on the earlier day, as the server counts it
    public var reportDay: String {
        if case .usageSegment(let segment) = payload { return KST.dayString(of: segment.startedAt) }
        return KST.dayString(of: occurredAt)
    }

    private enum CodingKeys: String, CodingKey {
        case eventId, sessionId, occurredAt, type, payload
    }

    private enum PayloadKeys: String, CodingKey {
        case severity, isRecalibration, bubbleType
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try c.decodeUUID(forKey: .eventId)
        sessionId = try c.decodeUUID(forKey: .sessionId)
        occurredAt = try c.decodeKST(forKey: .occurredAt)
        let type = try c.decode(String.self, forKey: .type)
        let p = try c.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)
        switch type {
        case "SESSION_START": payload = .sessionStart
        case "SESSION_END": payload = .sessionEnd
        case "USAGE_SEGMENT": payload = .usageSegment(try c.decode(UsageSegment.self, forKey: .payload))
        case "POSTURE_BAD": payload = .postureBad(try p.decode(Severity.self, forKey: .severity))
        case "POMODORO_COMPLETED": payload = .pomodoroCompleted
        case "CALIBRATION_COMPLETED": payload = .calibrationCompleted(isRecalibration: try p.decode(Bool.self, forKey: .isRecalibration))
        case "BUBBLE_SHOWN": payload = .bubbleShown(try p.decode(BubbleType.self, forKey: .bubbleType))
        case "SETTINGS_CHANGED": payload = .settingsChanged(try c.decode(FeatureToggles.self, forKey: .payload))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown event type \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(eventId.uuidString.lowercased(), forKey: .eventId)
        try c.encode(sessionId.uuidString.lowercased(), forKey: .sessionId)
        try c.encode(KST.string(from: occurredAt), forKey: .occurredAt)
        try c.encode(payload.type, forKey: .type)
        switch payload {
        case .usageSegment(let segment):
            try c.encode(segment, forKey: .payload)
        case .settingsChanged(let toggles):
            try c.encode(toggles, forKey: .payload)
        default:
            // An empty nested container still writes `{}`
            var p = c.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)
            switch payload {
            case .postureBad(let severity): try p.encode(severity, forKey: .severity)
            case .calibrationCompleted(let isRecalibration): try p.encode(isRecalibration, forKey: .isRecalibration)
            case .bubbleShown(let bubbleType): try p.encode(bubbleType, forKey: .bubbleType)
            default: break
            }
        }
    }
}

extension KeyedDecodingContainer {
    fileprivate func decodeKST(forKey key: Key) throws -> Date {
        let string = try decode(String.self, forKey: key)
        guard let date = KST.date(from: string) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Not a KST time: \(string)")
        }
        return date
    }

    fileprivate func decodeUUID(forKey key: Key) throws -> UUID {
        let string = try decode(String.self, forKey: key)
        guard let uuid = UUID(uuidString: string) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Not a UUID: \(string)")
        }
        return uuid
    }
}
