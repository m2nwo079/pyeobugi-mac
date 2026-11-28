import AppKit
import Observation
import PostureCore
import os

// Owns the overlay panel and feeds posture into the turtle's neck
@Observable
final class TurtleOverlay {
    static let visibleKey = "showTurtle"
    static let sensitivityKey = "sensitivity"
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

    @ObservationIgnored private let monitor: PostureMonitor
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var model: TurtleModel?
    @ObservationIgnored private var view: TurtleView?
    @ObservationIgnored private var pointer: TurtlePointer?
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var candidateSince: TimeInterval?
    // Whether "neck requested" was logged for the current candidate
    @ObservationIgnored private var neckLogged = false

    init(monitor: PostureMonitor) {
        self.monitor = monitor
        isVisible = UserDefaults.standard.object(forKey: Self.visibleKey) as? Bool ?? true
        sensitivity = (UserDefaults.standard.object(forKey: Self.sensitivityKey) as? Int).flatMap(Sensitivity.init(rawValue:)) ?? .default
        let center = NotificationCenter.default
        // Windows are created once the app has finished launching
        center.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
        // The visible frame changes with the Dock, the menu bar and display settings
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitScreen() }
        }
    }

    private func apply() {
        if isVisible, panel == nil {
            show()
        } else if !isVisible, panel != nil {
            hide()
        }
    }

    private func show() {
        guard let screen = NSScreen.screens.first else { return }
        let panel = NSPanel(
            contentRect: screen.visibleFrame,
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

        let model = TurtleModel(screen: screen.visibleFrame.size, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let view = TurtleView(model: model)
        panel.contentView = view
        panel.orderFrontRegardless()

        self.panel = panel
        self.model = model
        self.view = view
        // Pointer tracking exists only while the overlay is shown
        pointer = TurtlePointer(panel: panel, model: model, view: view)
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
    }
}
