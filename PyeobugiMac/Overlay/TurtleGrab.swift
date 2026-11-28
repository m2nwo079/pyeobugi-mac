import AppKit
import SwiftUI

// MARK: - Constants (durations in seconds, lengths in points unless noted)

enum TurtleGrab {
    // The hand holds the drawing box at this point
    static let grip = UnitPoint(x: 0.5, y: 0.3)
    // Pointer hit box around the feet: half width and height above in turtle sizes, depth below in points
    static let hitHalfWidth: CGFloat = 0.6
    static let hitAbove: CGFloat = 1
    static let hitBelow: CGFloat = 8
    // Gravity for the pendulum and the fall (points per second squared)
    static let gravity = 2600.0
    // The hand closes this fraction of the gap to the pointer per second
    static let follow = 28.0
    // Smoothing rate of the hand's sideways acceleration per second
    static let accelerationSmoothing = 12.0
    // Pendulum length in turtle sizes, damping per second, and limits of spin (rad/s) and tilt (rad)
    static let pendulumLength = 0.36
    static let pendulumDamping = 3.2
    static let maxSpin = 14.0
    static let maxTilt = 1.0
    // Longest physics step, and the step used when a frame reports no elapsed time
    static let maxStep = 0.033
    static let fallbackStep = 0.016
    // Throw speed from the pointer samples of the last throwWindow, measured over at least minThrowSpan
    static let historyLength = 6
    static let throwWindow = 0.09
    static let minThrowSpan = 0.016
    static let maxThrowSideways = 1800.0
    static let maxThrowUp = 1800.0
    static let maxThrowDown = 1400.0
    static let startleDuration: TimeInterval = 0.26
    // Legs flail back and forth once per period, the second pair `lead` ahead; the head trembles while held
    static let heldFlailPeriod: TimeInterval = 0.2
    static let heldFlailLead: TimeInterval = 0.1
    static let fallingFlailPeriod: TimeInterval = 0.26
    static let fallingFlailLead: TimeInterval = 0.13
    static let tremblePeriod: TimeInterval = 0.16
    // Wandering waits this long after a grab or a release, checking every pausePoll
    static let wanderPause: TimeInterval = 1.5
    static let pausePoll: TimeInterval = 0.15
    // How often the behaviour loop checks whether the turtle is back on the floor
    static let busyPoll: TimeInterval = 0.05
}

enum TurtleFall {
    // Sideways speed kept (and reversed) at a screen edge
    static let wallBounce = 0.45
    // The first floor contact faster than bounceSpeed bounces once
    static let bounceSpeed = 520.0
    static let bounceKeep = 0.22
    static let bounceSlide = 0.5
    // Tilt springs back to upright while falling
    static let tiltSpring = 22.0
    static let tiltDamping = 3.5
    static let bounceSquash = 0.6
    static let bounceDuration: TimeInterval = 0.26
    static let landDuration: TimeInterval = 0.38
    // Grabbing stays off this long after landing
    static let settle: TimeInterval = 0.3
    static let restAfterLanding: ClosedRange<TimeInterval> = 0.6...1.2
}

extension TurtleKeyframes {
    // Lift (pt), scale x, scale y
    static let startle = Keyframes([(0, [0, 0.9, 1.12]), (0.5, [0, 1.04, 0.96]), (1, [0, 1, 1])])

    static func landing(_ strength: Double) -> Keyframes {
        let k = strength
        return Keyframes([
            (0, [0, 1, 1]),
            (0.3, [3 * k, 1 + 0.16 * k, 1 - 0.2 * k]),
            (0.65, [0, 1 - 0.04 * k, 1 + 0.05 * k]),
            (1, [0, 1, 1]),
        ])
    }

    // Leg angle (degrees), lift (drawing units)
    static let flail = Keyframes([(0, [-24, -5]), (1, [20, 4])], curve: .easeInOutCurve)
    // Head angle (degrees), lift (drawing units)
    static let tremble = Keyframes([(0, [-3, 1]), (1, [3, -2])], curve: .easeInOutCurve)
}

// MARK: - Physics

struct PointerSample {
    var point: CGPoint
    var time: TimeInterval
}

// The turtle in the hand (a pendulum hanging from the grip) and in the air after release, in view points with y down
struct TurtleFlight {
    enum Contact {
        case none, bounce, landed
    }

    let size: CGFloat
    // Where the grip is, the pointer it chases, and the feet
    private(set) var hand: CGPoint
    private var target: CGPoint
    private(set) var foot: CGPoint
    // Radians, clockwise on screen
    private(set) var tilt = 0.0
    private var spin = 0.0
    private var sideSpeed = 0.0
    private var sideAcceleration = 0.0
    private var history: [PointerSample]
    private var velocity = CGVector.zero
    private var bounced = false
    private var last: TimeInterval

    static func grip(_ size: CGFloat) -> CGPoint {
        CGPoint(x: size * TurtleGrab.grip.x, y: size * TurtleGrab.grip.y)
    }

    init(foot: CGPoint, size: CGFloat, pointer: CGPoint, at t: TimeInterval) {
        self.size = size
        self.foot = foot
        let g = Self.grip(size)
        hand = CGPoint(x: foot.x - size / 2 + g.x, y: foot.y - size * TurtleSize.footLine + g.y)
        target = pointer
        history = [PointerSample(point: pointer, time: t)]
        last = t
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(high, max(low, value))
    }

    private mutating func step(to t: TimeInterval) -> Double {
        let dt = min(TurtleGrab.maxStep, t - last)
        last = t
        return dt
    }

    // The hand follows inside the screen; samples keep the raw pointer
    mutating func move(to pointer: CGPoint, screen: CGSize, at t: TimeInterval) {
        target = CGPoint(x: min(screen.width, max(0, pointer.x)), y: min(screen.height, max(0, pointer.y)))
        history.append(PointerSample(point: pointer, time: t))
        if history.count > TurtleGrab.historyLength { history.removeFirst(history.count - TurtleGrab.historyLength) }
    }

    mutating func hold(to t: TimeInterval) {
        let raw = step(to: t)
        let dt = raw > 0 ? raw : TurtleGrab.fallbackStep
        let previous = hand.x
        let k = CGFloat(min(1, dt * TurtleGrab.follow))
        hand.x += (target.x - hand.x) * k
        hand.y += (target.y - hand.y) * k
        let speed = Double(hand.x - previous) / dt
        let acceleration = (speed - sideSpeed) / dt
        sideSpeed = speed
        sideAcceleration += (acceleration - sideAcceleration) * min(1, dt * TurtleGrab.accelerationSmoothing)
        let length = Double(size) * TurtleGrab.pendulumLength
        spin += (-(TurtleGrab.gravity / length) * sin(tilt) - TurtleGrab.pendulumDamping * spin - (sideAcceleration / length) * cos(tilt)) * dt
        spin = Self.clamp(spin, -TurtleGrab.maxSpin, TurtleGrab.maxSpin)
        tilt = Self.clamp(tilt + spin * dt, -TurtleGrab.maxTilt, TurtleGrab.maxTilt)
        foot = footInHand()
    }

    // The feet turned with the tilt around the grip
    private func footInHand() -> CGPoint {
        let g = Self.grip(size)
        let fx = Double(size / 2 - g.x), fy = Double(size * TurtleSize.footLine - g.y)
        let c = cos(tilt), s = sin(tilt)
        return CGPoint(x: hand.x + CGFloat(fx * c - fy * s), y: hand.y + CGFloat(fx * s + fy * c))
    }

    static func throwVelocity(_ history: [PointerSample], at t: TimeInterval) -> CGVector {
        guard history.count > 1, let first = history.first, let latest = history.last else { return .zero }
        let old = history.first { t - $0.time < TurtleGrab.throwWindow } ?? first
        let span = max(TurtleGrab.minThrowSpan, t - old.time)
        let dx = clamp(Double(latest.point.x - old.point.x) / span, -TurtleGrab.maxThrowSideways, TurtleGrab.maxThrowSideways)
        let dy = clamp(Double(latest.point.y - old.point.y) / span, -TurtleGrab.maxThrowUp, TurtleGrab.maxThrowDown)
        return CGVector(dx: dx, dy: dy)
    }

    // Let go: thrown by the latest pointer motion, or simply dropped. The swing carries into the fall
    mutating func release(throwing: Bool, at t: TimeInterval) {
        velocity = throwing ? Self.throwVelocity(history, at: t) : .zero
        foot = footInHand()
        last = t
    }

    // One step of the fall between the screen edges, down to the floor
    mutating func fall(to t: TimeInterval, minX: CGFloat, maxX: CGFloat, floor: CGFloat) -> Contact {
        let dt = max(0, step(to: t))
        velocity.dy += TurtleGrab.gravity * dt
        var x = Double(foot.x) + velocity.dx * dt
        var y = Double(foot.y) + velocity.dy * dt
        spin += (-tilt * TurtleFall.tiltSpring - spin * TurtleFall.tiltDamping) * dt
        tilt += spin * dt
        if x < Double(minX) {
            x = Double(minX)
            velocity.dx = -velocity.dx * TurtleFall.wallBounce
        }
        if x > Double(maxX) {
            x = Double(maxX)
            velocity.dx = -velocity.dx * TurtleFall.wallBounce
        }
        var contact = Contact.none
        if y >= Double(floor) {
            y = Double(floor)
            if !bounced, velocity.dy > TurtleFall.bounceSpeed {
                bounced = true
                velocity.dy = -velocity.dy * TurtleFall.bounceKeep
                velocity.dx *= TurtleFall.bounceSlide
                contact = .bounce
            } else {
                tilt = 0
                contact = .landed
            }
        }
        foot = CGPoint(x: x, y: y)
        return contact
    }
}

// MARK: - Pointer

// Lets the overlay take mouse events only while the pointer is over the turtle or a tappable bubble; everywhere else clicks reach the apps
// underneath. While events pass through, a global mouse-moved monitor (no extra permission) reports the pointer;
// while they are taken, the view's tracking area and its own mouse events do
final class TurtlePointer: NSObject {
    private let panel: NSPanel
    private let model: TurtleModel
    private var link: CADisplayLink?
    private var monitor: Any?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    // The panel takes mouse events
    private var catching = false
    private var dragging = false
    // A hand cursor was set and has to be put back
    private var handShown = false
    // A tappable bubble in view points, kept up to date while one is shown
    var tapArea: CGRect?
    var onTap: (() -> Void)?

    init(panel: NSPanel, model: TurtleModel, view: TurtleView) {
        self.panel = panel
        self.model = model
        super.init()
        view.pointer = self
        // Runs only while events are taken, so a pointer that left the turtle is let through on the next frame
        let link = view.displayLink(target: self, selector: #selector(frame))
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        self.link = link
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.moved() }
        }
        let app = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        watch(app, NSApplication.didResignActiveNotification, nil)
        watch(app, NSApplication.didChangeScreenParametersNotification, nil)
        watch(app, NSWindow.didChangeBackingPropertiesNotification, panel)
        watch(workspace, NSWorkspace.willSleepNotification, nil)
        // Entering or leaving a full-screen Space, where the panel is not shown
        watch(workspace, NSWorkspace.activeSpaceDidChangeNotification, nil)
    }

    private func watch(_ center: NotificationCenter, _ name: Notification.Name, _ object: AnyObject?) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.letGo() }
        }
        observers.append((center, token))
    }

    func stop() {
        link?.invalidate()
        link = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers = []
        letGo()
    }

    // In view coordinates: top-left origin, y down
    private func location() -> CGPoint {
        let p = NSEvent.mouseLocation, f = panel.frame
        return CGPoint(x: p.x - f.minX, y: f.maxY - p.y)
    }

    private var leftButtonDown: Bool {
        NSEvent.pressedMouseButtons & 1 != 0
    }

    // Take events only over the turtle or a tappable bubble, and never start while a button is held for another app's drag
    func moved() {
        guard !dragging else { return }
        let p = location()
        // On a full-screen Space the panel is not drawn, so the hidden turtle must not take events or change the cursor
        let over = panel.isOnActiveSpace && (model.contains(p, at: TurtleModel.now()) || tapArea?.contains(p) == true)
        setCatching(over && !leftButtonDown)
        // Other apps may reset the cursor while this app is in the background
        if catching, handShown { NSCursor.openHand.set() }
    }

    private func setCatching(_ next: Bool) {
        // Check the panel itself every time, so no path can leave it taking events
        if panel.ignoresMouseEvents == next { panel.ignoresMouseEvents = !next }
        if next != catching {
            catching = next
            if next, model.canGrab {
                NSCursor.openHand.set()
                handShown = true
            } else if handShown {
                NSCursor.arrow.set()
                handShown = false
            }
        }
        link?.isPaused = !(catching || dragging)
    }

    @objc private func frame(_ link: CADisplayLink) {
        guard dragging else {
            moved()
            return
        }
        // The button is up although no mouseUp arrived: release with the throw as usual
        if !leftButtonDown {
            mouseUp()
        } else if !model.isHeld {
            // The neck needed to grow and the turtle slipped out of the hand
            endDrag()
        }
    }

    func mouseDown() {
        // The bubble wins over the turtle underneath it
        if let tapArea, tapArea.contains(location()) {
            onTap?()
            return
        }
        guard model.grab(at: location(), at: TurtleModel.now()) else { return }
        dragging = true
        NSCursor.closedHand.set()
        handShown = true
        link?.isPaused = false
    }

    func mouseDragged() {
        guard dragging else { return }
        guard model.isHeld else {
            endDrag()
            return
        }
        model.moveGrab(to: location(), at: TurtleModel.now())
        NSCursor.closedHand.set()
    }

    func mouseUp() {
        guard dragging else { return }
        model.release(at: TurtleModel.now())
        endDrag()
    }

    // Always ends with events passing through, wherever the pointer is
    private func endDrag() {
        dragging = false
        if handShown {
            NSCursor.arrow.set()
            handShown = false
        }
        catching = true
        setCatching(false)
    }

    // Lose the hand and let events through: the app went inactive, the screen changed, the system sleeps, or the overlay closes
    private func letGo() {
        if dragging {
            mouseUp()
        } else {
            setCatching(false)
        }
    }
}
