import AppKit
import Observation
import PostureCore
import SwiftUI

// Owns the overlay panel and feeds posture into the turtle's neck
@Observable
final class TurtleOverlay {
    static let visibleKey = "showTurtle"
    // How often posture is turned into a neck length
    static let updateInterval: TimeInterval = 0.1

    var isVisible: Bool {
        didSet {
            UserDefaults.standard.set(isVisible, forKey: Self.visibleKey)
            apply()
        }
    }

    @ObservationIgnored private let monitor: PostureMonitor
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var model: TurtleModel?
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var candidateSince: TimeInterval?

    init(monitor: PostureMonitor) {
        self.monitor = monitor
        isVisible = UserDefaults.standard.object(forKey: Self.visibleKey) as? Bool ?? true
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
        panel.level = .statusBar
        // Show on every Space and over full-screen apps
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false

        let model = TurtleModel(screen: screen.visibleFrame.size, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let host = NSHostingView(rootView: TurtleOverlayView(model: model))
        // Keep the panel at the visible frame instead of the content's ideal size
        host.sizingOptions = []
        panel.contentView = host
        panel.orderFrontRegardless()

        self.panel = panel
        self.model = model
        model.start()
        updates = Task { [weak self] in
            while !Task.isCancelled {
                self?.update()
                try? await Task.sleep(for: .seconds(Self.updateInterval))
            }
        }
    }

    private func hide() {
        updates?.cancel()
        updates = nil
        model?.stop()
        model = nil
        panel?.close()
        panel = nil
        candidateSince = nil
    }

    private func fitScreen() {
        guard let panel, let model, let screen = NSScreen.screens.first else { return }
        panel.setFrame(screen.visibleFrame, display: true)
        model.layout(screen.visibleFrame.size)
    }

    private func update() {
        let now = FaceCapture.now()
        let phase = monitor.feedback.phase
        // Hold the first candidate time through confirmation, because the engine reuses it for recovery.
        // Drop it once posture is good, recovering or unknown so the neck shrinks
        if phase == .pendingBad || petMood(from: phase) == .bad {
            candidateSince = candidateSince ?? monitor.candidateSince ?? now
        } else {
            candidateSince = nil
        }
        model?.setNeck(neckLength(candidateSince: candidateSince, at: now))
    }
}

struct TurtleOverlayView: View {
    let model: TurtleModel

    var body: some View {
        TimelineView(.animation(paused: model.reduceMotion)) { context in
            let frame = model.frame(at: context.date.timeIntervalSinceReferenceDate)
            TurtleFigure(frame: frame)
                .offset(x: frame.x - frame.size / 2, y: frame.y - frame.size * TurtleSize.footLine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
