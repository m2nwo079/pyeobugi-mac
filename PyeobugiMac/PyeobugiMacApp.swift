//
//  PyeobugiMacApp.swift
//  PyeobugiMac
//
//  Created by 이민우 on 11/26/26.
//

import SwiftUI

@main
struct PyeobugiMacApp: App {
    @State private var monitor = PostureMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        MenuBarExtra {
            MenuBarView(monitor: monitor)
        } label: {
            Image(systemName: monitor.symbolName)
                .accessibilityLabel(monitor.title)
        }
    }
}
