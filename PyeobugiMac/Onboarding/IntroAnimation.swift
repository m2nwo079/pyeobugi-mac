import CoreGraphics
import Foundation

// MARK: - Timing

// cubic-bezier() timing function with the same definition as CSS
nonisolated struct IntroEasing {
    let x1: Double, y1: Double, x2: Double, y2: Double

    static let linear = IntroEasing(x1: 0, y1: 0, x2: 1, y2: 1)
    static let easeOut = IntroEasing(x1: 0, y1: 0, x2: 0.58, y2: 1)
    static let easeInOut = IntroEasing(x1: 0.42, y1: 0, x2: 0.58, y2: 1)

    func callAsFunction(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        if x1 == y1 && x2 == y2 { return t }
        let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
        let cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
        func x(_ s: Double) -> Double { ((ax * s + bx) * s + cx) * s }
        func y(_ s: Double) -> Double { ((ay * s + by) * s + cy) * s }
        var s = t
        for _ in 0..<8 {
            let error = x(s) - t
            if abs(error) < 1e-7 { return y(s) }
            let slope = (3 * ax * s + 2 * bx) * s + cx
            if abs(slope) < 1e-6 { break }
            s -= error / slope
        }
        var low = 0.0, high = 1.0
        s = t
        while high - low > 1e-7 {
            if x(s) < t { low = s } else { high = s }
            s = (low + high) / 2
        }
        return y(s)
    }
}

// One keyframe: values of the animated parameters, and the easing of the segment that starts here
nonisolated struct IntroKey {
    var offset: Double?
    var values: [Double]
    var easing = IntroEasing.linear

    init(_ values: Double..., at offset: Double? = nil, easing: IntroEasing = .linear) {
        self.values = values
        self.offset = offset
        self.easing = easing
    }

    init(values: [Double], at offset: Double? = nil) {
        self.values = values
        self.offset = offset
    }
}

// What an animation writes to
enum IntroChannel {
    // Parameters turned into a transform by the closure; additive animations stack on the value below
    case transform(([Double]) -> CGAffineTransform, additive: Bool)
    case opacity
    case rect
}

// A keyframe animation on one node: delay, duration, iterations, overall easing and an optional forwards fill
final class IntroMotion {
    let channel: IntroChannel
    let keys: [IntroKey]
    let start: Double
    let delay: Double
    let duration: Double
    let iterations: Double
    let easing: IntroEasing
    let fill: Bool
    var onEnd: (() -> Void)?
    fileprivate var ended = false

    init(_ channel: IntroChannel, _ keys: [IntroKey], start: Double, delay: Double, duration: Double, iterations: Double,
         easing: IntroEasing, fill: Bool) {
        self.channel = channel
        self.start = start
        self.delay = delay
        self.duration = duration
        self.iterations = iterations
        self.easing = easing
        self.fill = fill
        // Missing offsets are spread evenly between their neighbours
        var keys = keys
        keys[0].offset = keys[0].offset ?? 0
        keys[keys.count - 1].offset = keys[keys.count - 1].offset ?? 1
        var known = 0
        for index in 1..<keys.count where keys[index].offset != nil {
            let from = keys[known].offset!, to = keys[index].offset!
            for gap in (known + 1)..<index {
                keys[gap].offset = from + (to - from) * Double(gap - known) / Double(index - known)
            }
            known = index
        }
        self.keys = keys
    }

    var end: Double { start + delay + duration * iterations }

    // Parameter values at time t, or nil while the animation has no effect
    func values(at t: Double) -> [Double]? {
        let local = t - start - delay
        if local < 0 { return nil }
        var progress: Double
        if local >= duration * iterations {
            guard fill else { return nil }
            progress = 1
        } else {
            progress = local.truncatingRemainder(dividingBy: duration) / duration
        }
        progress = easing(progress)
        var index = 0
        while index < keys.count - 2, progress >= keys[index + 1].offset! { index += 1 }
        let a = keys[index], b = keys[index + 1]
        let span = b.offset! - a.offset!
        let local01 = span > 0 ? a.easing((progress - a.offset!) / span) : 1
        return zip(a.values, b.values).map { $0 + ($1 - $0) * local01 }
    }
}

// MARK: - Nodes

// Value of a node after its animations: transform about the node's origin, opacity and (for the screen) a frame
struct IntroNodeValue {
    var transform = CGAffineTransform.identity
    var opacity = 1.0
    var rect = CGRect.zero
}

// One animated element. `base` plays the role of the inline style; animations apply on top in creation order
final class IntroNode {
    let origin: CGPoint
    var base = IntroNodeValue()
    fileprivate(set) var motions: [IntroMotion] = []

    init(origin: CGPoint = .zero) {
        self.origin = origin
    }

    func value(at t: Double, through last: IntroMotion? = nil) -> IntroNodeValue {
        var value = base
        for motion in motions {
            if let v = motion.values(at: t) {
                switch motion.channel {
                case let .transform(build, additive):
                    value.transform = additive ? build(v).concatenating(value.transform) : build(v)
                case .opacity:
                    value.opacity = v[0]
                case .rect:
                    value.rect = CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
                }
            }
            if motion === last { break }
        }
        return value
    }

    // The transform about the node's origin, in its parent's coordinates
    func placed(_ transform: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(translationX: -origin.x, y: -origin.y)
            .concatenating(transform)
            .concatenating(CGAffineTransform(translationX: origin.x, y: origin.y))
    }
}

// CSS transform functions, applied in list order like a transform list
nonisolated enum IntroTF {
    static func translate(_ x: Double, _ y: Double) -> CGAffineTransform { CGAffineTransform(translationX: x, y: y) }
    static func rotate(_ degrees: Double) -> CGAffineTransform { CGAffineTransform(rotationAngle: degrees * .pi / 180) }
    static func scale(_ x: Double, _ y: Double) -> CGAffineTransform { CGAffineTransform(scaleX: x, y: y) }

    // `list(a, b)` is the CSS list "a b": b applies to the element first
    static func list(_ functions: CGAffineTransform...) -> CGAffineTransform {
        functions.reversed().reduce(.identity) { $0.concatenating($1) }
    }

    // 2D decomposition used to interpolate between transform lists that do not match function by function
    static func decompose(_ m: CGAffineTransform) -> [Double] {
        var row0 = (x: Double(m.a), y: Double(m.b)), row1 = (x: Double(m.c), y: Double(m.d))
        var sx = hypot(row0.x, row0.y), sy = hypot(row1.x, row1.y)
        if row0.x * row1.y - row0.y * row1.x < 0 {
            if row0.x < row1.y { sx = -sx } else { sy = -sy }
        }
        if sx != 0 { row0 = (row0.x / sx, row0.y / sx) }
        if sy != 0 { row1 = (row1.x / sy, row1.y / sy) }
        let angle = atan2(row0.y, row0.x) * 180 / .pi
        return [Double(m.tx), Double(m.ty), angle, sx, sy]
    }

    static func recompose(_ v: [Double]) -> CGAffineTransform {
        list(translate(v[0], v[1]), rotate(v[2]), scale(v[3], v[4]))
    }

    static func decomposed(from: CGAffineTransform, to: CGAffineTransform) -> [IntroKey] {
        var a = decompose(from), b = decompose(to)
        // Turn the short way around
        if abs(a[2] - b[2]) > 180 {
            if a[2] > b[2] { a[2] -= 360 } else { b[2] -= 360 }
        }
        return [IntroKey(values: a), IntroKey(values: b)]
    }
}

// MARK: - Clock

// Virtual time in milliseconds. Timers run in time order while the clock advances, so every step of the
// sequence starts exactly when the step before it ended, whatever the frame rate
final class IntroClock {
    private(set) var now = 0.0
    private var timers: [(time: Double, order: Int, action: () -> Void)] = []
    private var order = 0

    func after(_ ms: Double, _ action: @escaping () -> Void) {
        order += 1
        timers.append((now + ms, order, action))
    }

    func advance(to t: Double) {
        while let index = timers.indices.filter({ timers[$0].time <= t })
            .min(by: { (timers[$0].time, timers[$0].order) < (timers[$1].time, timers[$1].order) }) {
            let timer = timers.remove(at: index)
            now = max(now, timer.time)
            timer.action()
        }
        now = max(now, t)
    }
}

// MARK: - Scene

// The intro sequence: loading, the laptop rising with the start copy, the idle turtle, and the expanding screen.
// Times are milliseconds; all values follow docs/intro.md
final class IntroScene {
    enum Stage {
        case loading, rising, start, expanding, permission
    }

    private enum Act {
        case look, shake, tap, wave, rest
    }

    static let size = CGSize(width: 1280, height: 832)
    static let turtleBox = CGRect(x: 430.13, y: -4, width: 420, height: 420)
    static let screenFrom = CGRect(x: 123, y: 257, width: 1034, height: 686)
    static let screenTo = CGRect(x: -18, y: -150, width: 1316, height: 1000)
    static let easeOut = IntroEasing(x1: 0.22, y1: 1, x2: 0.36, y2: 1)
    static let easeInOut = IntroEasing(x1: 0.76, y1: 0, x2: 0.24, y2: 1)
    static let poseEasing = IntroEasing(x1: 0.45, y1: 0, x2: 0.25, y2: 1)

    let reduceMotion: Bool
    let clock = IntroClock()
    var onStart: () -> Void = {}
    private(set) var stage = Stage.loading

    // Elements, with transform origins in their own boxes
    let logo = IntroNode(origin: CGPoint(x: 423, y: 260))
    let loadingText = IntroNode()
    let dots = (0..<4).map { _ in IntroNode() }
    let laptop = IntroNode(origin: CGPoint(x: 640, y: 416))
    let turtleBody = IntroNode(origin: CGPoint(x: 209.87, y: 315))
    let turtleFront = IntroNode(origin: CGPoint(x: 209.87, y: 315))
    let body = IntroNode(origin: CGPoint(x: 210, y: 318))
    let shell = IntroNode(origin: CGPoint(x: 210, y: 300))
    let flips = IntroNode(origin: CGPoint(x: 210, y: 317.94))
    // Fill boxes of the flippers: left (57.6286, 254.2961, 81.6004 x 75.3075) at 80% 15%, right at 20% 15%
    let flipperLeft = IntroNode(origin: CGPoint(x: 57.6286 + 81.6004 * 0.8, y: 254.2961 + 75.3075 * 0.15))
    let flipperRight = IntroNode(origin: CGPoint(x: 281.7619 + 81.6006 * 0.2, y: 254.2961 + 75.3075 * 0.15))
    let bob = IntroNode(origin: CGPoint(x: 210, y: 299.88))
    let head = IntroNode(origin: CGPoint(x: 210, y: 299.88))
    let look = IntroNode(origin: CGPoint(x: 210, y: 228))
    // Fill box of the open eyes (164.0004, 206.8706, 91.2362 x 40.7468) at 50% 55%
    let blink = IntroNode(origin: CGPoint(x: 164.0004 + 91.2362 * 0.5, y: 206.8706 + 40.7468 * 0.55))
    let closed = IntroNode()
    let startContent = IntroNode()
    let startItems = (0..<3).map { _ in IntroNode() }
    let button = IntroNode(origin: CGPoint(x: 100, y: 22))
    let notch = IntroNode()
    let screen = IntroNode()
    let screenFill = IntroNode()

    // Flippers drawn above the head while waving
    private(set) var flipsOnTop = false
    // Start copy takes pointer input and the button takes keyboard focus
    private(set) var interactive = false
    var buttonFocused = false {
        didSet {
            if buttonFocused != oldValue { buttonFocused ? watchButton() : unwatchButton() }
        }
    }

    private var brain = 0
    private var attention = false
    private var eyesShut = false
    private var following = false
    private var watching = false
    private var lastAct = Act.shake
    private var lastMove = 0.0
    private var lastFrame: Double?
    private var aim = CGPoint.zero
    private var cur = CGPoint.zero
    private var running: [ObjectIdentifier: IntroMotion] = [:]
    private var random: () -> Double

    init(reduceMotion: Bool, random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.reduceMotion = reduceMotion
        self.random = random
        laptop.base.transform = IntroTF.translate(0, 293)
        screen.base.rect = Self.screenFrom
        closed.base.opacity = 0
        screenFill.base.opacity = 0
        for item in startItems { item.base.opacity = 0 }
    }

    // IntroMotion durations shrink to a short fade when the system asks for less motion
    private func D(_ ms: Double) -> Double { reduceMotion ? min(ms, 180) : ms }

    private var active: Bool { stage == .loading || stage == .rising || stage == .start }

    // MARK: Animation helpers

    @discardableResult
    private func animate(_ node: IntroNode, _ channel: IntroChannel, _ keys: [IntroKey], duration: Double, delay: Double = 0,
                         iterations: Double = 1, easing: IntroEasing = .linear, fill: Bool = false,
                         then done: (() -> Void)? = nil) -> IntroMotion {
        let motion = IntroMotion(channel, keys, start: clock.now, delay: delay, duration: duration, iterations: iterations,
                            easing: easing, fill: fill)
        motion.onEnd = done
        node.motions.append(motion)
        if iterations.isFinite {
            clock.after(delay + duration * iterations) { [weak node, weak motion] in
                guard let node, let motion, !motion.ended else { return }
                motion.ended = true
                if !motion.fill { node.motions.removeAll { $0 === motion } }
                let done = motion.onEnd
                motion.onEnd = nil
                done?()
            }
        }
        return motion
    }

    private func transform(_ build: @escaping ([Double]) -> CGAffineTransform, additive: Bool = false) -> IntroChannel {
        .transform(build, additive: additive)
    }

    private let translateY = IntroChannel.transform({ IntroTF.translate(0, $0[0]) }, additive: false)
    private let rotate = IntroChannel.transform({ IntroTF.rotate($0[0]) }, additive: false)
    private let scaleY = IntroChannel.transform({ IntroTF.scale(1, $0[0]) }, additive: false)
    private let scaleXY = IntroChannel.transform({ IntroTF.scale($0[0], $0[1]) }, additive: false)

    // Cancelling ends the animation now; whoever waits on it continues right away
    private func cancel(_ motion: IntroMotion, on node: IntroNode) {
        guard !motion.ended else { return }
        motion.ended = true
        node.motions.removeAll { $0 === motion }
        if let done = motion.onEnd { clock.after(0, done) }
        motion.onEnd = nil
    }

    private func commit(_ motion: IntroMotion, on node: IntroNode) {
        node.base.transform = node.value(at: clock.now, through: motion).transform
    }

    // Moves from the current transform to the target and keeps it there
    private func pose(_ node: IntroNode, _ target: CGAffineTransform, _ duration: Double, easing: IntroEasing = poseEasing,
                      then done: (() -> Void)? = nil) {
        let id = ObjectIdentifier(node)
        if let previous = running[id] {
            commit(previous, on: node)
            cancel(previous, on: node)
        }
        let from = node.value(at: clock.now).transform
        var motion: IntroMotion!
        motion = animate(node, transform(IntroTF.recompose), IntroTF.decomposed(from: from, to: target), duration: duration,
                         easing: easing, fill: true) { [unowned self, unowned node] in
            if !node.motions.contains(where: { $0 === motion }) {
                // Cancelled
            } else {
                commit(motion, on: node)
                node.motions.removeAll { $0 === motion }
            }
            if running[id] === motion { running[id] = nil }
            done?()
        }
        running[id] = motion
    }

    private func play(_ node: IntroNode, _ channel: IntroChannel, _ keys: [IntroKey], duration: Double, easing: IntroEasing = .linear,
                      then done: (() -> Void)? = nil) {
        animate(node, channel, keys, duration: duration, easing: easing, then: done)
    }

    private func wait(_ ms: Double, _ action: @escaping () -> Void) {
        clock.after(ms, action)
    }

    private func nap(_ ms: Double, _ gen: Int, _ action: @escaping (Bool) -> Void) {
        clock.after(ms) { [unowned self] in action(gen == brain) }
    }

    private func all(_ count: Int, then done: @escaping () -> Void) -> () -> Void {
        var left = count
        return {
            left -= 1
            if left == 0 { done() }
        }
    }

    private func rand(_ a: Double, _ b: Double) -> Double { a + random() * (b - a) }

    // MARK: Sequence

    func run() {
        playLoading { [unowned self] in playRise() }
    }

    private func playLoading(then done: @escaping () -> Void) {
        stage = .loading
        wakeTurtle(firstShake: false, keepBreath: false)
        if !reduceMotion {
            for (i, dot) in dots.enumerated() {
                animate(dot, .opacity, [IntroKey(0.15), IntroKey(1), IntroKey(0.15)], duration: 1100, delay: Double(i) * 140,
                        iterations: .infinity)
            }
        }
        animate(logo, .opacity, [IntroKey(0), IntroKey(1)], duration: D(700), easing: Self.easeOut, fill: true)
        animate(logo, translateY, [IntroKey(16), IntroKey(0)], duration: D(700), easing: Self.easeOut, fill: true)
        wait(reduceMotion ? 900 : 2300, done)
    }

    private func playRise() {
        stage = .rising
        let fall = IntroEasing(x1: 0.55, y1: 0, x2: 0.75, y2: 0.4)
        animate(logo, .opacity, [IntroKey(1), IntroKey(0)], duration: D(650), easing: fall, fill: true)
        animate(logo, translateY, [IntroKey(0), IntroKey(-90)], duration: D(650), easing: fall, fill: true)
        animate(loadingText, .opacity, [IntroKey(1), IntroKey(0)], duration: D(220), fill: true)
        if reduceMotion {
            animate(laptop, translateY, [IntroKey(293), IntroKey(0)], duration: D(1000), delay: D(120), easing: Self.easeOut, fill: true)
            animate(laptop, .opacity, [IntroKey(0), IntroKey(1)], duration: D(1000), delay: D(120), easing: Self.easeOut, fill: true)
        } else {
            animate(laptop, translateY, [IntroKey(293), IntroKey(-12, at: 0.72), IntroKey(0)], duration: D(1000), delay: D(120),
                    easing: Self.easeOut, fill: true)
        }
        for (i, item) in startItems.enumerated() {
            let delay = D(620 + Double(i) * 90)
            animate(item, .opacity, [IntroKey(0), IntroKey(1)], duration: D(500), delay: delay, easing: Self.easeOut, fill: true)
            animate(item, translateY, [IntroKey(10), IntroKey(0)], duration: D(500), delay: delay, easing: Self.easeOut, fill: true)
        }
        // The turtle rides up on the laptop edge and squashes a little when it lands
        wait(D(1000)) { [unowned self] in
            if !reduceMotion {
                for node in [turtleBody, turtleFront] {
                    animate(node, scaleXY, [IntroKey(1, 1), IntroKey(1.03, 0.95, at: 0.4), IntroKey(1, 1)], duration: 380, easing: .easeOut)
                }
            }
            wait(D(240)) { [unowned self] in
                wakeTurtle(firstShake: true, keepBreath: true)
                stage = .start
                interactive = true
            }
        }
    }

    func expand() {
        guard stage == .start else { return }
        stage = .expanding
        brain += 1
        attention = false
        interactive = false
        animate(button, scaleXY, [IntroKey(1, 1), IntroKey(0.96, 0.96), IntroKey(1, 1)], duration: D(200))
        wait(D(160)) { [unowned self] in
            let duration = D(950)
            // Distance the screen's top edge travels (257 to -150)
            let push = 407.0
            let grow = 1316.0 / 1034.0
            animate(startContent, .opacity, [IntroKey(1), IntroKey(0)], duration: duration * 0.45, easing: .easeOut, fill: true)
            for node in [turtleFront, turtleBody] {
                animate(node, transform { IntroTF.list(IntroTF.translate(0, $0[0]), IntroTF.scale($0[1], $0[1])) },
                        [IntroKey(0, 1), IntroKey(-push, grow)], duration: duration, easing: Self.easeInOut, fill: true)
            }
            animate(notch, translateY, [IntroKey(0), IntroKey(-24)], duration: duration, easing: Self.easeInOut, fill: true)
            let from = Self.screenFrom, to = Self.screenTo
            animate(screen, .rect, [IntroKey(from.minX, from.minY, from.width, from.height), IntroKey(to.minX, to.minY, to.width, to.height)],
                    duration: duration, easing: Self.easeInOut, fill: true) { [unowned self] in
                animate(screenFill, .opacity, [IntroKey(0), IntroKey(1)], duration: D(900),
                        easing: IntroEasing(x1: 0.4, y1: 0, x2: 0.2, y2: 1), fill: true) { [unowned self] in
                    stage = .permission
                    onStart()
                }
            }
        }
    }

    // MARK: Turtle

    private func blinkOnce(then done: @escaping () -> Void) {
        if eyesShut { return done() }
        play(blink, scaleY, [IntroKey(1), IntroKey(0.08, at: 0.45), IntroKey(0.08, at: 0.55), IntroKey(1)], duration: 170,
             easing: .easeInOut, then: done)
    }

    private func blinkLoop(_ gen: Int) {
        nap(rand(2200, 5200), gen) { [unowned self] alive in
            guard alive else { return }
            blinkOnce { [unowned self] in
                if random() < 0.22 {
                    nap(90, gen) { [unowned self] _ in blinkOnce { [unowned self] in blinkLoop(gen) } }
                } else {
                    blinkLoop(gen)
                }
            }
        }
    }

    // The shell swells a little and the head rises with it
    private func breathe() {
        animate(shell, scaleXY, [IntroKey(1, 1), IntroKey(1.015, 1.03), IntroKey(1, 1)], duration: 3200, iterations: .infinity,
                easing: .easeInOut)
        animate(bob, translateY, [IntroKey(0), IntroKey(-1.5), IntroKey(0)], duration: 3200, iterations: .infinity, easing: .easeInOut)
    }

    private func headPose(_ dx: Double, _ dy: Double) -> CGAffineTransform {
        IntroTF.list(IntroTF.translate(dx * 7, dy * 3), IntroTF.rotate(dx * 6))
    }

    private func lookPose(_ dx: Double, _ dy: Double = 0, then done: @escaping () -> Void) {
        if eyesShut || following { return done() }
        let both = all(2, then: done)
        pose(head, headPose(dx, dy), 380, then: both)
        pose(look, IntroTF.list(IntroTF.translate(dx * 15, dy * 9), IntroTF.scale(1 - abs(dx) * 0.08, 1)), 340, then: both)
    }

    private func lookAround(_ gen: Int, then done: @escaping () -> Void) {
        let first = random() < 0.5 ? -1.0 : 1.0
        lookPose(first, rand(-0.3, 0.4)) { [unowned self] in
            nap(rand(700, 1200), gen) { [unowned self] alive in
                if !alive || attention { return done() }
                let back = { [unowned self] in
                    lookPose(-first, rand(-0.3, 0.4)) { [unowned self] in
                        nap(rand(700, 1200), gen) { [unowned self] alive in
                            if !alive || attention { return done() }
                            lookPose(0, then: done)
                        }
                    }
                }
                if random() < 0.5 { blinkOnce(then: back) } else { back() }
            }
        }
    }

    // Shut eyes, shake the head side to side and settle
    private func shake(_ gen: Int, then done: @escaping () -> Void) {
        if eyesShut { return done() }
        eyesShut = true
        pose(look, .identity, 160) { [unowned self] in
            blink.base.opacity = 0
            closed.base.opacity = 1
            pose(head, .identity, 120) { [unowned self] in
                let jig: [(Double, Double)] = [(0, 0), (1.6, 0.12), (-1.6, 0.26), (1.1, 0.4), (-0.8, 0.54), (0.3, 0.7), (0, 1)]
                for node in [flips, body] {
                    animate(node, rotate, jig.map { IntroKey($0.0, at: $0.1, easing: .easeInOut) }, duration: 950)
                }
                let kf: [(Double, Double, Double)] = [(0, 0, 0), (-14, -10, 0.1), (14, 10, 0.24), (-11, -8, 0.38),
                                                      (8, 5, 0.52), (-4, -3, 0.66), (1.5, 1, 0.8), (0, 0, 1)]
                play(head, transform { IntroTF.list(IntroTF.rotate($0[0]), IntroTF.translate($0[1], 0)) },
                     kf.map { IntroKey($0.0, $0.1, at: $0.2, easing: .easeInOut) }, duration: 950) { [unowned self] in
                    nap(140, gen) { [unowned self] _ in
                        closed.base.opacity = 0
                        blink.base.opacity = 1
                        eyesShut = false
                        play(blink, scaleY, [IntroKey(0.1), IntroKey(1)], duration: 160, easing: .easeOut, then: done)
                    }
                }
            }
        }
    }

    // Greets with the right flipper, smiling eyes and a tilted head
    private func wave(_ gen: Int, then done: @escaping () -> Void) {
        eyesShut = true
        let both = all(2) { [unowned self] in
            blink.base.opacity = 0
            closed.base.opacity = 1
            flipsOnTop = true
            let swing: [(Double, Double, Double, Double)] = [(0, 0, 0, 0), (50, -6, -128, 0.18), (50, -6, -98, 0.3),
                                                             (50, -6, -134, 0.42), (50, -6, -98, 0.54), (50, -6, -134, 0.66),
                                                             (50, -6, -110, 0.78), (0, 0, 0, 1)]
            let hop: [(Double, Double)] = [(0, 0), (-5, 0.18), (-5, 0.78), (0, 1)]
            animate(bob, transform({ IntroTF.translate(0, $0[0]) }, additive: true),
                    hop.map { IntroKey($0.0, at: $0.1, easing: .easeInOut) }, duration: 1800)
            play(flipperRight, transform { IntroTF.list(IntroTF.translate($0[0], $0[1]), IntroTF.rotate($0[2])) },
                 swing.map { IntroKey($0.0, $0.1, $0.2, at: $0.3, easing: .easeInOut) }, duration: 1800) { [unowned self] in
                flipsOnTop = false
                closed.base.opacity = 0
                blink.base.opacity = 1
                eyesShut = false
                play(blink, scaleY, [IntroKey(0.1), IntroKey(1)], duration: 160, easing: .easeOut)
                if gen == brain { pose(head, .identity, 360, then: done) } else { done() }
            }
        }
        pose(look, .identity, 160, then: both)
        pose(head, IntroTF.list(IntroTF.translate(5, -3), IntroTF.rotate(6)), 320, then: both)
    }

    // Taps the laptop edge with one flipper
    private func tap(then done: @escaping () -> Void) {
        let left = random() < 0.5
        let s = left ? 1.0 : -1.0
        let kf: [(Double, Double)] = [(0, 0), (-9 * s, 0.25), (0, 0.5), (-7 * s, 0.72), (0, 1)]
        play(left ? flipperLeft : flipperRight, rotate, kf.map { IntroKey($0.0, at: $0.1, easing: .easeInOut) },
             duration: 560, then: done)
    }

    private func idleLoop(_ gen: Int) {
        nap(rand(1100, 2600), gen) { [unowned self] alive in
            guard alive else { return }
            if attention { return idleLoop(gen) }
            // Looking around is the main act; head shakes are occasional and never twice in a row
            let r = random()
            if r < 0.6 {
                lookAround(gen) { [unowned self] in
                    lastAct = .look
                    idleLoop(gen)
                }
            } else if r < 0.68 && lastAct != .shake {
                shake(gen) { [unowned self] in
                    lastAct = .shake
                    idleLoop(gen)
                }
            } else if r < 0.84 {
                tap { [unowned self] in
                    lastAct = .tap
                    idleLoop(gen)
                }
            } else {
                lastAct = .rest
                idleLoop(gen)
            }
        }
    }

    private func wakeTurtle(firstShake: Bool, keepBreath: Bool) {
        brain += 1
        let gen = brain
        if reduceMotion { return }
        if !keepBreath { breathe() }
        blinkLoop(gen)
        // Waves once the laptop lands; while loading, looks around and waits
        if firstShake {
            nap(150, gen) { [unowned self] alive in
                let next = { [unowned self] in
                    lastAct = .wave
                    idleLoop(gen)
                }
                if alive { wave(gen, then: next) } else { next() }
            }
        } else {
            nap(600, gen) { [unowned self] alive in
                if alive {
                    lookAround(gen) { [unowned self] in
                        lastAct = .look
                        idleLoop(gen)
                    }
                } else {
                    idleLoop(gen)
                }
            }
        }
    }

    // MARK: Input

    // Keyboard focus on the start button makes the turtle look down at it
    private func watchButton() {
        guard stage == .start, !reduceMotion, !eyesShut, !following else { return }
        watching = true
        attention = true
        pose(head, IntroTF.list(IntroTF.translate(-5, 4), IntroTF.rotate(-5)), 320)
        pose(look, IntroTF.list(IntroTF.translate(-13, 12), IntroTF.scale(0.94, 1)), 300)
    }

    private func unwatchButton() {
        guard watching else { return }
        watching = false
        attention = false
        lookPose(0) {}
    }

    // Pointer in stage coordinates; `turtle` is the bounding box of the front turtle box in stage coordinates
    func pointerMoved(to point: CGPoint, turtle: CGRect) {
        guard !reduceMotion, active else { return }
        let hx = turtle.minX + turtle.width * 0.5
        // Between the eyes
        let hy = turtle.minY + turtle.height * 0.54
        let s = turtle.width / 420
        aim = CGPoint(x: clamp((point.x - hx) / (420 * s)), y: clamp((point.y - hy) / (320 * s)))
        lastMove = clock.now
        guard !following else { return }
        following = true
        attention = true
        for node in [head, look] {
            let id = ObjectIdentifier(node)
            if let motion = running[id] {
                commit(motion, on: node)
                cancel(motion, on: node)
                running[id] = nil
            }
        }
        let m = look.value(at: clock.now).transform
        cur = CGPoint(x: clamp(m.tx / 15), y: clamp(m.ty / 9))
    }

    // Clicking the turtle's head or flippers makes it shake its head
    func poke() {
        guard !reduceMotion, active, !eyesShut else { return }
        shake(brain) {}
    }

    // Advances the sequence to time t and follows the pointer once per frame
    func frame(at t: Double) {
        clock.advance(to: t)
        let dt = t - (lastFrame ?? t)
        lastFrame = t
        guard following else { return }
        if !active || clock.now - lastMove > 2500 {
            // Idle pointer: back to acting on its own
            following = false
            attention = false
            return
        }
        // Paused while shaking or waving
        if eyesShut { return }
        // 0.14 of the remaining distance per frame at 60 frames per second
        let k = 1 - pow(1 - 0.14, dt * 60 / 1000)
        cur.x += (aim.x - cur.x) * k
        cur.y += (aim.y - cur.y) * k
        head.base.transform = IntroTF.list(IntroTF.translate(cur.x * 7, cur.y * 4), IntroTF.rotate(cur.x * 6))
        look.base.transform = IntroTF.list(IntroTF.translate(cur.x * 15, cur.y * 10), IntroTF.scale(1 - abs(cur.x) * 0.08, 1))
    }

    private func clamp(_ v: Double) -> Double { max(-1, min(1, v)) }
}
