import AppKit
import PostureCore
import PyeobugiAPI
import os

// Turns app activity into anonymous events and hands them to an EventStore.
// Only the store protocol is known here; the file-backed store is chosen in `openDefault()`.
// Events carry no pitch, face size, baseline or sensitivity, only what the server accepts.
final class EventRecorder {
    // Toggle changes this close together become one SETTINGS_CHANGED
    static let settingsDebounce: TimeInterval = 0.5
    // Only event types, counts and failures are logged, never event contents
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PyeobugiMac", category: "events")

    private let store: (any EventStore)?
    // One session per app launch
    private let sessionId = UUID()
    private var usage = UsageTracker()
    private var checkpointAt = Date.distantPast
    // Whether the store holds a non-empty snapshot, so an empty one is written only once
    private var hasPending = false
    // The toggles last recorded; the values at launch count as already recorded
    private var recordedToggles: FeatureToggles?
    private var togglesTask: Task<Void, Never>?
    // The day whose cap was last reported, so a full day is logged once
    private var fullDay: String?

    init(store: (any EventStore)?) {
        self.store = store
        // Closing the open segment before sleep keeps it even if power is lost while asleep;
        // the time asleep is never counted, since no samples arrive
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushUsage() }
        }
    }

    // Events/ under the app's Application Support folder (inside the sandbox container).
    // Without a store the app keeps running and records nothing
    static func openDefault() -> EventRecorder {
        let directory = URL.applicationSupportDirectory.appending(path: "Events")
        do {
            return EventRecorder(store: try FileEventStore(directory: directory))
        } catch {
            log.error("Event store unavailable: \(error.localizedDescription, privacy: .public)")
            return EventRecorder(store: nil)
        }
    }

    func sessionStarted() {
        record(.sessionStart)
    }

    // The last segment is closed before the session ends
    func sessionEnded() {
        flushUsage()
        record(.sessionEnd)
    }

    // One detection sample while detecting. mild counts only while bad
    func usageSample(face: Bool, bad: Bool, mild: Bool, at now: Date = .now) {
        let segments = usage.update(at: now, face: face, bad: bad, mild: mild)
        segments.forEach { record(.usageSegment($0)) }
        // A closed segment makes the saved snapshot stale right away
        if !segments.isEmpty || now.timeIntervalSince(checkpointAt) >= UsageTiming.checkpoint {
            checkpoint(at: now)
        }
    }

    // Detection paused or stopped, the Mac is going to sleep, or the app quits
    func flushUsage(at now: Date = .now) {
        usage.flush(at: now).forEach { record(.usageSegment($0)) }
        checkpoint(at: now)
    }

    // occurredAt is when the bad posture began, not when it was confirmed
    func postureBad(_ severity: PostureCore.Severity, since start: Date) {
        let value: PyeobugiAPI.Severity = switch severity {
        case .mild: .mild
        case .moderate: .moderate
        case .severe: .severe
        }
        record(.postureBad(value), at: start)
    }

    func calibrationCompleted(isRecalibration: Bool) {
        record(.calibrationCompleted(isRecalibration: isRecalibration))
    }

    // The distance bubble has no type of its own on the server and counts as POSTURE
    func bubbleShown(_ kind: BubbleKind) {
        let type: BubbleType = switch kind {
        case .posture, .distance: .posture
        case .stretch: .stretch
        case .timerBreak: .timerBreak
        case .encourage: .encourage
        case .greeting: .greeting
        }
        record(.bubbleShown(type))
    }

    func pomodoroCompleted() {
        record(.pomodoroCompleted)
    }

    // There is no away pause setting yet, so awayPause is always false
    private static func toggles(studyTimer: Bool, stretch: Bool, overlay: Bool) -> FeatureToggles {
        FeatureToggles(studyTimer: studyTimer, stretch: stretch, awayPause: false, overlay: overlay)
    }

    // The values at launch; nothing is recorded for them
    func settingsLoaded(studyTimer: Bool, stretch: Bool, overlay: Bool) {
        recordedToggles = Self.toggles(studyTimer: studyTimer, stretch: stretch, overlay: overlay)
    }

    // Recorded once the toggles stop changing, and only if they differ from the last recorded values
    func settingsChanged(studyTimer: Bool, stretch: Bool, overlay: Bool) {
        let toggles = Self.toggles(studyTimer: studyTimer, stretch: stretch, overlay: overlay)
        togglesTask?.cancel()
        togglesTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.settingsDebounce))
            guard !Task.isCancelled, let self, toggles != self.recordedToggles else { return }
            self.recordedToggles = toggles
            self.record(.settingsChanged(toggles))
        }
    }

    private func record(_ payload: EventPayload, at date: Date = .now) {
        guard let store else { return }
        do {
            try store.append(Event(sessionId: sessionId, payload: payload, occurredAt: date))
            Self.log.debug("Recorded \(payload.type, privacy: .public)")
        } catch EventStoreError.dayFull(let day) {
            if day != fullDay {
                fullDay = day
                Self.log.error("Daily event cap reached for \(day, privacy: .public); further events that day are dropped")
            }
        } catch {
            Self.log.error("Failed to record \(payload.type, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // Saves the open segment so a crash loses at most one checkpoint interval
    private func checkpoint(at now: Date) {
        checkpointAt = now
        guard let store else { return }
        let pending = usage.snapshot().map { Event(sessionId: sessionId, payload: .usageSegment($0)) }
        guard !pending.isEmpty || hasPending else { return }
        do {
            try store.savePending(pending)
            hasPending = !pending.isEmpty
        } catch {
            Self.log.error("Failed to save the usage snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }
}
