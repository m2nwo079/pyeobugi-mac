import AppKit
import SwiftUI

// Hosts the onboarding and calibration screens; one window at a time
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private let monitor: PostureMonitor
    private var window: NSWindow?

    init(monitor: PostureMonitor) {
        self.monitor = monitor
    }

    func show(calibrationOnly: Bool) {
        if window == nil {
            let root = OnboardingView(monitor: monitor, step: calibrationOnly ? .calibrate : .intro) { [weak self] in
                self?.window?.close()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.title = "펴부기"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
            monitor.holdCamera(true)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        // Closes the camera too if it was opened only for these screens
        monitor.holdCamera(false)
        window = nil
    }
}

struct OnboardingView: View {
    enum Step {
        case intro, permission, calibrate
    }

    let monitor: PostureMonitor
    @State var step: Step
    let close: () -> Void

    var body: some View {
        Group {
            switch step {
            case .intro:
                IntroView { step = .permission }
            case .permission:
                PermissionView(monitor: monitor, onGranted: { step = .calibrate }, onRefused: { step = .intro })
            case .calibrate:
                CalibrationView(monitor: monitor, close: close)
            }
        }
        .frame(width: 1280, height: 832)
    }
}

private struct IntroView: View {
    let start: () -> Void

    private static let points = [
        "웹캠으로 자세를 실시간으로 살펴요",
        "영상은 기기 안에서만 처리돼요",
        "자세가 무너지면 펴부기가 알려줘요",
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.main1
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("당신의 자세 건강,\n펴부기가 지켜드릴게요.")
                        .textStyle(.display)
                        .foregroundStyle(Color.grey900)
                    Text("공부하거나 일하는 동안 웹캠으로 앉은 자세를 살피고,\n자세가 구부정해지기 시작하면 펴부기가 알려드려요.")
                        .textStyle(.body)
                        .foregroundStyle(Color.grey700)
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(Self.points.enumerated()), id: \.offset) { index, point in
                        HStack(spacing: 8) {
                            Text(String(index + 1))
                                .textStyle(.caption)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(Color.grey900, lineWidth: 1))
                            Text(point).textStyle(.body)
                        }
                    }
                }
                .foregroundStyle(Color.grey900)
                Button("시작하기", action: start)
                    .buttonStyle(FilledButtonStyle(fill: false))
            }
            .padding(.leading, 46)
            .padding(.top, 93)
            // The laptop screen of the intro scene, rising from the bottom edge
            .frame(width: 999, height: 557, alignment: .topLeading)
            .background(Color.main5, in: UnevenRoundedRectangle(topLeadingRadius: 9, topTrailingRadius: 9))
            .padding(.leading, 141)
            .padding(.top, 275)
        }
    }
}

private struct PermissionView: View {
    let monitor: PostureMonitor
    let onGranted: () -> Void
    let onRefused: () -> Void

    @State private var isStarting = false
    @State private var refused = false

    var body: some View {
        let copy = Self.copy(for: monitor.camera)
        ZStack {
            Color.main1
            if isStarting {
                VStack(spacing: 16) {
                    Spinner()
                    Text("카메라 켜는 중...").textStyle(.heading).foregroundStyle(.white)
                }
            } else {
                DialogCard(title: copy.title, message: copy.message, confirm: copy.confirm, cancel: copy.cancel,
                           onConfirm: confirm, onCancel: cancel)
            }
            OnboardingHeader(current: 1)
            if refused {
                let denied = Self.copy(for: .denied)
                ModalDialog(title: denied.title, message: denied.message, confirm: denied.confirm) {
                    NSWorkspace.shared.openCameraSettings()
                    onRefused()
                }
            }
        }
        .onChange(of: monitor.camera, initial: true) {
            if monitor.camera == .running { onGranted() }
        }
    }

    private var failed: Bool {
        [.denied, .unavailable, .failed].contains(monitor.camera)
    }

    private func confirm() {
        if monitor.camera == .denied {
            NSWorkspace.shared.openCameraSettings()
        } else {
            openCamera()
        }
    }

    private func cancel() {
        if failed {
            openCamera()
        } else {
            refused = true
        }
    }

    // Opens the camera only; detection starts from the menu
    private func openCamera() {
        isStarting = true
        Task {
            await monitor.openCamera()
            isStarting = false
        }
    }

    private static func copy(for status: PostureMonitor.CameraStatus)
        -> (title: String, message: String, confirm: String, cancel: String?) {
        switch status {
        case .denied:
            ("카메라 권한 없음",
             "카메라가 없으면 자세를 감지할 수 없어요.\n시스템 설정에서 펴부기의 카메라 접근을 켜주세요.",
             "설정 열기", nil)
        case .unavailable:
            ("카메라를 찾을 수 없어요",
             "연결된 카메라가 없어요.\n카메라를 연결한 뒤 다시 시도해 주세요.",
             "다시 시도", nil)
        case .failed:
            ("카메라를 열 수 없어요",
             "다른 앱이 카메라를 쓰고 있을 수 있어요.\n그 앱을 끄고 다시 시도해 주세요.",
             "다시 시도", nil)
        case .idle, .running:
            ("카메라 권한을 허용하시겠습니까?",
             "펴부기가 자세를 감지하려면 카메라가 필요해요.\n카메라 영상은 기기 안에서만 처리돼요.",
             "허용", "거부")
        }
    }
}
