//
//  PyeobugiMacApp.swift
//  PyeobugiMac
//
//  Created by 이민우 on 11/26/26.
//

import SwiftUI

@main
struct PyeobugiMacApp: App {
    @State private var monitor: PostureMonitor
    @State private var overlay: TurtleOverlay
    @State private var onboarding: OnboardingWindow

    init() {
        let monitor = PostureMonitor()
        let onboarding = OnboardingWindow(monitor: monitor)
        _monitor = State(initialValue: monitor)
        _overlay = State(initialValue: TurtleOverlay(monitor: monitor))
        _onboarding = State(initialValue: onboarding)
        if !PostureMonitor.isOnboarded {
            // Runs once the app has finished launching
            Task { onboarding.show(calibrationOnly: false) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: monitor, overlay: overlay, onboarding: onboarding)
        } label: {
            Image(systemName: monitor.symbolName)
                .accessibilityLabel(monitor.title)
        }
    }
}
