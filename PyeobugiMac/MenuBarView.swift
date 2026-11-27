import AppKit
import PostureCore
import SwiftUI

struct MenuBarView: View {
    let monitor: PostureMonitor
    @Bindable var overlay: TurtleOverlay

    var body: some View {
        Text(monitor.title)
        Divider()
        if monitor.camera == .denied {
            Text("카메라 권한이 꺼져 있습니다.")
            Text("시스템 설정에서 펴부기의 카메라 접근을 허용해 주세요.")
            Button("시스템 설정에서 카메라 열기…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
            Divider()
        }
        if let message = calibrationMessage {
            Text(message)
        }
        Button(monitor.isRunning ? "감지 정지" : "감지 시작") {
            Task { await monitor.toggleDetection() }
        }
        Button("기준 잡기") {
            monitor.startCalibration()
        }
        .disabled(!monitor.isRunning || monitor.isCalibrating)
        Toggle("거북이 표시", isOn: $overlay.isVisible)
        Divider()
        Button("종료") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var calibrationMessage: String? {
        switch monitor.calibration {
        case .idle:
            return monitor.isRunning && monitor.baseline == nil ? "바르게 앉은 뒤 기준 잡기를 눌러 주세요." : nil
        case .collecting(let remaining):
            return "기준 잡는 중… \(remaining)초 동안 바르게 앉아 계세요."
        case .failed:
            return "기준 잡기 실패. 움직이지 말고 다시 시도해 주세요."
        case .saved:
            return "기준을 저장했습니다."
        }
    }
}

extension PostureMonitor {
    // Every name here was checked to load with NSImage(systemSymbolName:)
    var symbolName: String {
        switch camera {
        case .idle: return "pause.circle"
        case .denied: return "lock"
        case .unavailable: return "video.slash"
        case .running: break
        }
        switch feedback.phase {
        case .uncalibrated: return "scope"
        case .unavailable: return "magnifyingglass"
        case .good: return "checkmark.circle"
        case .pendingBad: return "hourglass"
        case .bad: return "exclamationmark.triangle.fill"
        case .recovering: return "arrow.up.circle"
        }
    }

    var title: String {
        switch camera {
        case .idle: return "감지 꺼짐"
        case .denied: return "카메라 권한 필요"
        case .unavailable: return "카메라 없음"
        case .running: break
        }
        switch feedback.phase {
        case .uncalibrated: return "기준 필요"
        case .unavailable: return "얼굴 찾는 중"
        case .good: return "바른 자세"
        case .pendingBad: return "자세 확인 중"
        case .recovering: return "회복 중"
        case .bad:
            switch feedback.severity {
            case .severe: return "거북목 (심함)"
            case .moderate: return "거북목 (중간)"
            case .mild, nil: return "거북목 (가벼움)"
            }
        }
    }
}
