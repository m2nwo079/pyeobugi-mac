import AppKit
import PostureCore
import SwiftUI

struct MenuBarView: View {
    let monitor: PostureMonitor
    @Bindable var overlay: TurtleOverlay
    let onboarding: OnboardingWindow

    var body: some View {
        Text(monitor.title)
        Divider()
        if monitor.camera == .denied {
            Text("카메라 권한이 꺼져 있습니다.")
            Text("시스템 설정에서 펴부기의 카메라 접근을 허용해 주세요.")
            Button("시스템 설정에서 카메라 열기…") {
                NSWorkspace.shared.openCameraSettings()
            }
            Divider()
        }
        if let message = calibrationMessage {
            Text(message)
        }
        Button(monitor.isDetecting ? "감지 정지" : "감지 시작") {
            Task { await monitor.toggleDetection() }
        }
        Button("기준 잡기") {
            onboarding.show(calibrationOnly: true)
        }
        .disabled(monitor.camera == .denied)
        Toggle("거북이 표시", isOn: $overlay.isVisible)
        Toggle("전체 화면에서도 표시", isOn: $overlay.overFullScreen)
        Toggle("공부 타이머", isOn: $overlay.studyTimerOn)
        Toggle("스트레칭 알림", isOn: $overlay.stretchReminder)
        Picker("교정 강도", selection: $overlay.sensitivity) {
            ForEach(Sensitivity.allCases, id: \.self) { level in
                Text(level.label).tag(level)
            }
        }
        .pickerStyle(.menu)
        Divider()
        Button("종료") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var calibrationMessage: String? {
        switch monitor.calibration {
        case .idle:
            return monitor.isDetecting && monitor.baseline == nil ? "바르게 앉은 뒤 기준 잡기를 눌러 주세요." : nil
        case .collecting(let remaining):
            return "기준 잡는 중… \(remaining)초 동안 바르게 앉아 계세요."
        case .failed:
            return "기준 잡기 실패. 움직이지 말고 다시 시도해 주세요."
        case .saved:
            return "기준을 저장했습니다."
        }
    }
}

extension Sensitivity {
    var label: String {
        switch self {
        case .loose: "느슨"
        case .normal: "보통"
        case .strict: "엄격"
        }
    }
}

extension PostureMonitor {
    // Every name here was checked to load with NSImage(systemSymbolName:)
    var symbolName: String {
        switch camera {
        case .idle: return "pause.circle"
        case .denied: return "lock"
        case .unavailable, .failed: return "video.slash"
        case .running: break
        }
        guard isDetecting else { return "pause.circle" }
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
        case .failed: return "카메라 오류"
        case .running: break
        }
        guard isDetecting else { return "감지 꺼짐" }
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
