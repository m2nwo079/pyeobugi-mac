import AVFoundation
import PostureCore
import Vision
import os

// Session work and Vision run on `queue`; the only shared state is the lock-protected detection gate
nonisolated final class FaceCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "capture")
    // Earliest time the next frame may go to Vision; infinity while a detection is in flight
    private let nextDetectionAt = OSAllocatedUnfairLock<TimeInterval>(initialState: 0)
    private let onSample: @MainActor @Sendable (Sample) -> Void

    init(onSample: @escaping @MainActor @Sendable (Sample) -> Void) {
        self.onSample = onSample
    }

    // Monotonic seconds that keep counting while the Mac sleeps, so face-loss timing survives sleep
    static func now() -> TimeInterval {
        Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    func start() async -> Bool {
        nextDetectionAt.withLock { $0 = 0 }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard !session.inputs.isEmpty || configure() else {
                    continuation.resume(returning: false)
                    return
                }
                session.startRunning()
                continuation.resume(returning: true)
            }
        }
    }

    func stop() {
        queue.async { [self] in session.stopRunning() }
    }

    func scheduleNext(at time: TimeInterval) {
        nextDetectionAt.withLock { $0 = time }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        let output = AVCaptureVideoDataOutput()
        session.beginConfiguration()
        session.sessionPreset = .medium
        session.addInput(input)
        output.setSampleBufferDelegate(self, queue: queue)
        let added = session.canAddOutput(output)
        if added { session.addOutput(output) }
        session.commitConfiguration()
        return added
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = Self.now()
        let due = nextDetectionAt.withLock { next -> Bool in
            guard now >= next else { return false }
            next = .infinity
            return true
        }
        guard due else { return }
        // A missing face is still delivered so the engine can time out presence and the gate is reopened
        let sample = Sample(at: now, face: Self.detectFace(in: pixelBuffer))
        Task { @MainActor [onSample] in
            onSample(sample)
        }
    }

    private static func detectFace(in pixelBuffer: CVPixelBuffer) -> FaceSample? {
        let request = VNDetectFaceRectanglesRequest()
        // Revision 3 is required for pitch
        request.revision = VNDetectFaceRectanglesRequestRevision3
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              // The largest face is the person sitting at the screen
              let face = request.results?.max(by: { $0.boundingBox.height < $1.boundingBox.height }),
              let pitch = face.pitch else { return nil }
        // Vision reports radians
        return FaceSample(pitch: pitch.doubleValue * 180 / .pi, size: face.boundingBox.height)
    }
}
