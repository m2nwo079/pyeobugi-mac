import Foundation
import Testing
@testable import PyeobugiAPI

private struct Body: Codable {
    var events: [Event]
}

private func fixture() throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "post-events.request", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

// Compares JSON values, ignoring key order and formatting
private func json(_ data: Data) throws -> NSObject {
    try #require(JSONSerialization.jsonObject(with: data) as? NSObject)
}

private func fixtureEvents() throws -> [NSDictionary] {
    let body = try #require(json(try fixture()) as? NSDictionary)
    return try #require(body["events"] as? [NSDictionary])
}

private func kst(_ string: String) throws -> Date {
    try #require(KST.date(from: string))
}

private func uuid(_ string: String) throws -> UUID {
    try #require(UUID(uuidString: string))
}

private let session = "a9a9a9a9-0000-4000-8000-0000000000aa"

@Test func fixtureRoundTripsUnchanged() throws {
    let data = try fixture()
    let body = try JSONDecoder().decode(Body.self, from: data)
    #expect(body.events.count == 8)
    let encoded = try JSONEncoder().encode(body)
    #expect(try json(encoded) == json(data))
}

@Test func builtEventsMatchFixture() throws {
    let expected = try fixtureEvents()
    let sessionId = try uuid(session)
    let built = [
        (0, Event(sessionId: sessionId, payload: .sessionStart,
                  occurredAt: try kst("2026-11-03T23:58:05+09:00"),
                  eventId: try uuid("b1c2d3e4-0000-4000-8000-000000000001"))),
        (1, Event(sessionId: sessionId, payload: .calibrationCompleted(isRecalibration: false),
                  occurredAt: try kst("2026-11-03T23:58:09+09:00"),
                  eventId: try uuid("b1c2d3e4-0000-4000-8000-000000000002"))),
        (2, Event(sessionId: sessionId, payload: .postureBad(.moderate),
                  occurredAt: try kst("2026-11-03T23:58:30+09:00"),
                  eventId: try uuid("b1c2d3e4-0000-4000-8000-000000000003"))),
        // Ends at midnight; occurredAt comes from endedAt, and nil mild leaves the key out
        (4, Event(sessionId: sessionId, payload: .usageSegment(UsageSegment(
                    startedAt: try kst("2026-11-03T23:59:10+09:00"),
                    endedAt: try kst("2026-11-04T00:00:00+09:00"),
                    durationSec: 50, badDurationSec: 50, mildDurationSec: nil)),
                  eventId: try uuid("b1c2d3e4-0000-4000-8000-000000000005"))),
    ]
    for (index, event) in built {
        #expect(try json(JSONEncoder().encode(event)) == expected[index])
    }
}

@Test func payloadShapes() throws {
    let sessionId = try uuid(session)
    let at = try kst("2026-11-04T10:00:00+09:00")
    let cases: [(EventPayload, NSDictionary)] = [
        (.sessionEnd, [:]),
        (.pomodoroCompleted, [:]),
        (.bubbleShown(.timerBreak), ["bubbleType": "TIMER_BREAK"]),
        (.settingsChanged(FeatureToggles(studyTimer: true, stretch: false, awayPause: false, overlay: true)),
         ["studyTimer": true, "stretch": false, "awayPause": false, "overlay": true]),
        (.usageSegment(UsageSegment(startedAt: at, endedAt: at.addingTimeInterval(60),
                                    durationSec: 60, badDurationSec: 10, mildDurationSec: 0)),
         ["startedAt": "2026-11-04T10:00:00+09:00", "endedAt": "2026-11-04T10:01:00+09:00",
          "durationSec": 60, "badDurationSec": 10, "mildDurationSec": 0]),
    ]
    for (payload, expected) in cases {
        let event = Event(sessionId: sessionId, payload: payload, occurredAt: at)
        let object = try #require(json(JSONEncoder().encode(event)) as? NSDictionary)
        #expect(Set(object.allKeys as? [String] ?? []) == ["eventId", "sessionId", "occurredAt", "type", "payload"])
        #expect(object["type"] as? String == payload.type)
        #expect(object["payload"] as? NSDictionary == expected)
        // Lowercase UUID v4, as the server pattern and the examples use
        let id = try #require(object["eventId"] as? String)
        #expect(id == id.lowercased() && id.count == 36 && Array(id)[14] == "4")
        #expect(try JSONDecoder().decode(Event.self, from: JSONEncoder().encode(event)) == event)
    }
}

@Test func kstStringDropsFractionalSeconds() throws {
    let at = try kst("2026-11-26T14:03:05+09:00").addingTimeInterval(0.9)
    #expect(KST.string(from: at) == "2026-11-26T14:03:05+09:00")
    let event = Event(sessionId: UUID(), payload: .sessionStart, occurredAt: at)
    #expect(event.occurredAt == KST.floorToSecond(at))
    // Same instant written in UTC is shown in KST
    #expect(KST.string(from: Date(timeIntervalSince1970: 0)) == "1970-01-01T09:00:00+09:00")
}

@Test func kstParsesOnlyServerForm() {
    #expect(KST.date(from: "2026-11-26T14:03:00+09:00") != nil)
    #expect(KST.date(from: "2026-11-26T05:03:00Z") == nil)
    #expect(KST.date(from: "2026-11-26T14:03:00.000+09:00") == nil)
    #expect(KST.date(from: "2026-11-26T15:03:00+10:00") == nil)
}

@Test func kstDays() throws {
    let late = try kst("2026-11-03T23:59:10+09:00")
    #expect(KST.dayString(of: late) == "2026-11-03")
    #expect(KST.startOfDay(late) == (try kst("2026-11-03T00:00:00+09:00")))
    #expect(KST.nextMidnight(after: late) == (try kst("2026-11-04T00:00:00+09:00")))
    #expect(KST.nextMidnight(after: try kst("2026-11-04T00:00:00+09:00")) == (try kst("2026-11-05T00:00:00+09:00")))
}

@Test func segmentCountsOnTheDayItStarted() throws {
    let segment = UsageSegment(startedAt: try kst("2026-11-03T23:59:10+09:00"),
                               endedAt: try kst("2026-11-04T00:00:00+09:00"),
                               durationSec: 50, badDurationSec: 0, mildDurationSec: 0)
    let event = Event(sessionId: UUID(), payload: .usageSegment(segment), occurredAt: .distantPast)
    #expect(event.occurredAt == segment.endedAt)
    #expect(event.reportDay == "2026-11-03")
    #expect(Event(sessionId: UUID(), payload: .sessionEnd, occurredAt: segment.endedAt).reportDay == "2026-11-04")
}
