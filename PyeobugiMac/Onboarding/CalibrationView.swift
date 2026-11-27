import AVFoundation
import AppKit
import SwiftUI

struct CalibrationView: View {
    let monitor: PostureMonitor
    let close: () -> Void

    @State private var failed = false
    @State private var done = false

    private static let failedMessage = "얼굴을 정면으로 두고 움직임을 줄여 다시 시도해 주세요."

    // Calibration needs pitch, so the button waits for a face with pitch
    private var ready: Bool { monitor.faceMarks?.hasPitch == true }
    // Once an attempt starts, the screen stays on the capture step even if the face drops out
    private var capturing: Bool { ready || monitor.isCalibrating }

    var body: some View {
        ZStack {
            CameraPreview(monitor: monitor)
            OnboardingHeader(current: capturing ? 3 : 2)
            OnboardingPanel(title: capturing ? "바른 자세로 앉은 뒤 기준을 잡아주세요." : "얼굴이 보이도록 앉아주세요.",
                            message: failed ? Self.failedMessage : message) {
                if capturing {
                    Button("기준 잡기") { monitor.startCalibration() }
                        .buttonStyle(FilledButtonStyle(large: true))
                        .disabled(monitor.isCalibrating)
                }
            }
            if done {
                ModalDialog(title: "기준 저장 완료",
                            message: "이제 이 자세를 기준으로 살펴볼게요.\n기준은 메뉴 막대에서 언제든 다시 잡을 수 있어요.",
                            confirm: "시작하기",
                            onConfirm: close)
            }
        }
        .task {
            // Opens only the camera; without detection nothing is scored or accumulated
            monitor.setPreview(true)
            await monitor.openCamera()
        }
        .onChange(of: monitor.calibration) { _, status in
            if status == .failed {
                failed = true
            } else if status == .saved {
                failed = false
                done = true
            }
        }
    }

    private var message: String {
        capturing
            ? "지금 자세가 앞으로 교정할 기준이 돼요. 버튼을 누르는 순간의 위치가 저장돼요."
            : "두 눈·코·입에 점이 모두 찍히면 다음 단계로 넘어가요."
    }
}

// Live camera image with the detected face drawn on top, mirrored like a looking glass
private struct CameraPreview: View {
    let monitor: PostureMonitor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.grey100
                // The layer needs a configured session so its mirroring can be set
                if monitor.camera == .running {
                    PreviewLayerView(session: monitor.session)
                    if let marks = monitor.faceMarks {
                        FaceMarksView(marks: marks, size: geometry.size)
                    }
                }
            }
        }
        .clipped()
    }
}

// Shows frames straight from the shared session; nothing is copied or stored
private struct PreviewLayerView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        let view = NSView()
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct FaceMarksView: View {
    let marks: FaceMarks
    let size: CGSize

    var body: some View {
        let color = marks.hasPitch ? Color.main3 : .main2
        let box = rect(marks.box)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color, lineWidth: 2)
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
            ForEach(Array(marks.points.compactMap { $0 }.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .position(place(point))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // Maps a normalized frame point through aspect-fill scaling, mirrored to match the video
    private func place(_ point: CGPoint) -> CGPoint {
        let frame = marks.frameSize
        let scale = max(size.width / frame.width, size.height / frame.height)
        let originX = (size.width - frame.width * scale) / 2
        let originY = (size.height - frame.height * scale) / 2
        return CGPoint(x: originX + (1 - point.x) * frame.width * scale,
                       y: originY + point.y * frame.height * scale)
    }

    private func rect(_ box: CGRect) -> CGRect {
        let a = place(CGPoint(x: box.minX, y: box.minY))
        let b = place(CGPoint(x: box.maxX, y: box.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
