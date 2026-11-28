//
//  PyeobugiMacApp.swift
//  PyeobugiMac
//
//  Created by 이민우 on 11/26/26.
//

import AppKit
import SwiftUI
import os

@main
struct PyeobugiMacApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var monitor: PostureMonitor
    @State private var overlay: TurtleOverlay
    @State private var onboarding: OnboardingWindow
    @State private var main: MainWindow

    init() {
        let monitor = PostureMonitor()
        let onboarding = OnboardingWindow(monitor: monitor)
        let overlay = TurtleOverlay(monitor: monitor) { onboarding.show(calibrationOnly: true) }
        let main = MainWindow(monitor: monitor, overlay: overlay) { onboarding.show(calibrationOnly: true) }
        onboarding.onFinished = { main.show(.report) }
        AppDelegate.reopen = { main.show() }
        _monitor = State(initialValue: monitor)
        _overlay = State(initialValue: overlay)
        _onboarding = State(initialValue: onboarding)
        _main = State(initialValue: main)
        // Runs once the app has finished launching
        if PostureMonitor.isOnboarded {
            Task { main.show(.report) }
        } else {
            Task { onboarding.show(calibrationOnly: false) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: monitor, overlay: overlay, onboarding: onboarding, main: main)
        } label: {
            Image(systemName: monitor.symbolName)
                .accessibilityLabel(monitor.title)
        }
    }
}

// Dock policy: the app shows in the Dock and Cmd+Tab only while one of its titled windows (main, onboarding,
// calibration) is open, and is a menu bar app otherwise. Overlay panels are borderless, so they never count
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Set by the app before launch finishes
    static var reopen: () -> Void = {}
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PyeobugiMac", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard let closing = note.object as? NSWindow, closing.isAppWindow else { return }
                let othersOpen = NSApp.windows.contains { $0 !== closing && $0.isAppWindow }
                if !othersOpen {
                    Self.log.debug("last window closed, dock icon hidden")
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    // A Dock click or launching the app again brings the front open window forward, or opens the main window
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.log.debug("reopen requested")
        if let open = NSApp.orderedWindows.first(where: \.isAppWindow) ?? NSApp.windows.first(where: \.isAppWindow) {
            open.bringToFront()
        } else {
            Self.reopen()
        }
        return false
    }
}

extension NSWindow {
    // Open, or minimized to the Dock
    var isAppWindow: Bool { styleMask.contains(.titled) && (isVisible || isMiniaturized) }

    // Shows the Dock icon first, so the window can become key even while another app is active
    func bringToFront() {
        NSApp.setActivationPolicy(.regular)
        if isMiniaturized { deminiaturize(nil) }
        makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
