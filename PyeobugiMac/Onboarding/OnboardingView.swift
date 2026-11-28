import AppKit
import SwiftUI

// Hosts the onboarding and calibration screens; one window at a time
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private let monitor: PostureMonitor
    private var window: NSWindow?
    // Called when the full onboarding, not a recalibration, ends with its completion dialog
    var onFinished: (() -> Void)?

    init(monitor: PostureMonitor) {
        self.monitor = monitor
    }

    func show(calibrationOnly: Bool) {
        if window == nil {
            let root = OnboardingView(monitor: monitor, step: calibrationOnly ? .calibrate : .intro) { [weak self] in
                self?.window?.close()
                if !calibrationOnly { self?.onFinished?() }
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
        window?.bringToFront()
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
                IntroScreen { step = .permission }
            case .permission:
                PermissionView(monitor: monitor, onGranted: { step = .calibrate }, onRefused: { step = .intro })
            case .calibrate:
                CalibrationView(monitor: monitor, close: close)
            }
        }
        .frame(width: 1280, height: 832)
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
