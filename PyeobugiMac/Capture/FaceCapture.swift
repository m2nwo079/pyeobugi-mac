import AVFoundation
import PostureCore
import Vision
import os

// Vision face geometry for the calibration preview: normalized, top-left origin, unmirrored frame coordinates
nonisolated struct FaceMarks: Sendable {
    var box: CGRect
    // Centers of the left eye, right eye, nose and mouth, in that order; nil where Vision found no region
    var points: [CGPoint?]
    // Frame time the face was last seen, and the last frame time it came with a pitch
    var at: TimeInterval
    var pitchAt: TimeInterval?
    // Frame size in pixels, needed to map marks through aspect-fill scaling
    var frameSize: CGSize

    var hasPitch: Bool { pitchAt != nil }

    // Eases toward a newer detection with a time-based exponential filter, so the drawing does not jump
    // with per-frame noise. A pitch seen within `holdTime` is kept so the capture button does not blink.
    func smoothed(toward next: FaceMarks, timeConstant: TimeInterval, holdTime: TimeInterval) -> FaceMarks {
        let elapsed = next.at - at
        func blend(_ old: CGFloat, _ new: CGFloat) -> CGFloat {
            CGFloat(smoothSignal(Double(old), Double(new), elapsed: elapsed, timeConstant: timeConstant))
        }
        func blend(_ old: CGPoint?, _ new: CGPoint?) -> CGPoint? {
            guard let new else { return old }
            guard let old else { return new }
            return CGPoint(x: blend(old.x, new.x), y: blend(old.y, new.y))
        }
        let keptPitch = pitchAt.flatMap { next.at - $0 <= holdTime ? $0 : nil }
        return FaceMarks(
            box: CGRect(x: blend(box.minX, next.box.minX), y: blend(box.minY, next.box.minY),
                        width: blend(box.width, next.box.width), height: blend(box.height, next.box.height)),
            points: zip(points, next.points).map { blend($0, $1) },
            at: next.at,
            pitchAt: next.pitchAt ?? keptPitch,
            frameSize: next.frameSize
        )
    }
}

// Session work and Vision run on `queue`; the only shared state is the lock-protected detection gate
nonisolated final class FaceCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "capture")
    // Earliest time the next frame may go to Vision; infinity while a detection is in flight
    private let nextDetectionAt = OSAllocatedUnfairLock<TimeInterval>(initialState: 0)
    // While on, every frame yields face marks, independent of the detection gate
    private let previewEnabled = OSAllocatedUnfairLock(initialState: false)
    private let onSample: @MainActor @Sendable (Sample) -> Void
    // Frame time and the face found in it, if any
    private let onMarks: @MainActor @Sendable (TimeInterval, FaceMarks?) -> Void

    init(onSample: @escaping @MainActor @Sendable (Sample) -> Void,
         onMarks: @escaping @MainActor @Sendable (TimeInterval, FaceMarks?) -> Void) {
        self.onSample = onSample
        self.onMarks = onMarks
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

    func setPreview(_ enabled: Bool) {
        previewEnabled.withLock { $0 = enabled }
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
        let preview = previewEnabled.withLock { $0 }
        guard due || preview else { return }
        let face = Self.largestFace(in: pixelBuffer)
        if due {
            // A missing face is still delivered so the engine can time out presence and the gate is reopened
            let sample = Sample(at: now, face: face.flatMap(Self.faceSample))
            Task { @MainActor [onSample] in
                onSample(sample)
            }
        }
        if preview {
            let marks = face.map { Self.marks(for: $0, in: pixelBuffer, at: now) }
            Task { @MainActor [onMarks] in
                onMarks(now, marks)
            }
        }
    }

    private static func largestFace(in pixelBuffer: CVPixelBuffer) -> VNFaceObservation? {
        let request = VNDetectFaceRectanglesRequest()
        // Revision 3 is required for pitch
        request.revision = VNDetectFaceRectanglesRequestRevision3
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        guard (try? handler.perform([request])) != nil else { return nil }
        // The largest face is the person sitting at the screen
        return request.results?.max(by: { $0.boundingBox.height < $1.boundingBox.height })
    }

    private static func faceSample(_ face: VNFaceObservation) -> FaceSample? {
        guard let pitch = face.pitch else { return nil }
        // Vision reports radians
        return FaceSample(pitch: pitch.doubleValue * 180 / .pi, size: face.boundingBox.height)
    }

    private static func marks(for face: VNFaceObservation, in pixelBuffer: CVPixelBuffer, at time: TimeInterval) -> FaceMarks {
        let request = VNDetectFaceLandmarksRequest()
        request.inputFaceObservations = [face]
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])
        let landmarks = request.results?.first?.landmarks
        let regions = [landmarks?.leftEye, landmarks?.rightEye, landmarks?.nose, landmarks?.outerLips]
        // Vision uses a bottom-left origin; landmark points are relative to the face box
        let box = face.boundingBox
        let points = regions.map { region -> CGPoint? in
            guard let region, region.pointCount > 0 else { return nil }
            let sum = region.normalizedPoints.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let count = CGFloat(region.pointCount)
            return CGPoint(x: box.minX + sum.x / count * box.width,
                           y: 1 - (box.minY + sum.y / count * box.height))
        }
        return FaceMarks(
            box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height),
            points: points,
            at: time,
            pitchAt: face.pitch != nil ? time : nil,
            frameSize: CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        )
    }
}
