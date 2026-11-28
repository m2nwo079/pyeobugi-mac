import AppKit
import Observation
import PostureCore
import os

// Owns the overlay panel, feeds posture into the turtle's neck and shows speech bubbles and the study timer
@Observable
final class TurtleOverlay {
    static let visibleKey = "showTurtle"
    static let sensitivityKey = "sensitivity"
    static let studyTimerKey = "studyTimer"
    static let stretchReminderKey = "stretchReminder"
    // How often posture is turned into a neck length
    static let updateInterval: TimeInterval = 0.1

    var isVisible: Bool {
        didSet {
            UserDefaults.standard.set(isVisible, forKey: Self.visibleKey)
            apply()
        }
    }

    // How soon the neck starts growing; stored as Sensitivity.rawValue
    var sensitivity: Sensitivity {
        didSet { UserDefaults.standard.set(sensitivity.rawValue, forKey: Self.sensitivityKey) }
    }

    // Runs regardless of detection, since it times study rather than posture
    var studyTimerOn: Bool {
        didSet {
            UserDefaults.standard.set(studyTimerOn, forKey: Self.studyTimerKey)
            timer.setRunning(studyTimerOn)
            apply()
        }
    }

    var stretchReminder: Bool {
        didSet { UserDefaults.standard.set(stretchReminder, forKey: Self.stretchReminderKey) }
    }

    @ObservationIgnored private let monitor: PostureMonitor
    @ObservationIgnored private let timer: StudyTimer
    @ObservationIgnored private let bubbles: TurtleBubbles
    @ObservationIgnored private let corner: TimerCorner
    @ObservationIgnored private let recalibrate: () -> Void
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var model: TurtleModel?
    @ObservationIgnored private var view: TurtleView?
    @ObservationIgnored private var pointer: TurtlePointer?
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var candidateSince: TimeInterval?
    // Whether "neck requested" was logged for the current candidate
    @ObservationIgnored private var neckLogged = false

    init(monitor: PostureMonitor, recalibrate: @escaping () -> Void) {
        self.monitor = monitor
        self.recalibrate = recalibrate
        let timer = StudyTimer()
        self.timer = timer
        bubbles = TurtleBubbles(monitor: monitor, timer: timer)
        corner = TimerCorner(timer: timer)
        let defaults = UserDefaults.standard
        // bool(forKey:) also reads launch arguments such as `-showTurtle NO`, which arrive as strings
        defaults.register(defaults: [Self.visibleKey: true, Self.studyTimerKey: false, Self.stretchReminderKey: true])
        isVisible = defaults.bool(forKey: Self.visibleKey)
        sensitivity = (defaults.object(forKey: Self.sensitivityKey) as? Int).flatMap(Sensitivity.init(rawValue:)) ?? .default
        studyTimerOn = defaults.bool(forKey: Self.studyTimerKey)
        stretchReminder = defaults.bool(forKey: Self.stretchReminderKey)
        timer.setRunning(studyTimerOn)
        let center = NotificationCenter.default
        // Windows are created once the app has finished launching
        center.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
        // The visible frame changes with the Dock, the menu bar and display settings
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fitScreen()
                self?.corner.fitScreen()
            }
        }
    }

    private func apply() {
        if isVisible, panel == nil {
            show()
        } else if !isVisible, panel != nil {
            hide()
        }
        // Without the turtle there is no head to put the timer over
        corner.setShown(!isVisible && studyTimerOn)
    }

    // A transparent click-through panel over every Space
    static func makePanel(_ frame: CGRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Let clicks pass through to the apps underneath
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.level = .statusBar
        // Show on every Space and over full-screen apps
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func show() {
        guard let screen = NSScreen.screens.first else { return }
        let panel = Self.makePanel(screen.visibleFrame)
        let model = TurtleModel(screen: screen.visibleFrame.size, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let view = TurtleView(model: model)
        // TurtleView hosts its own layers, so the bubble is its sibling rather than its subview
        let container = NSView(frame: CGRect(origin: .zero, size: screen.visibleFrame.size))
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        panel.contentView = container
        panel.orderFrontRegardless()

        self.panel = panel
        self.model = model
        self.view = view
        // Pointer tracking exists only while the overlay is shown
        let pointer = TurtlePointer(panel: panel, model: model, view: view)
        pointer.onTap = { [weak self] in self?.recalibrate() }
        self.pointer = pointer
        bubbles.attach(container: container, view: view, pointer: pointer)
        model.start()
        view.start()
        updates = Task { [weak self] in
            while !Task.isCancelled {
                self?.update()
                try? await Task.sleep(for: .seconds(Self.updateInterval))
            }
        }
    }

    private func hide() {
        bubbles.detach()
        pointer?.stop()
        pointer = nil
        updates?.cancel()
        updates = nil
        model?.stop()
        model = nil
        view?.stop()
        view = nil
        panel?.close()
        panel = nil
        candidateSince = nil
        neckLogged = false
    }

    private func fitScreen() {
        guard let panel, let model, let screen = NSScreen.screens.first else { return }
        panel.setFrame(screen.visibleFrame, display: true)
        model.layout(screen.visibleFrame.size)
    }

    private func update() {
        let now = FaceCapture.now()
        let phase = monitor.feedback.phase
        let held = candidateSince
        // Hold the first candidate time through confirmation, because the engine reuses it for recovery.
        // Drop it once posture is good, recovering or unknown so the neck shrinks
        if phase == .pendingBad || petMood(from: phase) == .bad {
            candidateSince = candidateSince ?? monitor.candidateSince ?? now
        } else {
            candidateSince = nil
        }
        let length = neckLength(candidateSince: candidateSince, sensitivity: sensitivity, at: now)
        if let since = candidateSince, length > 0, !neckLogged {
            neckLogged = true
            PostureMonitor.postureLog.debug("neck requested t=\(now, format: .fixed(precision: 3), privacy: .public) +\(now - since, format: .fixed(precision: 3), privacy: .public)s from candidate")
        }
        if let held, candidateSince == nil {
            neckLogged = false
            PostureMonitor.postureLog.debug("recovered t=\(now, format: .fixed(precision: 3), privacy: .public) +\(now - held, format: .fixed(precision: 3), privacy: .public)s from candidate (\(String(describing: phase), privacy: .public))")
        }
        model?.setNeck(length)
        bubbles.update(stretchReminder: stretchReminder)
    }
}
