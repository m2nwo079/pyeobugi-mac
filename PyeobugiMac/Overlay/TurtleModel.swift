import SwiftUI
import os

// MARK: - Constants (durations in seconds)

enum TurtleSize {
    static let maximum: CGFloat = 120
    static let minimum: CGFloat = 80
    // The turtle is never wider than this fraction of the screen width or height
    static let screenFraction: CGFloat = 0.3
    // Feet stand this far above the bottom of the visible frame
    static let groundInset: CGFloat = 8
    // Feet sit at this fraction of the drawing box height
    static let footLine: CGFloat = 0.8
}

enum TurtleLife {
    static let startDelay: TimeInterval = 0.9
    // How often a nap checks whether the neck needs to grow
    static let napPoll: TimeInterval = 0.04
    // One roll per loop: below shakeChance while facing front shakes the head,
    // below faceFrontChance while facing elsewhere turns to the front, anything else walks
    static let shakeChance = 0.14
    static let faceFrontChance = 0.32
    static let shakeAfterFacingFrontChance = 0.4
    static let restAfterShake: ClosedRange<TimeInterval> = 0.7...1.6
    static let restAfterFacingFront: ClosedRange<TimeInterval> = 0.9...1.6
    static let restAfterFrontShake: ClosedRange<TimeInterval> = 0.6...1.2
    static let restAfterFrontOnly: ClosedRange<TimeInterval> = 0.5...1.2
    static let restAfterWalk: ClosedRange<TimeInterval> = 0.6...2.2
    static let restAfterNeck: TimeInterval = 0.7
}

enum TurtleWalk {
    // Turtle sizes per second, constant from start to stop
    static let speed: CGFloat = 0.55
    static let sidewaysChance = 0.45
    // Radians around straight left or right
    static let sidewaysSpread = 0.3
    // In turtle sizes
    static let distance: ClosedRange<CGFloat> = 0.8...2.4
    static let minimumDistance: CGFloat = 0.6
    static let targetAttempts = 20
    // How often a walk checks whether it has to stop
    static let checkInterval: TimeInterval = 1.0 / 60
}

enum TurtleTurn {
    // Time spent on each of the eight headings passed through
    static let step: TimeInterval = 0.085
    // The first heading changes this long after the hop starts
    static let lead: TimeInterval = 0.05
    // The hop lasts step * headings + trail
    static let trail: TimeInterval = 0.08
    // When the target is exactly opposite, chance of turning through the front
    static let viaFrontChance = 0.75
}

enum TurtleShake {
    static let afterTurn: TimeInterval = 0.22
    static let beforeClosing: TimeInterval = 0.12
    static let closing: TimeInterval = 0.09
    static let beforeShake: TimeInterval = 0.14
    static let duration: TimeInterval = 0.95
    static let beforeOpening: TimeInterval = 0.18
    static let opening: TimeInterval = 0.02
}

enum TurtleEyes {
    static let blinkPeriod: TimeInterval = 5.3
    // Lids move between open and nearly shut over this time
    static let lidTransition: TimeInterval = 0.09
    static let shutHeight = 0.1
}

enum TurtleMotion {
    static let breathePeriod: TimeInterval = 3.2
    static let idleWagPeriod: TimeInterval = 3.2
    static let waddlePeriod: TimeInterval = 0.9
    // Back legs run half a step behind the front legs
    static let legPhase: TimeInterval = 0.45
    // Tail wag and head nod swing back and forth once per period while walking
    static let walkSwingPeriod: TimeInterval = 0.45
}

enum NeckStretch {
    // One full extension in drawing units (a drawing is TurtleArt.units wide); neck ratio 1 equals this
    static let full = 1056.0
    static let wantedThreshold = 0.01
    static let afterTurn: TimeInterval = 0.15
    static let enterSquash = 0.93
    static let enterSquashDuration: TimeInterval = 0.32
    static let exitSquash = 0.94
    static let exitSquashDuration: TimeInterval = 0.26
    // Shrinking takes exitBase + exitPerUnit * length, at most exitMax
    static let exitBase: TimeInterval = 0.55
    static let exitPerUnit: TimeInterval = 0.00012
    static let exitMax: TimeInterval = 1.5
    static let settle: TimeInterval = 0.3
    // Spring toward the target length, stepped springRate times per second
    static let springRate = 60.0
    static let springStiffness = 0.03
    static let springDamping = 0.78
    static let snapDistance = 0.3
    static let snapVelocity = 0.05
    // Steps replayed at most after a stall such as system sleep
    static let springCatchUp = 6
    // The head changes from resting to stretched between these lengths
    static let morphStart = 10.0
    static let morphSpan = 40.0
    // Neck width at rest relative to full extension
    static let restWidth = 0.85
    // Wrapped columns run this far past the screen edges, and each tube overlaps the next by tubePad
    static let overshoot = 40.0
    static let tubePad = 6.0
    // Column layout: start from columns tightGap apart, then widen the gap by gapGrowth
    static let columnMargin = 4.0
    static let tightGap = 12.0
    static let gapGrowth = 2.0
    // Columns closer than this many pitches to the body's own neck are skipped
    static let rootClearance = 0.9
}

// MARK: - Headings and looks

// Eight headings in turning order; right-hand headings mirror the left-hand drawings
enum TurtleHeading: Int {
    case left, frontLeft, front, frontRight, right, backRight, back, backLeft

    var look: TurtleLook {
        switch self {
        case .left, .right: .side
        case .frontLeft, .frontRight: .frontLeft
        case .front: .front
        case .back: .back
        case .backLeft, .backRight: .backLeft
        }
    }

    var isFlipped: Bool {
        self == .right || self == .frontRight || self == .backRight
    }
}

enum TurtleLook {
    case side, front, back, frontLeft, backLeft, long
}

// MARK: - Keyframes

extension UnitCurve {
    // cubic-bezier(0.25, 0.1, 0.25, 1)
    static let easeCurve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.25, y: 0.1), endControlPoint: UnitPoint(x: 0.25, y: 1))
    // cubic-bezier(0.42, 0, 0.58, 1)
    static let easeInOutCurve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.42, y: 0), endControlPoint: UnitPoint(x: 0.58, y: 1))
    // cubic-bezier(0, 0, 0.58, 1)
    static let easeOutCurve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0, y: 0), endControlPoint: UnitPoint(x: 0.58, y: 1))
    static let shakeCurve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.3, y: 0.6), endControlPoint: UnitPoint(x: 0.4, y: 1))
    static let waddleDown = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.3, y: 0), endControlPoint: UnitPoint(x: 0.6, y: 1))
    static let waddleUp = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.4, y: 0), endControlPoint: UnitPoint(x: 0.7, y: 1))
}

struct Keyframes {
    struct Stop {
        var offset: Double
        var values: [Double]
        // Easing for the segment that starts at this stop
        var curve: UnitCurve
    }

    var stops: [Stop]

    init(_ stops: [(Double, [Double])], curve: UnitCurve = .linear) {
        self.stops = stops.map { Stop(offset: $0.0, values: $0.1, curve: curve) }
    }

    init(stops: [Stop]) {
        self.stops = stops
    }

    func values(at progress: Double) -> [Double] {
        let p = min(1, max(0, progress))
        guard let i = stops.lastIndex(where: { $0.offset <= p }), i + 1 < stops.count else {
            return stops[stops.count - 1].values
        }
        let a = stops[i], b = stops[i + 1]
        let u = a.curve.value(at: (p - a.offset) / (b.offset - a.offset))
        return zip(a.values, b.values).map { $0 + ($1 - $0) * u }
    }
}

enum TurtleKeyframes {
    // Scale x, scale y
    static let breathe = Keyframes([(0, [1, 1]), (0.5, [1.012, 1.03]), (1, [1, 1])], curve: .easeInOutCurve)
    // Lift (pt), tilt (degrees)
    static let waddle = Keyframes(stops: [
        .init(offset: 0, values: [0, -2], curve: .waddleDown),
        .init(offset: 0.25, values: [-6, 0], curve: .waddleUp),
        .init(offset: 0.5, values: [0, 2], curve: .waddleDown),
        .init(offset: 0.75, values: [-6, 0], curve: .waddleUp),
        .init(offset: 1, values: [0, -2], curve: .linear),
    ])
    // Leg angle (degrees), lift (drawing units)
    static let step = Keyframes([(0, [-11, 0]), (0.25, [0, -7]), (0.5, [11, 0]), (0.75, [0, 0]), (1, [-11, 0])], curve: .easeInOutCurve)
    // Tail angle (degrees)
    static let wag = Keyframes([(0, [-8]), (1, [8])], curve: .easeInOutCurve)
    // Head angle (degrees), lift (drawing units)
    static let nod = Keyframes([(0, [-1.5, 0]), (1, [1.5, -3])], curve: .easeInOutCurve)
    // Eye height
    static let blink = Keyframes([(0, [1]), (0.46, [1]), (0.475, [0.08]), (0.49, [1]), (1, [1])], curve: .easeCurve)
    // Head angle (degrees), sideways shift (drawing units)
    static let shake = Keyframes([
        (0, [0, 0]), (0.1, [-10, -7]), (0.24, [10, 7]), (0.38, [-8, -5]),
        (0.52, [6, 4]), (0.66, [-3.5, -2]), (0.8, [1.5, 1]), (1, [0, 0]),
    ], curve: .shakeCurve)
    // Body angle (degrees)
    static let jiggle = Keyframes([
        (0, [0]), (0.12, [1.6]), (0.26, [-1.6]), (0.4, [1.1]), (0.54, [-0.8]), (0.7, [0.3]), (1, [0]),
    ], curve: .easeOutCurve)

    // Lift (pt), scale x, scale y. The squat and the rebound keep fixed lengths however long the turn is
    static func turnHop(duration: TimeInterval) -> Keyframes {
        Keyframes([
            (0, [0, 1, 1]),
            (min(0.4, 0.09 / duration), [2, 1.04, 0.94]),
            (max(0.6, 1 - 0.12 / duration), [-3, 0.99, 1.02]),
            (1, [0, 1, 1]),
        ])
    }

    static func squash(height: Double) -> Keyframes {
        Keyframes([(0, [0, 1, 1]), (0.5, [2, 2 - height, height]), (1, [0, 1, 1])])
    }
}

// MARK: - Render state

struct LegPose {
    var angle = 0.0
    var lift = 0.0
}

// Neck pieces in long view coordinates
struct NeckTube: Equatable {
    var x: Double
    var top: Double
    var bottom: Double
}

struct NeckLayout: Equatable {
    // Below one full extension the resting neck curve is pulled down by `drop` and the head moves with it
    var extended = false
    var drop = 0.0
    // Head shape from resting (0) to stretched (1)
    var morph = 1.0
    var front: [NeckTube] = []
    var back: [NeckTube] = []
    // Offsets of each head from where it sits at one full extension
    var frontHeads: [CGPoint] = []
    var backHeads: [CGPoint] = []
}

// Everything the view needs for one frame. Offsets are in points unless noted
struct TurtleFrame {
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var look: TurtleLook
    var flipped: Bool
    var hopOffset = 0.0
    var hopScale = CGSize(width: 1, height: 1)
    var bobOffset = 0.0
    var bobAngle = 0.0
    var bobScale = CGSize(width: 1, height: 1)
    // Inner parts: angles in degrees, distances in drawing units
    var tailAngle = 0.0
    var frontLeg = LegPose()
    var backLeg = LegPose()
    var headAngle = 0.0
    var headLift = 0.0
    var headShift = 0.0
    var eyeOpen = 1.0
    var eyesClosed = false
    var neck: NeckLayout?
    // Whole-figure turn around the feet in radians, while held or falling
    var tilt = 0.0
}

// MARK: - Model

@Observable
final class TurtleModel {
    private enum Pose {
        case idle, walk, long, held, falling
    }

    private enum Phase {
        case normal, entering, long, exiting
    }

    private struct Walk {
        var from: CGFloat
        var to: CGFloat
        var start: TimeInterval
        var duration: TimeInterval

        func x(at t: TimeInterval) -> CGFloat {
            guard duration > 0 else { return to }
            return from + (to - from) * CGFloat(min(1, max(0, (t - start) / duration)))
        }
    }

    private struct Hop {
        var start: TimeInterval
        var duration: TimeInterval
        var frames: Keyframes
        var curve = UnitCurve.easeInOutCurve
    }

    private struct NeckExit {
        var from: Double
        var start: TimeInterval
        var duration: TimeInterval
    }

    // Wrapped neck columns in drawing units, fixed when the neck starts to grow
    private struct Columns {
        var top: Double
        var bottom: Double
        var order: [Double]

        var height: Double { bottom - top }

        func x(_ index: Int) -> Double {
            order[(index - 1) % order.count]
        }
    }

    let reduceMotion: Bool

    private var screen = CGSize.zero
    private var size: CGFloat = 0
    private var x: CGFloat = 0
    private var heading = TurtleHeading.front
    private var longView = false
    private var pose = Pose.idle
    private var poseSince: TimeInterval
    private var walk: Walk?
    private var hop: Hop?
    private var shakeSince: TimeInterval?
    private var eyesClosing = false
    private var eyesClosingSince = -TimeInterval.infinity
    private var eyesClosed = false
    private var neck = 0.0
    private var neckExit: NeckExit?
    private var columns: Columns?
    // In the hand, in the air, or just landed and not grabbable yet
    private var airborne = false

    @ObservationIgnored let blinkOrigin: TimeInterval
    @ObservationIgnored private var phase = Phase.normal
    @ObservationIgnored private var longRequested = false
    @ObservationIgnored private var unlongRequested = false
    @ObservationIgnored private var neckWanted = 0.0
    @ObservationIgnored private var neckTarget = 0.0
    @ObservationIgnored private var neckVelocity = 0.0
    @ObservationIgnored private var springClock: TimeInterval = 0
    @ObservationIgnored private var life: Task<Void, Never>?
    // Physics changes every frame; the view draws it at the full rate, so it is not observed
    @ObservationIgnored private var flight: TurtleFlight?
    @ObservationIgnored private var flailSince: TimeInterval = 0
    @ObservationIgnored private var landed = false
    @ObservationIgnored private var wanderPausedUntil: TimeInterval = 0

    init(screen: CGSize, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        let now = Self.now()
        poseSince = now
        blinkOrigin = now
        layout(screen)
    }

    static func now() -> TimeInterval {
        Date().timeIntervalSinceReferenceDate
    }

    private var ground: CGFloat { screen.height - TurtleSize.groundInset }

    func start() {
        guard !reduceMotion, life == nil else { return }
        life = Task { await self.runLife() }
    }

    func stop() {
        life?.cancel()
        life = nil
    }

    func layout(_ screen: CGSize) {
        self.screen = screen
        size = max(TurtleSize.minimum, min(TurtleSize.maximum, screen.width * TurtleSize.screenFraction, screen.height * TurtleSize.screenFraction))
        x = clampX(x)
        if longView { columns = makeColumns() }
    }

    // ratio: 0 is resting, 1 is one full extension, above 1 wraps into more columns
    func setNeck(_ ratio: Double) {
        neckWanted = max(0, ratio)
        let wanted = neckWanted > NeckStretch.wantedThreshold
        // Posture feedback wins: the turtle slips out of the hand
        if wanted, pose == .held { endGrab(throwing: false, at: Self.now()) }
        if reduceMotion {
            // No turning and no spring: jump to the nearest side view and show the length directly
            if wanted, !longView {
                heading = nearestSide()
                columns = makeColumns()
                longView = true
                PostureMonitor.postureLog.debug("neck growing t=\(FaceCapture.now(), format: .fixed(precision: 3), privacy: .public)")
            }
            if !wanted, longView {
                longView = false
                neck = 0
            }
            let length = neckWanted * NeckStretch.full
            if wanted, neck != length { neck = length }
            return
        }
        if wanted {
            if phase == .normal { longRequested = true }
            if phase == .long { neckTarget = neckWanted * NeckStretch.full }
        } else if phase == .long || phase == .entering {
            unlongRequested = true
        }
    }

    // MARK: Behaviour loop

    private func runLife() async {
        await nap(TurtleLife.startDelay)
        while !Task.isCancelled {
            if busy {
                await sleep(TurtleGrab.busyPoll)
                continue
            }
            // The neck always wins over the next wandering action
            if longRequested {
                longRequested = false
                await enterLong()
                while !unlongRequested, !Task.isCancelled {
                    await sleep(1 / NeckStretch.springRate)
                    stepSpring()
                }
                unlongRequested = false
                await exitLong()
                await nap(TurtleLife.restAfterNeck)
                continue
            }
            if landed {
                // Shake the fall off
                landed = false
                await shakeHead()
                await nap(.random(in: TurtleFall.restAfterLanding))
                continue
            }
            if Self.now() < wanderPausedUntil {
                await nap(TurtleGrab.pausePoll)
                continue
            }
            let roll = Double.random(in: 0..<1)
            if roll < TurtleLife.shakeChance, heading == .front {
                await shakeHead()
                await nap(.random(in: TurtleLife.restAfterShake))
            } else if roll < TurtleLife.faceFrontChance, heading != .front {
                await turnTo(.front)
                await nap(.random(in: TurtleLife.restAfterFacingFront))
                if Double.random(in: 0..<1) < TurtleLife.shakeAfterFacingFrontChance {
                    await shakeHead()
                    await nap(.random(in: TurtleLife.restAfterFrontShake))
                } else {
                    await nap(.random(in: TurtleLife.restAfterFrontOnly))
                }
            } else {
                await walkTo(pickTarget())
                await nap(.random(in: TurtleLife.restAfterWalk))
            }
        }
    }

    private func sleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(for: .seconds(max(0, seconds)))
    }

    // Rest that ends early when the neck has to grow or the turtle is picked up
    private func nap(_ seconds: TimeInterval) async {
        let end = Self.now() + seconds
        while Self.now() < end, !longRequested, !busy, !Task.isCancelled {
            await sleep(TurtleLife.napPoll)
        }
    }

    private func setPose(_ next: Pose) {
        pose = next
        poseSince = Self.now()
    }

    private func startHop(_ frames: Keyframes, duration: TimeInterval, curve: UnitCurve = .easeInOutCurve) {
        hop = Hop(start: Self.now(), duration: duration, frames: frames, curve: curve)
    }

    private func squash(_ height: Double, duration: TimeInterval) async {
        startHop(TurtleKeyframes.squash(height: height), duration: duration)
        await sleep(duration)
    }

    // MARK: Turning

    private func turnPath(from: TurtleHeading, to: TurtleHeading) -> [TurtleHeading] {
        let a = from.rawValue, b = to.rawValue
        guard a != b else { return [] }
        let forward = (b - a + 8) % 8, backward = (a - b + 8) % 8
        let direction: Int
        if forward != backward {
            direction = forward < backward ? 1 : -1
        } else {
            // Exactly opposite: usually turn through the front so the face shows
            let frontIsForward = (1..<4).contains { TurtleHeading(rawValue: (a + $0) % 8) == .front }
            direction = (Double.random(in: 0..<1) < TurtleTurn.viaFrontChance) == frontIsForward ? 1 : -1
        }
        var path: [TurtleHeading] = []
        var i = a
        while i != b {
            i = (i + direction + 8) % 8
            path.append(TurtleHeading(rawValue: i)!)
        }
        return path
    }

    private func turnTo(_ target: TurtleHeading) async {
        let path = turnPath(from: heading, to: target)
        guard !path.isEmpty else { return }
        let start = Self.now()
        let duration = TurtleTurn.step * Double(path.count) + TurtleTurn.trail
        hop = Hop(start: start, duration: duration, frames: TurtleKeyframes.turnHop(duration: duration))
        await sleep(TurtleTurn.lead)
        for next in path {
            // A grab turns the turtle to the front and ends the turn
            guard !busy else { return }
            heading = next
            await sleep(TurtleTurn.step)
        }
        await sleep(start + duration - Self.now())
    }

    private func nearestSide() -> TurtleHeading {
        let i = heading.rawValue
        let toLeft = min(i, 8 - i), toRight = abs(i - TurtleHeading.right.rawValue)
        if toLeft != toRight { return toLeft < toRight ? .left : .right }
        return Bool.random() ? .left : .right
    }

    // MARK: Walking

    private func clampX(_ value: CGFloat) -> CGFloat {
        let half = size / 2
        return min(screen.width - half, max(half, value))
    }

    private func pickTarget() -> CGFloat {
        for _ in 0..<TurtleWalk.targetAttempts {
            // Mostly sideways; the floor is a single line, so only the horizontal part of the step remains
            let angle = Double.random(in: 0..<1) < TurtleWalk.sidewaysChance
                ? (Bool.random() ? 0 : .pi) + .random(in: -TurtleWalk.sidewaysSpread...TurtleWalk.sidewaysSpread)
                : .random(in: 0...(2 * .pi))
            let length = CGFloat.random(in: TurtleWalk.distance) * size
            let target = clampX(x + CGFloat(cos(angle)) * length)
            if abs(target - x) > size * TurtleWalk.minimumDistance { return target }
        }
        return clampX(screen.width / 2)
    }

    private func walkTo(_ goal: CGFloat) async {
        let target = clampX(goal)
        await turnTo(target < x ? .left : .right)
        guard !longRequested, !busy, !Task.isCancelled else { return }
        let segment = Walk(from: x, to: target, start: Self.now(), duration: abs(target - x) / (size * TurtleWalk.speed))
        walk = segment
        setPose(.walk)
        var reached = target
        while Self.now() < segment.start + segment.duration {
            // A grab has already taken the position and stopped the walk
            if busy { return }
            if longRequested || Task.isCancelled {
                reached = segment.x(at: Self.now())
                break
            }
            await sleep(TurtleWalk.checkInterval)
        }
        if busy { return }
        x = reached
        walk = nil
        setPose(.idle)
    }

    // MARK: Head shake

    private func shakeHead() async {
        if heading != .front {
            await turnTo(.front)
            await sleep(TurtleShake.afterTurn)
        }
        await sleep(TurtleShake.beforeClosing)
        setEyesClosing(true)
        await sleep(TurtleShake.closing)
        eyesClosed = true
        await sleep(TurtleShake.beforeShake)
        shakeSince = Self.now()
        await sleep(TurtleShake.duration)
        shakeSince = nil
        // Breathing starts over, unless the turtle was picked up meanwhile
        if pose == .idle { setPose(.idle) }
        await sleep(TurtleShake.beforeOpening)
        eyesClosed = false
        await sleep(TurtleShake.opening)
        setEyesClosing(false)
    }

    private func setEyesClosing(_ closing: Bool) {
        eyesClosing = closing
        eyesClosingSince = Self.now()
    }

    // MARK: Neck

    private func enterLong() async {
        phase = .entering
        await turnTo(nearestSide())
        await sleep(NeckStretch.afterTurn)
        // Breathing stops so the neck lines up with the screen edges
        setPose(.long)
        longView = true
        neck = 0
        neckVelocity = 0
        columns = makeColumns()
        await squash(NeckStretch.enterSquash, duration: NeckStretch.enterSquashDuration)
        neckTarget = 0
        springClock = Self.now()
        phase = .long
        PostureMonitor.postureLog.debug("neck growing t=\(FaceCapture.now(), format: .fixed(precision: 3), privacy: .public)")
    }

    private func exitLong() async {
        phase = .exiting
        let from = neck
        let duration = min(NeckStretch.exitMax, NeckStretch.exitBase + from * NeckStretch.exitPerUnit)
        neckExit = NeckExit(from: from, start: Self.now(), duration: duration)
        await sleep(duration)
        neckExit = nil
        neck = 0
        neckTarget = 0
        startHop(TurtleKeyframes.squash(height: NeckStretch.exitSquash), duration: NeckStretch.exitSquashDuration)
        longView = false
        setPose(.idle)
        await sleep(NeckStretch.settle)
        phase = .normal
    }

    private func stepSpring() {
        let t = Self.now()
        let due = Int((t - springClock) * NeckStretch.springRate)
        guard due > 0 else { return }
        springClock = due > NeckStretch.springCatchUp ? t : springClock + Double(due) / NeckStretch.springRate
        var length = neck
        for _ in 0..<min(due, NeckStretch.springCatchUp) {
            let diff = neckTarget - length
            neckVelocity = (neckVelocity + diff * NeckStretch.springStiffness) * NeckStretch.springDamping
            length = max(0, length + neckVelocity)
            if abs(diff) < NeckStretch.snapDistance, abs(neckVelocity) < NeckStretch.snapVelocity {
                length = neckTarget
                neckVelocity = 0
            }
        }
        if length != neck { neck = length }
    }

    private func neckLength(at t: TimeInterval) -> Double {
        guard let neckExit else { return neck }
        let k = min(1, max(0, (t - neckExit.start) / neckExit.duration))
        let eased = k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2
        return neckExit.from * (1 - eased)
    }

    // Screen edges in long view coordinates, and the columns the neck climbs after leaving the top
    private func makeColumns() -> Columns {
        let k = Double(size) / TurtleArt.units
        let s: Double = heading.isFlipped ? -1 : 1
        let centre = TurtleArt.units / 2
        let edgeA = centre + (0 - Double(x)) * s / k
        let edgeB = centre + (Double(screen.width) - Double(x)) * s / k
        let left = min(edgeA, edgeB) - TurtleArt.longOffset.width, width = Double(screen.width) / k
        let top = TurtleArt.foot - Double(ground) / k - TurtleArt.longOffset.height
        let bottom = TurtleArt.foot + (Double(screen.height) - Double(ground)) / k - TurtleArt.longOffset.height

        let root = TurtleArt.neckCentre
        let faceReach = root - TurtleArt.faceEdge
        let span = faceReach + (NeckArt.right + TurtleArt.backEdge - root) + NeckStretch.columnMargin
        let tight = max(2, (width / (span + NeckStretch.tightGap)).rounded(.down))
        let gap = (width / tight - span) * NeckStretch.gapGrowth
        let count = max(2, Int(width / (span + gap)))
        let pitch = width / Double(count)
        let offset = faceReach + (pitch - span) / 2
        let clearance = max(pitch * NeckStretch.rootClearance, span)
        let cells: [Double] = (0..<count).map { left + Double($0) * pitch + offset }
        let free = cells.filter { abs($0 - root) >= clearance }
        // Face side first, nearest column outward; past the edge, continue from the far edge inward
        let faceSide: [Double] = free.filter { $0 < root }.sorted(by: >)
        let backSide: [Double] = free.filter { $0 > root }.sorted(by: >)
        var order = faceSide + backSide
        if order.isEmpty { order = [root - pitch] }
        return Columns(top: top, bottom: bottom, order: order)
    }

    private func neckLayout(_ length: Double) -> NeckLayout {
        var layout = NeckLayout()
        guard length >= NeckStretch.full, let columns else {
            // The resting neck curve stretches up from the shell and the head changes shape on the way
            let drop = NeckStretch.full - length
            let p = min(1, max(0, (length - NeckStretch.morphStart) / NeckStretch.morphSpan))
            layout.drop = drop
            layout.morph = p * p * (3 - 2 * p)
            layout.frontHeads = [CGPoint(x: 0, y: drop)]
            return layout
        }

        layout.extended = true
        let root = TurtleArt.neckCentre, base = NeckArt.columnTop
        let past = length - NeckStretch.full
        let first = base - columns.top
        let top = columns.top - NeckStretch.overshoot, bottom = columns.bottom + NeckStretch.overshoot
        // Past the top edge the neck comes back up from the bottom of the next column
        let column: Int, head: Double
        if past <= first {
            column = 0
            head = base - past
        } else {
            let t = past - first
            column = 1 + Int(t / columns.height)
            head = columns.bottom - (t - Double(column - 1) * columns.height)
        }
        layout.front = [NeckTube(x: root, top: column == 0 ? head : top, bottom: base)]
        // Columns passed again keep the earlier tube underneath
        for j in max(1, column - columns.order.count)..<max(1, column) {
            layout.back.append(NeckTube(x: columns.x(j), top: top, bottom: bottom))
        }
        if column >= 1 {
            layout.back.append(NeckTube(x: columns.x(column), top: head, bottom: bottom))
        }
        let lift = head - base
        let headPoint = CGPoint(x: column == 0 ? 0 : columns.x(column) - root, y: lift)
        if column == 0 {
            layout.frontHeads = [headPoint]
        } else {
            layout.backHeads = [headPoint]
        }
        // The part of the head above the top edge shows at the bottom of the following column
        if TurtleArt.headTop + lift < columns.top {
            layout.backHeads.append(CGPoint(x: columns.x(column + 1) - root, y: lift + columns.height))
        }
        return layout
    }

    // MARK: Frame

    private func cycle(_ elapsed: TimeInterval, _ period: TimeInterval) -> Double {
        elapsed.truncatingRemainder(dividingBy: period) / period
    }

    // Back and forth: even periods play forward, odd periods backward
    private func swing(_ elapsed: TimeInterval, _ period: TimeInterval) -> Double {
        let p = cycle(elapsed, period)
        return Int((elapsed / period).rounded(.down)) % 2 == 0 ? p : 1 - p
    }

    // Until when something moves faster than breathing and the idle tail: walking, turning, squashing,
    // shaking, eyelids and the neck pulling back. The neck spring redraws on every step by itself
    var fullRateUntil: TimeInterval {
        if walk != nil || shakeSince != nil || neckExit != nil || pose == .held || airborne { return .infinity }
        var end = eyesClosingSince + TurtleEyes.lidTransition
        if let hop { end = max(end, hop.start + hop.duration) }
        return end
    }

    func frame(at t: TimeInterval) -> TurtleFrame {
        let look = longView && heading.look == .side ? TurtleLook.long : heading.look
        var f = TurtleFrame(x: walk?.x(at: t) ?? x, y: ground, size: size, look: look, flipped: heading.isFlipped)
        if let flight {
            f.x = flight.foot.x
            f.y = flight.foot.y
            f.tilt = flight.tilt
        }
        if look == .long {
            f.neck = neckLayout(neckLength(at: t))
        }
        guard !reduceMotion else { return f }

        if let hop {
            let v = hop.frames.values(at: hop.curve.value(at: min(1, max(0, (t - hop.start) / hop.duration))))
            f.hopOffset = v[0]
            f.hopScale = CGSize(width: v[1], height: v[2])
        }

        let elapsed = t - poseSince
        if pose == .held {
            // The hold overrides a head shake still running underneath
            let head = TurtleKeyframes.tremble.values(at: swing(elapsed, TurtleGrab.tremblePeriod))
            f.headAngle = head[0]
            f.headLift = head[1]
        } else if let shakeSince {
            let p = (t - shakeSince) / TurtleShake.duration
            f.bobAngle = TurtleKeyframes.jiggle.values(at: p)[0]
            let head = TurtleKeyframes.shake.values(at: p)
            f.headAngle = head[0]
            f.headShift = head[1]
        } else if pose == .idle {
            let v = TurtleKeyframes.breathe.values(at: cycle(elapsed, TurtleMotion.breathePeriod))
            f.bobScale = CGSize(width: v[0], height: v[1])
        } else if pose == .walk {
            let bob = TurtleKeyframes.waddle.values(at: cycle(elapsed, TurtleMotion.waddlePeriod))
            f.bobOffset = bob[0]
            f.bobAngle = bob[1]
            let front = TurtleKeyframes.step.values(at: cycle(elapsed, TurtleMotion.waddlePeriod))
            let back = TurtleKeyframes.step.values(at: cycle(elapsed + TurtleMotion.legPhase, TurtleMotion.waddlePeriod))
            f.frontLeg = LegPose(angle: front[0], lift: front[1])
            f.backLeg = LegPose(angle: back[0], lift: back[1])
            let nod = TurtleKeyframes.nod.values(at: swing(elapsed, TurtleMotion.walkSwingPeriod))
            f.headAngle = nod[0]
            f.headLift = nod[1]
        }
        if pose == .held || pose == .falling {
            // The flail keeps its clock from the grab; only its period changes on release
            let held = pose == .held
            let period = held ? TurtleGrab.heldFlailPeriod : TurtleGrab.fallingFlailPeriod
            let lead = held ? TurtleGrab.heldFlailLead : TurtleGrab.fallingFlailLead
            let since = t - flailSince
            let front = TurtleKeyframes.flail.values(at: swing(since, period))
            let back = TurtleKeyframes.flail.values(at: swing(since + lead, period))
            f.frontLeg = LegPose(angle: front[0], lift: front[1])
            f.backLeg = LegPose(angle: back[0], lift: back[1])
        } else {
            f.tailAngle = pose == .walk
                ? TurtleKeyframes.wag.values(at: swing(elapsed, TurtleMotion.walkSwingPeriod))[0]
                : TurtleKeyframes.wag.values(at: cycle(elapsed, TurtleMotion.idleWagPeriod))[0]
        }

        let blink = TurtleKeyframes.blink.values(at: cycle(t - blinkOrigin, TurtleEyes.blinkPeriod))[0]
        let lid = UnitCurve.easeInOutCurve.value(at: min(1, max(0, (t - eyesClosingSince) / TurtleEyes.lidTransition)))
        f.eyeOpen = eyesClosing
            ? blink + (TurtleEyes.shutHeight - blink) * lid
            : TurtleEyes.shutHeight + (blink - TurtleEyes.shutHeight) * lid
        // Eyes stay shut in the hand and in the air
        f.eyesClosed = eyesClosed || pose == .held || pose == .falling
        return f
    }

    // MARK: Grab, throw and fall

    private var busy: Bool { pose == .held || airborne }

    var isHeld: Bool { pose == .held }

    // Only on the floor with the neck in and motion allowed
    var canGrab: Bool {
        !reduceMotion && !busy && phase == .normal && !longView
    }

    // Pointer hit box around the feet, in view points
    func contains(_ point: CGPoint, at t: TimeInterval) -> Bool {
        let foot = flight?.foot ?? CGPoint(x: walk?.x(at: t) ?? x, y: ground)
        return abs(point.x - foot.x) <= size * TurtleGrab.hitHalfWidth
            && point.y >= foot.y - size * TurtleGrab.hitAbove
            && point.y <= foot.y + TurtleGrab.hitBelow
    }

    func grab(at pointer: CGPoint, at t: TimeInterval) -> Bool {
        guard canGrab else { return false }
        if let walk { x = walk.x(at: t) }
        walk = nil
        shakeSince = nil
        eyesClosed = false
        if eyesClosing { setEyesClosing(false) }
        landed = false
        // Startled, it faces the front
        heading = .front
        setPose(.held)
        flailSince = t
        startHop(TurtleKeyframes.startle, duration: TurtleGrab.startleDuration, curve: .easeOutCurve)
        flight = TurtleFlight(foot: CGPoint(x: x, y: ground), size: size, pointer: pointer, at: t)
        wanderPausedUntil = t + TurtleGrab.wanderPause
        return true
    }

    func moveGrab(to pointer: CGPoint, at t: TimeInterval) {
        guard pose == .held else { return }
        flight?.move(to: pointer, screen: screen, at: t)
    }

    func release(at t: TimeInterval) {
        endGrab(throwing: true, at: t)
        wanderPausedUntil = t + TurtleGrab.wanderPause
    }

    private func endGrab(throwing: Bool, at t: TimeInterval) {
        guard pose == .held, var flight else { return }
        flight.release(throwing: throwing, at: t)
        self.flight = flight
        // The flail clock carries on from the grab
        pose = .falling
        airborne = true
    }

    // One physics step per display frame while held or falling
    func advance(to t: TimeInterval) {
        guard var flight else { return }
        if pose == .held {
            flight.hold(to: t)
            self.flight = flight
            return
        }
        let half = size / 2
        switch flight.fall(to: t, minX: half, maxX: screen.width - half, floor: ground) {
        case .none:
            self.flight = flight
        case .bounce:
            self.flight = flight
            startHop(TurtleKeyframes.landing(TurtleFall.bounceSquash), duration: TurtleFall.bounceDuration, curve: .easeOutCurve)
        case .landed:
            x = flight.foot.x
            self.flight = nil
            land()
        }
    }

    // Squash on the floor and keep the eyes shut until the head shake
    private func land() {
        startHop(TurtleKeyframes.landing(1), duration: TurtleFall.landDuration, curve: .easeOutCurve)
        setEyesClosing(true)
        eyesClosed = true
        setPose(.idle)
        Task {
            await sleep(TurtleFall.settle)
            airborne = false
            landed = true
        }
    }
}
