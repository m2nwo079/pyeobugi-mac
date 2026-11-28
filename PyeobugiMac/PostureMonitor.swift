import AVFoundation
import Observation
import PostureCore
import os

@Observable
final class PostureMonitor {
    enum CameraStatus {
        // unavailable: no camera is connected; failed: a camera exists but could not be opened
        case idle, running, denied, unavailable, failed
    }

    enum CalibrationStatus: Equatable {
        case idle, collecting(remainingSeconds: Int), failed, saved
    }

    private static let baselineKey = "baseline"
    private static let onboardedKey = "onboarded"
    // Preview drawing: exponential smoothing time constant, and how long a lost face stays drawn
    private static let previewSmoothingTime: TimeInterval = 0.15
    private static let previewHoldTime: TimeInterval = 0.3
    // Only counts, face presence and outcomes are logged; never pitch, size or coordinates
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PyeobugiMac", category: "calibration")
    // Reaction timing only: when posture events happen on the FaceCapture clock, never pitch, size or score
    static let postureLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PyeobugiMac", category: "posture")

    static var isOnboarded: Bool { UserDefaults.standard.bool(forKey: onboardedKey) }

    private(set) var camera = CameraStatus.idle
    // The camera can be open for the calibration screen without detection; only detection scores posture
    private(set) var isDetecting = false
    private(set) var faceMarks: FaceMarks?
    private(set) var feedback = PostureFeedback.initial
    private(set) var calibration = CalibrationStatus.idle
    private(set) var baseline: Baseline?
    // Sitting distance compared with the baseline; read by polling, so not observed
    @ObservationIgnored private(set) var distance = DistanceState.initial

    @ObservationIgnored private var engine = EngineState.initial
    @ObservationIgnored private var calibrationRun: CalibrationRun?
    // Ends the attempt at its deadline when samples stop arriving
    @ObservationIgnored private var calibrationWatch: Task<Void, Never>?
    @ObservationIgnored private var capture: FaceCapture!
    @ObservationIgnored private var isPreviewing = false
    // True while a window that uses the camera is open
    @ObservationIgnored private var isCameraHeld = false

    var session: AVCaptureSession { capture.session }

    // When the score first crossed the entry line; nil once confirmed, because the engine then reuses the field for recovery
    var candidateSince: TimeInterval? { engine.bad ? nil : engine.pendingSince }

    var isCalibrating: Bool {
        if case .collecting = calibration { return true }
        return false
    }

    init() {
        baseline = Self.loadBaseline()
        if [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video)) {
            camera = .denied
        }
        capture = FaceCapture(
            onSample: { [weak self] sample in self?.ingest(sample) },
            onMarks: { [weak self] time, marks in self?.receive(marks, at: time) }
        )
    }

    func toggleDetection() async {
        if isDetecting {
            stop()
        } else {
            await start()
        }
    }

    func start() async {
        await openCameraDevice()
        guard camera == .running else { return }
        isDetecting = true
        capture.scheduleNext(at: FaceCapture.now())
    }

    func stop() {
        isDetecting = false
        engine = .initial
        distance = .initial
        feedback = updateFeedback(feedback, engine: engine, at: FaceCapture.now(), calibrated: baseline != nil, transitions: [])
        closeCameraIfUnused()
    }

    // Opens the camera for a window without starting detection, so nothing is scored or accumulated.
    // Opening can outlast the window (for example during the permission prompt), so the camera is
    // closed again right away if the window was closed in the meantime and detection is off.
    func openCamera() async {
        await openCameraDevice()
        closeCameraIfUnused()
    }

    // Releasing the camera turns the preview off and closes the camera unless detection is using it
    func holdCamera(_ held: Bool) {
        isCameraHeld = held
        guard !held else { return }
        setPreview(false)
        closeCameraIfUnused()
    }

    func setPreview(_ enabled: Bool) {
        isPreviewing = enabled
        capture.setPreview(enabled)
        if !enabled { faceMarks = nil }
    }

    private func openCameraDevice() async {
        guard camera != .running else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                camera = .denied
                return
            }
        default:
            camera = .denied
            return
        }
        if await capture.start() {
            camera = .running
        } else {
            camera = AVCaptureDevice.default(for: .video) == nil ? .unavailable : .failed
        }
    }

    // An attempt in progress is never restarted; it runs until it completes or fails
    func startCalibration() {
        guard camera == .running, calibrationRun == nil else {
            Self.log.debug("Calibration start ignored (camera running: \(self.camera == .running, privacy: .public), in progress: \(self.calibrationRun != nil, privacy: .public))")
            return
        }
        let run = CalibrationRun(startedAt: FaceCapture.now())
        calibrationRun = run
        Self.log.debug("Calibration started (detecting: \(self.isDetecting, privacy: .public))")
        apply(run.evaluate(at: run.startedAt))
        // Take the first calibration sample right away instead of waiting out the current interval
        capture.scheduleNext(at: run.startedAt)
        watchCalibration()
    }

    private func watchCalibration() {
        calibrationWatch?.cancel()
        calibrationWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let run = self.calibrationRun else { return }
                let wait = run.deadline - FaceCapture.now()
                if wait >= 0 {
                    // A sample may move the deadline while this sleeps, so it is re-read on wake
                    try? await Task.sleep(for: .seconds(wait + 0.05))
                    continue
                }
                self.apply(run.evaluate(at: FaceCapture.now()))
            }
        }
    }

    private func apply(_ verdict: CalibrationVerdict) {
        switch verdict.result {
        case .collecting(let remaining):
            Self.log.debug("Calibration collecting (\(remaining, privacy: .public) s left)")
            calibration = .collecting(remainingSeconds: remaining)
        case .failed:
            Self.log.debug("Calibration failed: \(verdict.failure?.rawValue ?? "unknown", privacy: .public)")
            finishCalibration(.failed)
        case .complete(let newBaseline):
            Self.log.debug("Calibration complete")
            baseline = newBaseline
            UserDefaults.standard.set([newBaseline.pitch, newBaseline.size], forKey: Self.baselineKey)
            UserDefaults.standard.set(true, forKey: Self.onboardedKey)
            finishCalibration(.saved)
        }
    }

    private func receive(_ marks: FaceMarks?, at time: TimeInterval) {
        guard isPreviewing else { return }
        guard let marks else {
            // A briefly lost face stays drawn so a dropped frame does not blink
            if let shown = faceMarks, time - shown.at > Self.previewHoldTime { faceMarks = nil }
            return
        }
        guard let shown = faceMarks else {
            faceMarks = marks
            return
        }
        faceMarks = shown.smoothed(toward: marks, timeConstant: Self.previewSmoothingTime, holdTime: Self.previewHoldTime)
    }

    private func closeCameraIfUnused() {
        guard !isDetecting, !isCameraHeld, camera == .running else { return }
        capture.stop()
        camera = .idle
        finishCalibration(.idle)
    }

    private func ingest(_ sample: Sample) {
        guard camera == .running else { return }
        var (state, transitions) = isDetecting ? stepEngine(engine, sample: sample, baseline: baseline) : (state: engine, transitions: [])

        if var run = calibrationRun {
            let verdict = run.add(sample)
            calibrationRun = run
            Self.log.debug("Calibration sample \(run.samples.count, privacy: .public) (face: \(sample.face != nil, privacy: .public))")
            if case .complete = verdict.result, isDetecting {
                let reset = resetPosture(state, at: sample.at)
                state = reset.state
                transitions += reset.transitions
            }
            apply(verdict)
        }

        if isDetecting {
            logReaction(from: engine, to: state, transitions: transitions)
            engine = state
            distance = stepDistance(distance, at: sample.at, size: sample.face?.size, baseline: baseline)
            feedback = updateFeedback(feedback, engine: engine, at: sample.at, calibrated: baseline != nil, transitions: transitions)
        }
        // nil leaves the gate closed until detection or calibration starts
        if let next = nextDetection(engine, at: sample.at, detecting: isDetecting, calibrating: calibrationRun != nil) {
            capture.scheduleNext(at: next)
        }
    }

    private func logReaction(from old: EngineState, to new: EngineState, transitions: [Transition]) {
        let now = FaceCapture.now()
        // The score crossing the entry line and the candidate start are the same sample
        if !old.bad, old.pendingSince == nil, !new.bad, let since = new.pendingSince {
            Self.postureLog.debug("candidate started t=\(since, format: .fixed(precision: 3), privacy: .public) handled=\(now, format: .fixed(precision: 3), privacy: .public)")
        }
        for case let .badEnter(at, _) in transitions {
            Self.postureLog.debug("bad confirmed t=\(now, format: .fixed(precision: 3), privacy: .public) +\(now - at, format: .fixed(precision: 3), privacy: .public)s from candidate")
        }
    }

    private func finishCalibration(_ status: CalibrationStatus) {
        if calibrationRun != nil, status == .idle {
            Self.log.debug("Calibration cancelled because the camera closed")
        }
        calibrationRun = nil
        calibrationWatch?.cancel()
        calibrationWatch = nil
        calibration = status
    }

    private static func loadBaseline() -> Baseline? {
        guard let values = UserDefaults.standard.array(forKey: baselineKey) as? [Double], values.count == 2 else {
            return nil
        }
        return Baseline(pitch: values[0], size: values[1])
    }
}
