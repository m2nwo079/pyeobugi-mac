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

    init() {
        let monitor = PostureMonitor()
        _monitor = State(initialValue: monitor)
        _overlay = State(initialValue: TurtleOverlay(monitor: monitor))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        MenuBarExtra {
            MenuBarView(monitor: monitor, overlay: overlay)
        } label: {
            Image(systemName: monitor.symbolName)
                .accessibilityLabel(monitor.title)
        }
    }
}
