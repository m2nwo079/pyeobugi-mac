import AVFoundation
import Observation
import PostureCore

@Observable
final class PostureMonitor {
    enum CameraStatus {
        case idle, running, denied, unavailable
    }

    enum CalibrationStatus: Equatable {
        case idle, collecting(remainingSeconds: Int), failed, saved
    }

    private static let baselineKey = "baseline"

    private(set) var camera = CameraStatus.idle
    private(set) var feedback = PostureFeedback.initial
    private(set) var calibration = CalibrationStatus.idle
    private(set) var baseline: Baseline?

    @ObservationIgnored private var engine = EngineState.initial
    @ObservationIgnored private var calibrationStart: TimeInterval?
    @ObservationIgnored private var calibrationSamples: [Sample] = []
    @ObservationIgnored private var capture: FaceCapture!

    var isRunning: Bool { camera == .running }

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
        capture = FaceCapture { [weak self] sample in
            self?.ingest(sample)
        }
    }

    func toggleDetection() async {
        if isRunning {
            stop()
        } else {
            await start()
        }
    }

    func start() async {
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
        camera = await capture.start() ? .running : .unavailable
    }

    func stop() {
        capture.stop()
        camera = .idle
        finishCalibration(.idle)
        engine = .initial
        feedback = updateFeedback(feedback, engine: engine, at: FaceCapture.now(), calibrated: baseline != nil, transitions: [])
    }

    func startCalibration() {
        guard isRunning else { return }
        let start = FaceCapture.now()
        calibrationStart = start
        calibrationSamples = []
        if case .collecting(let remaining) = evaluateCalibration([], startedAt: start) {
            calibration = .collecting(remainingSeconds: remaining)
        }
        // Take the first calibration sample right away instead of waiting out the current interval
        capture.scheduleNext(at: start)
    }

    private func ingest(_ sample: Sample) {
        guard isRunning else { return }
        var (state, transitions) = stepEngine(engine, sample: sample, baseline: baseline)

        if let start = calibrationStart {
            calibrationSamples.append(sample)
            switch evaluateCalibration(calibrationSamples, startedAt: start) {
            case .collecting(let remaining):
                calibration = .collecting(remainingSeconds: remaining)
            case .failed:
                finishCalibration(.failed)
            case .complete(let newBaseline):
                baseline = newBaseline
                UserDefaults.standard.set([newBaseline.pitch, newBaseline.size], forKey: Self.baselineKey)
                let reset = resetPosture(state, at: sample.at)
                state = reset.state
                transitions += reset.transitions
                finishCalibration(.saved)
            }
        }

        engine = state
        feedback = updateFeedback(feedback, engine: engine, at: sample.at, calibrated: baseline != nil, transitions: transitions)
        // Calibration needs at least six valid samples in five seconds, which the idle 1 Hz rate cannot guarantee
        let interval = calibrationStart == nil ? nextInterval(engine, now: sample.at) : Timing.pendingInterval
        capture.scheduleNext(at: sample.at + interval)
    }

    private func finishCalibration(_ status: CalibrationStatus) {
        calibrationStart = nil
        calibrationSamples = []
        calibration = status
    }

    private static func loadBaseline() -> Baseline? {
        guard let values = UserDefaults.standard.array(forKey: baselineKey) as? [Double], values.count == 2 else {
            return nil
        }
        return Baseline(pitch: values[0], size: values[1])
    }
}
