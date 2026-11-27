import AppKit
import SwiftUI

// Drawing box and neck geometry in drawing units (a drawing is `units` wide, feet on y = foot)
enum TurtleArt {
    static let units = 500.0
    static let foot = 400.0
    // The front and back looks are drawn a little smaller; this lifts and enlarges them to the same foot line
    static let raisedPivot = CGPoint(x: 250, y: 382)
    static let raisedShift = 18.0
    static let raisedScale = 1.05
    // The long view is drawn in coordinates offset from the box by this much
    static let longOffset = CGSize(width: 2, height: -1002)
    // Neck column centre and width in long view coordinates
    static let neckCentre = (NeckArt.left + NeckArt.right) / 2
    static let neckWidth = NeckArt.right - NeckArt.left
    // A neck column with its head reaches from faceEdge on the face side to right + backEdge on the back
    static let faceEdge = 9.0
    static let backEdge = 3.5
    // Once the head is this far below the screen top, its upper part shows at the bottom of the next column
    static let headTop = 20.0
    static let neckLine = 7.0
}

// Frame pacing: the full display rate while the turtle moves quickly and around each blink, a low rate otherwise
enum TurtlePace {
    static let idleRate: Float = 12
    // A blink closes and opens the eyes within this part of its period, with a little room on both sides
    static let blinkWindow = 0.45...0.5
}

private func srgb(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

private extension CGColor {
    static let skin = srgb(0x34A8A8)
    static let ink = srgb(0x0F3838)
    static let shell = srgb(0x008180)
    static let plates = srgb(0x014A49)
    static let light = srgb(0xCFF4F0)
}

private extension Path {
    mutating func m(_ x: Double, _ y: Double) {
        move(to: CGPoint(x: x, y: y))
    }

    mutating func l(_ x: Double, _ y: Double) {
        addLine(to: CGPoint(x: x, y: y))
    }

    mutating func c(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double, _ y: Double) {
        addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
    }

    mutating func z() {
        closeSubpath()
    }
}

private func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, rotated degrees: Double) -> Path {
    Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
        .applying(rotation(degrees, about: CGPoint(x: cx, y: cy)))
}

// Move the origin to `pivot`, apply `inner`, move back
private func around(_ pivot: CGPoint, _ inner: CGAffineTransform) -> CGAffineTransform {
    CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
        .concatenating(inner)
        .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))
}

private func rotation(_ degrees: Double, about pivot: CGPoint) -> CGAffineTransform {
    around(pivot, CGAffineTransform(rotationAngle: degrees * .pi / 180))
}

// A turn by `degrees` with a move of (dx, dy) along the turned axes
private func swing(_ degrees: Double, _ dx: Double, _ dy: Double, about pivot: CGPoint) -> CGAffineTransform {
    around(pivot, CGAffineTransform(translationX: dx, y: dy).concatenating(CGAffineTransform(rotationAngle: degrees * .pi / 180)))
}

private func squash(_ height: Double, about pivot: CGPoint) -> CGAffineTransform {
    around(pivot, CGAffineTransform(scaleX: 1, y: max(0.001, height)))
}

struct ArtShape {
    let path: Path
    let fill: CGColor?
    let stroke: CGColor?
    let width: Double
    let roundCap: Bool

    init(_ path: Path, fill: CGColor? = nil, stroke: CGColor? = nil, width: Double = 0, roundCap: Bool = false) {
        self.path = path
        self.fill = fill
        self.stroke = stroke
        self.width = width
        self.roundCap = roundCap
    }

    func layer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.anchorPoint = .zero
        layer.path = path.cgPath
        layer.fillColor = fill
        layer.strokeColor = stroke
        layer.lineWidth = width
        layer.lineCap = roundCap ? .round : .butt
        layer.lineJoin = .miter
        layer.miterLimit = 4
        return layer
    }
}

enum PartRole {
    case still, tail, legA, legB, head, eyes, closedEyes
}

// One group of the artwork; moving parts turn around a pivot placed at `origin` of their bounds
struct ArtPart {
    let role: PartRole
    let shapes: [ArtShape]
    let children: [ArtPart]
    let bounds: CGRect
    let pivot: CGPoint

    init(_ role: PartRole, origin: UnitPoint = .center, shapes: [ArtShape], children: [ArtPart] = []) {
        self.role = role
        self.shapes = shapes
        self.children = children
        let all = shapes.map { $0.path.boundingRect } + children.map(\.bounds)
        bounds = all.dropFirst().reduce(all[0]) { $0.union($1) }
        pivot = CGPoint(x: bounds.minX + bounds.width * origin.x, y: bounds.minY + bounds.height * origin.y)
    }
}

private func group() -> CALayer {
    let layer = CALayer()
    layer.anchorPoint = .zero
    return layer
}

private func setTransform(_ layer: CALayer, _ t: CGAffineTransform) {
    if layer.affineTransform() != t { layer.setAffineTransform(t) }
}

private func setHidden(_ layer: CALayer, _ hidden: Bool) {
    if layer.isHidden != hidden { layer.isHidden = hidden }
}

// MARK: - Looks

// The layers of one look, built once; a frame only moves, turns, squashes or hides them
private final class LookLayers {
    let root = group()
    private var moving: [(part: ArtPart, layer: CALayer)] = []

    init(_ parts: [ArtPart], base: CGAffineTransform) {
        root.setAffineTransform(base)
        for part in parts {
            root.addSublayer(make(part))
        }
    }

    private func make(_ part: ArtPart) -> CALayer {
        let layer = group()
        for shape in part.shapes {
            layer.addSublayer(shape.layer())
        }
        for child in part.children {
            layer.addSublayer(make(child))
        }
        if part.role != .still { moving.append((part, layer)) }
        return layer
    }

    func apply(_ frame: TurtleFrame) {
        // Only the front look has drawn closed eyes; they replace the open ones
        let closable = frame.look == .front
        for (part, layer) in moving {
            switch part.role {
            case .still:
                break
            case .closedEyes:
                setHidden(layer, !frame.eyesClosed)
            case .eyes:
                setHidden(layer, closable && frame.eyesClosed)
                setTransform(layer, squash(frame.eyeOpen, about: part.pivot))
            case .tail:
                setTransform(layer, rotation(frame.tailAngle, about: part.pivot))
            case .legA:
                setTransform(layer, swing(frame.frontLeg.angle, 0, frame.frontLeg.lift, about: part.pivot))
            case .legB:
                setTransform(layer, swing(frame.backLeg.angle, 0, frame.backLeg.lift, about: part.pivot))
            case .head:
                setTransform(layer, swing(frame.headAngle, frame.headShift, frame.headLift, about: part.pivot))
            }
        }
    }

    static func base(_ look: TurtleLook) -> CGAffineTransform {
        switch look {
        case .front, .back, .backLeft:
            let s = TurtleArt.raisedScale
            return around(TurtleArt.raisedPivot, CGAffineTransform(scaleX: s, y: s).concatenating(CGAffineTransform(translationX: 0, y: TurtleArt.raisedShift)))
        case .long:
            return CGAffineTransform(translationX: TurtleArt.longOffset.width, y: TurtleArt.longOffset.height)
        case .side, .frontLeft:
            return .identity
        }
    }

    static func parts(_ look: TurtleLook) -> [ArtPart] {
        switch look {
        case .side: TurtleParts.side
        case .front: TurtleParts.front
        case .back: TurtleParts.back
        case .frontLeft: TurtleParts.frontLeft
        case .backLeft: TurtleParts.backLeft
        case .long: TurtleParts.long
        }
    }
}

// MARK: - Neck

// Head outline between resting (0) and stretched (1); the outline stroke leaves the neck side open once stretching starts
private struct HeadOutline {
    let fill: CGPath
    let stroke: CGPath

    static let resting = HeadOutline(morph: 0)
    static let stretched = HeadOutline(morph: 1)

    static func at(_ morph: Double) -> HeadOutline {
        morph <= 0 ? resting : morph >= 1 ? stretched : HeadOutline(morph: morph)
    }

    private init(morph o: Double) {
        let a = NeckArt.restingHead, b = NeckArt.stretchedHead
        let last = a.count / 2 - 1
        func point(_ i: Int) -> CGPoint {
            CGPoint(x: a[2 * i] + (b[2 * i] - a[2 * i]) * o, y: a[2 * i + 1] + (b[2 * i + 1] - a[2 * i + 1]) * o)
        }
        let points = (0...last).map(point)
        let outline = CGMutablePath()
        outline.addLines(between: points)
        outline.closeSubpath()
        fill = outline
        guard o >= 0.002 else {
            stroke = outline
            return
        }
        let visible = (1 - (1 - NeckArt.openOutline) * o) * Double(last)
        let n = Int(visible), f = visible - Double(n)
        var open = Array(points[0...n])
        if f > 0, n < last {
            let p = point(n), q = point(n + 1)
            open.append(CGPoint(x: p.x + (q.x - p.x) * f, y: p.y + (q.y - p.y) * f))
        }
        let line = CGMutablePath()
        line.addLines(between: open)
        stroke = line
    }
}

// One head on the end of the long neck: collar, outline and eyes
private final class NeckHeadLayers {
    let root = group()
    private let collar = group()
    private let fill = ArtShape(Path(), fill: .skin).layer()
    private let line = ArtShape(Path(), stroke: .ink, width: TurtleArt.neckLine, roundCap: true).layer()
    private let eyes = group()
    private static let eyePart = ArtPart(.eyes, shapes: TurtleParts.headEyes)
    private var morph = -1.0

    init() {
        for shape in TurtleParts.collar {
            collar.addSublayer(shape.layer())
        }
        for shape in TurtleParts.headEyes {
            eyes.addSublayer(shape.layer())
        }
        for layer in [collar, fill, line, eyes] {
            root.addSublayer(layer)
        }
    }

    func apply(offset: CGPoint?, morph: Double, collar shown: Bool, eyeOpen: Double) {
        guard let offset else {
            setHidden(root, true)
            return
        }
        setHidden(root, false)
        setTransform(root, CGAffineTransform(translationX: offset.x, y: offset.y))
        setHidden(collar, !shown)
        if morph != self.morph {
            self.morph = morph
            let outline = HeadOutline.at(morph)
            fill.path = outline.fill
            line.path = outline.stroke
        }
        setTransform(eyes, squash(eyeOpen, about: Self.eyePart.pivot))
    }
}

// Straight neck tubes: filled, with lines on the two long sides only
private final class TubeLayers {
    let fill = ArtShape(Path(), fill: .skin).layer()
    let sides = ArtShape(Path(), stroke: .ink, width: TurtleArt.neckLine).layer()

    func apply(_ tubes: [NeckTube]) {
        let pad = NeckStretch.tubePad
        let half = TurtleArt.neckWidth / 2
        let area = CGMutablePath(), lines = CGMutablePath()
        for t in tubes {
            area.addRect(CGRect(x: t.x - half, y: t.top - pad, width: 2 * half, height: t.bottom - t.top + 2 * pad))
            for x in [t.x - half, t.x + half] {
                lines.move(to: CGPoint(x: x, y: t.top - pad))
                lines.addLine(to: CGPoint(x: x, y: t.bottom + pad))
            }
        }
        fill.path = area
        sides.path = lines
    }
}

// Neck layers in the long view: wrapped columns and their heads behind the body, the rising neck and its head in front
private final class NeckLayers {
    let behind = group()
    let front = group()
    private let backTubes = TubeLayers()
    private let backHeads = [NeckHeadLayers(), NeckHeadLayers()]
    private let frontTubes = TubeLayers()
    private let rootFill = ArtShape(TurtlePaths.rootFill, fill: .skin).layer()
    private let rootLine = ArtShape(TurtlePaths.rootLine, stroke: .ink, width: TurtleArt.neckLine).layer()
    private let resting = ArtShape(Path(), fill: .skin, stroke: .ink, width: TurtleArt.neckLine).layer()
    private let frontHead = NeckHeadLayers()
    private var layout: NeckLayout?

    init() {
        for layer in [backTubes.fill, backTubes.sides] + backHeads.map(\.root) {
            behind.addSublayer(layer)
        }
        for layer in [frontTubes.fill, frontTubes.sides, rootFill, rootLine, resting, frontHead.root] {
            front.addSublayer(layer)
        }
    }

    // The resting neck squeezed toward the shell: narrower and pulled down by `drop`
    private static func restingNeck(drop: Double) -> CGPath {
        let k = (NeckArt.bottom - NeckArt.top - drop) / (NeckArt.bottom - NeckArt.top)
        let sx = 1 - (1 - NeckStretch.restWidth) * drop / NeckStretch.full
        let t = CGAffineTransform(a: sx, b: 0, c: 0, d: k, tx: NeckArt.centreX * (1 - sx), ty: NeckArt.bottom * (1 - k))
        return TurtlePaths.neck.applying(t).cgPath
    }

    func apply(_ neck: NeckLayout, eyeOpen: Double) {
        if neck != layout {
            layout = neck
            backTubes.apply(neck.back)
            frontTubes.apply(neck.front)
            for layer in [rootFill, rootLine] {
                setHidden(layer, !neck.extended)
            }
            setHidden(resting, neck.extended)
            if !neck.extended { resting.path = Self.restingNeck(drop: neck.drop) }
        }
        for (i, head) in backHeads.enumerated() {
            head.apply(offset: i < neck.backHeads.count ? neck.backHeads[i] : nil, morph: 1, collar: true, eyeOpen: eyeOpen)
        }
        frontHead.apply(offset: neck.frontHeads.first, morph: neck.morph, collar: neck.extended, eyeOpen: eyeOpen)
    }
}

// MARK: - View

// Draws the turtle with one Core Animation layer per part. Paths are set once; a frame only changes layer transforms,
// and frames come at the full display rate only while something moves quickly
final class TurtleView: NSView {
    private let model: TurtleModel
    private let figure = group()
    private var looks: [TurtleLook: LookLayers] = [:]
    private let neck = NeckLayers()
    private var shown: TurtleLook?
    private var link: CADisplayLink?
    private var fullRate: Bool?

    init(model: TurtleModel) {
        self.model = model
        super.init(frame: .zero)
        let root = CALayer()
        root.isGeometryFlipped = true
        layer = root
        wantsLayer = true
        root.addSublayer(figure)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func start() {
        guard link == nil else { return }
        let link = displayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
        observe()
        render()
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        render()
    }

    // Draw right away whenever the model changes, so turns and new motions start on time between slow frames
    private func observe() {
        guard link != nil else { return }
        withObservationTracking {
            _ = model.frame(at: TurtleModel.now())
            _ = model.fullRateUntil
        } onChange: { [self] in
            // Held only until the next change; stop() ends the chain
            Task { @MainActor in
                render()
                observe()
            }
        }
    }

    private func render() {
        guard link != nil else { return }
        let t = TurtleModel.now()
        draw(model.frame(at: t))
        pace(at: t)
    }

    func draw(_ frame: TurtleFrame) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let look = looks[frame.look] ?? makeLook(frame.look)
        if shown != frame.look {
            for (key, layers) in looks {
                setHidden(layers.root, key != frame.look)
            }
            shown = frame.look
        }
        look.apply(frame)
        if let layout = frame.neck { neck.apply(layout, eyeOpen: frame.eyeOpen) }
        setTransform(figure, placement(frame))
        CATransaction.commit()
    }

    private func makeLook(_ key: TurtleLook) -> LookLayers {
        let look = LookLayers(LookLayers.parts(key), base: LookLayers.base(key))
        if key == .long {
            look.root.insertSublayer(neck.behind, at: 0)
            look.root.addSublayer(neck.front)
        }
        figure.addSublayer(look.root)
        looks[key] = look
        matchScale(look.root)
        return look
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        matchBackingScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        matchBackingScale()
    }

    // Shape layers are drawn at their contentsScale; layers made in code start at 1, so match the window's backing scale
    private func matchBackingScale() {
        guard let root = layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        matchScale(root)
        CATransaction.commit()
    }

    private func matchScale(_ layer: CALayer) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        if layer.contentsScale != scale { layer.contentsScale = scale }
        for sublayer in layer.sublayers ?? [] {
            matchScale(sublayer)
        }
    }

    // Drawing units to view points: mirror, scale to size, breathe or waddle, hop, and stand on the floor
    private func placement(_ f: TurtleFrame) -> CGAffineTransform {
        let units = TurtleArt.units, size = Double(f.size)
        let anchor = CGPoint(x: size / 2, y: size * TurtleSize.footLine)
        var t = f.flipped ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: units, ty: 0) : .identity
        t = t.concatenating(CGAffineTransform(scaleX: size / units, y: size / units))
        t = t.concatenating(around(anchor, CGAffineTransform(scaleX: f.bobScale.width, y: f.bobScale.height)))
        t = t.concatenating(rotation(f.bobAngle, about: anchor))
        t = t.concatenating(CGAffineTransform(translationX: 0, y: f.bobOffset))
        t = t.concatenating(around(anchor, CGAffineTransform(scaleX: f.hopScale.width, y: f.hopScale.height)))
        t = t.concatenating(CGAffineTransform(translationX: 0, y: f.hopOffset))
        return t.concatenating(CGAffineTransform(translationX: Double(f.x) - anchor.x, y: Double(f.y) - anchor.y))
    }

    private func pace(at t: TimeInterval) {
        guard let link else { return }
        if model.reduceMotion {
            link.isPaused = true
            return
        }
        let period = TurtleEyes.blinkPeriod
        let phase = (t - model.blinkOrigin).truncatingRemainder(dividingBy: period) / period
        // Switch up one slow frame before the blink starts
        let lead = 1 / Double(TurtlePace.idleRate) / period
        let blinking = (TurtlePace.blinkWindow.lowerBound - lead)...TurtlePace.blinkWindow.upperBound
        let full = t < model.fullRateUntil || blinking.contains(phase)
        guard full != fullRate else { return }
        fullRate = full
        let idle = TurtlePace.idleRate
        link.preferredFrameRateRange = full ? .default : CAFrameRateRange(minimum: idle, maximum: idle, preferred: idle)
    }
}

// Turtle artwork paths in a 500 x 500 box; the long view is drawn in its own coordinates, see TurtleArt.longOffset
enum TurtlePaths {
    static let sideTail1 = Path { p in
        p.m(408.855, 228.826)
        p.c(412.396, 224.207, 419.301, 218.217, 426.407, 214.177)
        p.c(429.973, 212.149, 433.8, 210.49, 437.451, 209.814)
        p.c(441.079, 209.141, 445.042, 209.359, 448.236, 211.808)
        p.c(451.5, 214.31, 452.555, 218.053, 452.555, 221.662)
        p.c(452.555, 225.234, 451.547, 229.132, 450.165, 232.823)
        p.c(447.389, 240.233, 442.718, 247.799, 439.343, 252.202)
        p.c(436.117, 256.409, 432.431, 260.553, 428.115, 262.623)
        p.c(425.865, 263.702, 423.382, 264.251, 420.716, 263.921)
        p.c(418.069, 263.592, 415.513, 262.432, 413.042, 260.537)
        p.c(403.129, 252.936, 401.255, 238.739, 408.855, 228.826)
        p.z()
    }
    static let sideLegA1 = Path { p in
        p.m(153.193, 304.893)
        p.c(144.658, 309.835, 132.828, 320.281, 124.272, 331.532)
        p.c(119.985, 337.169, 116.37, 343.2, 114.45, 349.022)
        p.c(112.538, 354.817, 112.153, 360.915, 115.156, 366.13)
        p.c(118.202, 371.421, 123.578, 373.81, 129.388, 374.542)
        p.c(135.166, 375.271, 141.849, 374.448, 148.471, 372.886)
        p.c(161.745, 369.754, 175.805, 363.399, 184.107, 358.591)
        p.c(192.198, 353.906, 199.787, 348.668, 204.04, 342.192)
        p.c(206.222, 338.869, 207.572, 335.155, 207.622, 331.02)
        p.c(207.673, 326.903, 206.431, 322.648, 203.888, 318.231)
        p.c(193.692, 300.519, 170.983, 294.593, 153.193, 304.893)
        p.z()
    }
    static let sideBody1 = Path { p in
        p.m(274, 108.5)
        p.c(358.776, 108.5, 427.5, 177.224, 427.5, 262)
        p.c(427.5, 283.185, 423.204, 300.216, 415.23, 313.799)
        p.c(407.247, 327.398, 395.718, 337.301, 381.649, 344.438)
        p.c(353.696, 358.617, 315.444, 362, 274, 362)
        p.c(232.556, 362, 194.304, 358.617, 166.351, 344.438)
        p.c(152.282, 337.301, 140.753, 327.398, 132.77, 313.799)
        p.c(124.796, 300.216, 120.5, 283.185, 120.5, 262)
        p.c(120.5, 177.224, 189.224, 108.5, 274, 108.5)
        p.z()
    }
    static let sideBody2 = Path { p in
        p.m(424, 262)
        p.c(424, 344.843, 356.843, 301.5, 274, 301.5)
        p.c(191.157, 301.5, 124, 344.843, 124, 262)
        p.c(124, 179.157, 191.157, 112, 274, 112)
        p.c(356.843, 112, 424, 179.157, 424, 262)
        p.z()
    }
    static let sideLegA2 = Path { p in
        p.m(359.153, 317.533)
        p.c(367.545, 325.925, 378.075, 341.819, 384.506, 357.659)
        p.c(387.728, 365.592, 390.014, 373.735, 390.397, 381.077)
        p.c(390.778, 388.396, 389.278, 395.432, 384.293, 400.417)
        p.c(379.247, 405.464, 372.434, 406.613, 365.478, 405.695)
        p.c(358.56, 404.782, 351.036, 401.787, 343.767, 397.913)
        p.c(329.203, 390.152, 314.733, 378.352, 306.533, 370.152)
        p.c(298.507, 362.126, 291.361, 353.704, 288.492, 344.93)
        p.c(287.027, 340.445, 286.651, 335.8, 287.879, 331.081)
        p.c(289.102, 326.38, 291.847, 321.873, 296.187, 317.533)
        p.c(313.575, 300.146, 341.765, 300.146, 359.153, 317.533)
        p.z()
    }
    static let sideLegB1 = Path { p in
        p.m(437.337, 281.264)
        p.c(445.781, 283.514, 458.241, 289.726, 468.077, 297.398)
        p.c(473.007, 301.243, 477.471, 305.601, 480.439, 310.199)
        p.c(483.395, 314.778, 485.128, 320.026, 483.698, 325.334)
        p.c(482.246, 330.725, 478.094, 334.113, 473.23, 336.142)
        p.c(468.403, 338.155, 462.466, 339.027, 456.449, 339.246)
        p.c(444.387, 339.686, 430.946, 337.533, 422.767, 335.353)
        p.c(414.825, 333.237, 407.094, 330.506, 401.94, 325.871)
        p.c(399.287, 323.485, 397.263, 320.55, 396.278, 316.935)
        p.c(395.297, 313.338, 395.415, 309.332, 396.609, 304.9)
        p.c(401.392, 287.143, 419.615, 276.54, 437.337, 281.264)
        p.z()
    }
    static let sideHead1 = Path { p in
        p.m(166, 77.5)
        p.c(250.776, 77.5, 319.5, 146.224, 319.5, 231)
        p.c(319.5, 252.185, 315.204, 269.216, 307.23, 282.799)
        p.c(299.247, 296.398, 287.718, 306.301, 273.649, 313.438)
        p.c(245.696, 327.617, 207.444, 331, 166, 331)
        p.c(124.556, 331, 86.304, 327.617, 58.3506, 313.438)
        p.c(44.2823, 306.301, 32.7527, 296.398, 24.7695, 282.799)
        p.c(16.7962, 269.216, 12.5, 252.185, 12.5, 231)
        p.c(12.5, 146.224, 81.2243, 77.5, 166, 77.5)
        p.z()
    }
    static let frontLegB1 = Path { p in
        p.m(129.996, 304.189)
        p.c(122.324, 304.189, 109.591, 306.724, 98.8062, 311.279)
        p.c(93.4268, 313.552, 88.7492, 316.238, 85.4731, 319.189)
        p.c(82.1802, 322.156, 80.6598, 325.05, 80.6597, 327.807)
        p.c(80.6597, 330.479, 82.093, 333, 85.2671, 335.434)
        p.c(88.4702, 337.89, 93.0877, 339.952, 98.4751, 341.594)
        p.c(109.223, 344.868, 122.061, 346.182, 129.996, 346.182)
        p.c(138.168, 346.182, 144.859, 345.476, 149.447, 343.148)
        p.c(151.652, 342.03, 153.296, 340.571, 154.417, 338.66)
        p.c(155.548, 336.734, 156.284, 334.116, 156.284, 330.478)
        p.c(156.284, 315.959, 144.514, 304.19, 129.996, 304.189)
        p.z()
    }
    static let frontLegA1 = Path { p in
        p.m(369.977, 304.189)
        p.c(377.648, 304.189, 390.381, 306.724, 401.166, 311.279)
        p.c(406.545, 313.552, 411.223, 316.238, 414.499, 319.189)
        p.c(417.792, 322.156, 419.312, 325.05, 419.312, 327.807)
        p.c(419.312, 330.479, 417.879, 333, 414.705, 335.434)
        p.c(411.502, 337.89, 406.884, 339.952, 401.497, 341.594)
        p.c(390.75, 344.868, 377.912, 346.182, 369.977, 346.182)
        p.c(361.804, 346.182, 355.113, 345.476, 350.525, 343.148)
        p.c(348.32, 342.03, 346.676, 340.571, 345.555, 338.66)
        p.c(344.424, 336.734, 343.688, 334.116, 343.688, 330.478)
        p.c(343.689, 315.959, 355.458, 304.19, 369.977, 304.189)
        p.z()
    }
    static let frontBody1 = Path { p in
        p.m(249.435, 134.848)
        p.c(327.068, 134.848, 389.989, 197.622, 389.989, 275.04)
        p.c(389.989, 294.404, 386.057, 309.463, 379.145, 321.208)
        p.c(372.242, 332.937, 362.232, 341.592, 349.687, 347.939)
        p.c(324.42, 360.724, 289.161, 364.022, 249.435, 364.022)
        p.c(209.71, 364.022, 174.451, 360.724, 149.184, 347.939)
        p.c(136.639, 341.592, 126.629, 332.937, 119.726, 321.208)
        p.c(112.814, 309.463, 108.882, 294.404, 108.882, 275.04)
        p.c(108.882, 197.622, 171.802, 134.848, 249.435, 134.848)
        p.z()
    }
    static let frontBody2 = Path { p in
        p.m(249.853, 134.848)
        p.c(330.826, 134.848, 396.469, 200.49, 396.469, 281.463)
        p.c(396.469, 301.851, 392.313, 313.554, 385.673, 320.189)
        p.c(379.068, 326.792, 369.252, 329.128, 355.981, 328.894)
        p.c(342.704, 328.659, 326.855, 325.887, 308.757, 323.095)
        p.c(290.788, 320.322, 270.84, 317.577, 249.853, 317.577)
        p.c(228.866, 317.577, 208.919, 320.322, 190.95, 323.095)
        p.c(172.852, 325.887, 157.003, 328.659, 143.726, 328.894)
        p.c(130.455, 329.128, 120.638, 326.792, 114.033, 320.189)
        p.c(107.394, 313.554, 103.238, 301.851, 103.238, 281.463)
        p.c(103.238, 200.49, 168.88, 134.848, 249.853, 134.848)
        p.z()
    }
    static let frontLegA2 = Path { p in
        p.m(126.281, 310.618)
        p.c(116.924, 316.02, 103.305, 327.98, 93.4548, 341.004)
        p.c(88.5385, 347.505, 84.7047, 354.085, 82.7615, 360.073)
        p.c(80.8112, 366.082, 80.9045, 371.02, 83.0662, 374.765)
        p.c(85.1858, 378.435, 89.0909, 380.597, 94.8066, 381.348)
        p.c(100.559, 382.103, 107.686, 381.345, 115.34, 379.57)
        p.c(130.62, 376.027, 147.017, 368.67, 156.603, 363.136)
        p.c(161.05, 360.568, 163.672, 357.704, 165.123, 354.733)
        p.c(166.577, 351.756, 167, 348.373, 166.54, 344.527)
        p.c(165.596, 336.644, 161.051, 327.504, 155.364, 317.654)
        p.c(152.529, 312.743, 150.361, 309.3, 148.412, 306.97)
        p.c(146.485, 304.666, 145.059, 303.804, 143.804, 303.52)
        p.c(142.508, 303.227, 140.741, 303.397, 137.806, 304.581)
        p.c(134.866, 305.766, 131.213, 307.77, 126.281, 310.618)
        p.z()
    }
    static let frontLegB2 = Path { p in
        p.m(374.837, 310.618)
        p.c(384.195, 316.02, 397.814, 327.98, 407.664, 341.004)
        p.c(412.58, 347.505, 416.414, 354.085, 418.357, 360.073)
        p.c(420.307, 366.082, 420.214, 371.02, 418.052, 374.765)
        p.c(415.933, 378.435, 412.028, 380.597, 406.312, 381.348)
        p.c(400.56, 382.103, 393.433, 381.345, 385.779, 379.57)
        p.c(370.499, 376.027, 354.102, 368.67, 344.516, 363.136)
        p.c(340.069, 360.568, 337.447, 357.704, 335.996, 354.733)
        p.c(334.541, 351.756, 334.119, 348.373, 334.579, 344.527)
        p.c(335.523, 336.644, 340.067, 327.504, 345.755, 317.654)
        p.c(348.59, 312.743, 350.758, 309.3, 352.707, 306.97)
        p.c(354.634, 304.666, 356.06, 303.804, 357.315, 303.52)
        p.c(358.61, 303.227, 360.378, 303.397, 363.313, 304.581)
        p.c(366.253, 305.766, 369.906, 307.77, 374.837, 310.618)
        p.z()
    }
    static let frontHead1 = Path { p in
        p.m(249.853, 99.8506)
        p.c(330.826, 99.8506, 396.469, 165.492, 396.469, 246.466)
        p.c(396.469, 266.718, 392.367, 282.48, 385.147, 294.779)
        p.c(377.937, 307.062, 367.482, 316.121, 354.389, 322.763)
        p.c(328.027, 336.136, 291.253, 339.581, 249.853, 339.581)
        p.c(208.454, 339.581, 171.68, 336.136, 145.318, 322.763)
        p.c(132.225, 316.121, 121.771, 307.062, 114.56, 294.779)
        p.c(107.34, 282.48, 103.238, 266.718, 103.238, 246.466)
        p.c(103.238, 165.493, 168.88, 99.8507, 249.853, 99.8506)
        p.z()
    }
    static let frontClosedEyes1 = Path { p in
        p.m(231.546, 273.916)
        p.c(231.189, 275.25, 224.582, 270.497, 215.513, 268.067)
        p.c(206.444, 265.637, 198.347, 266.45, 198.704, 265.116)
        p.c(199.062, 263.783, 207.739, 260.808, 216.807, 263.238)
        p.c(225.876, 265.668, 231.903, 272.583, 231.546, 273.916)
        p.z()
    }
    static let frontClosedEyes2 = Path { p in
        p.m(300.171, 265.133)
        p.c(300.529, 266.467, 292.431, 265.654, 283.362, 268.084)
        p.c(274.293, 270.514, 267.687, 275.266, 267.33, 273.933)
        p.c(266.972, 272.599, 272.999, 265.684, 282.068, 263.254)
        p.c(291.137, 260.824, 299.814, 263.799, 300.171, 265.133)
        p.z()
    }
    static let backHead1 = Path { p in
        p.m(250, 93.3867)
        p.c(327.106, 93.3867, 389.613, 155.895, 389.613, 233.002)
        p.c(389.613, 252.287, 385.707, 267.285, 378.842, 278.98)
        p.c(371.986, 290.66, 362.043, 299.277, 349.584, 305.598)
        p.c(324.489, 318.328, 289.466, 321.613, 250, 321.613)
        p.c(210.534, 321.613, 175.511, 318.328, 150.416, 305.598)
        p.c(137.957, 299.277, 128.014, 290.66, 121.158, 278.98)
        p.c(114.293, 267.285, 110.387, 252.287, 110.387, 233.002)
        p.c(110.387, 155.895, 172.894, 93.3867, 250, 93.3867)
        p.z()
    }
    static let backLegB1 = Path { p in
        p.m(129.996, 304.267)
        p.c(122.324, 304.267, 109.591, 306.801, 98.8062, 311.356)
        p.c(93.4268, 313.629, 88.7492, 316.315, 85.4731, 319.267)
        p.c(82.1802, 322.234, 80.6598, 325.127, 80.6597, 327.884)
        p.c(80.6597, 330.556, 82.093, 333.077, 85.2671, 335.511)
        p.c(88.4702, 337.967, 93.0877, 340.029, 98.4751, 341.671)
        p.c(109.223, 344.946, 122.061, 346.259, 129.996, 346.259)
        p.c(138.168, 346.259, 144.859, 345.553, 149.447, 343.226)
        p.c(151.652, 342.107, 153.296, 340.648, 154.417, 338.737)
        p.c(155.548, 336.811, 156.284, 334.193, 156.284, 330.555)
        p.c(156.284, 316.036, 144.514, 304.267, 129.996, 304.267)
        p.z()
    }
    static let backLegA1 = Path { p in
        p.m(369.977, 304.267)
        p.c(377.648, 304.267, 390.381, 306.801, 401.166, 311.356)
        p.c(406.545, 313.629, 411.223, 316.315, 414.499, 319.267)
        p.c(417.792, 322.234, 419.312, 325.127, 419.312, 327.884)
        p.c(419.312, 330.556, 417.879, 333.077, 414.705, 335.511)
        p.c(411.502, 337.967, 406.884, 340.029, 401.497, 341.671)
        p.c(390.75, 344.946, 377.912, 346.259, 369.977, 346.259)
        p.c(361.804, 346.259, 355.113, 345.553, 350.525, 343.226)
        p.c(348.32, 342.107, 346.676, 340.648, 345.555, 338.737)
        p.c(344.424, 336.811, 343.688, 334.193, 343.688, 330.555)
        p.c(343.689, 316.036, 355.458, 304.267, 369.977, 304.267)
        p.z()
    }
    static let backBody1 = Path { p in
        p.m(249.435, 134.925)
        p.c(327.068, 134.925, 389.989, 197.699, 389.989, 275.117)
        p.c(389.989, 294.481, 386.057, 309.541, 379.145, 321.285)
        p.c(372.242, 333.014, 362.232, 341.669, 349.687, 348.017)
        p.c(324.42, 360.801, 289.161, 364.1, 249.435, 364.1)
        p.c(209.71, 364.1, 174.451, 360.801, 149.184, 348.017)
        p.c(136.639, 341.669, 126.629, 333.014, 119.726, 321.285)
        p.c(112.814, 309.541, 108.882, 294.481, 108.882, 275.117)
        p.c(108.882, 197.699, 171.802, 134.925, 249.435, 134.925)
        p.z()
    }
    static let backBody2 = Path { p in
        p.m(249.853, 134.925)
        p.c(330.826, 134.925, 396.469, 200.567, 396.469, 281.54)
        p.c(396.469, 301.928, 392.313, 313.631, 385.673, 320.267)
        p.c(379.068, 326.869, 369.252, 329.206, 355.981, 328.971)
        p.c(342.704, 328.736, 326.855, 325.964, 308.757, 323.172)
        p.c(290.788, 320.399, 270.84, 317.654, 249.853, 317.654)
        p.c(228.866, 317.654, 208.919, 320.399, 190.95, 323.172)
        p.c(172.852, 325.964, 157.003, 328.736, 143.726, 328.971)
        p.c(130.455, 329.206, 120.638, 326.869, 114.033, 320.267)
        p.c(107.394, 313.631, 103.238, 301.928, 103.238, 281.54)
        p.c(103.238, 200.567, 168.88, 134.925, 249.853, 134.925)
        p.z()
    }
    static let backLegA2 = Path { p in
        p.m(126.281, 310.695)
        p.c(116.924, 316.097, 103.305, 328.057, 93.4548, 341.081)
        p.c(88.5385, 347.582, 84.7047, 354.162, 82.7615, 360.15)
        p.c(80.8112, 366.159, 80.9045, 371.098, 83.0662, 374.842)
        p.c(85.1858, 378.513, 89.0909, 380.674, 94.8066, 381.425)
        p.c(100.559, 382.18, 107.686, 381.422, 115.34, 379.648)
        p.c(130.62, 376.104, 147.017, 368.747, 156.603, 363.213)
        p.c(161.05, 360.645, 163.672, 357.781, 165.123, 354.81)
        p.c(166.577, 351.833, 167, 348.45, 166.54, 344.604)
        p.c(165.596, 336.721, 161.051, 327.582, 155.364, 317.731)
        p.c(152.529, 312.82, 150.361, 309.377, 148.412, 307.047)
        p.c(146.485, 304.743, 145.059, 303.881, 143.804, 303.597)
        p.c(142.508, 303.304, 140.741, 303.475, 137.806, 304.658)
        p.c(134.866, 305.843, 131.213, 307.847, 126.281, 310.695)
        p.z()
    }
    static let backLegB2 = Path { p in
        p.m(374.837, 310.695)
        p.c(384.195, 316.097, 397.814, 328.057, 407.664, 341.081)
        p.c(412.58, 347.582, 416.414, 354.162, 418.357, 360.15)
        p.c(420.307, 366.159, 420.214, 371.098, 418.052, 374.842)
        p.c(415.933, 378.513, 412.028, 380.674, 406.312, 381.425)
        p.c(400.56, 382.18, 393.433, 381.422, 385.779, 379.648)
        p.c(370.499, 376.104, 354.102, 368.747, 344.516, 363.213)
        p.c(340.069, 360.645, 337.447, 357.781, 335.996, 354.81)
        p.c(334.541, 351.833, 334.119, 348.45, 334.579, 344.604)
        p.c(335.523, 336.721, 340.067, 327.582, 345.755, 317.731)
        p.c(348.59, 312.82, 350.758, 309.377, 352.707, 307.047)
        p.c(354.634, 304.743, 356.06, 303.881, 357.315, 303.597)
        p.c(358.61, 303.304, 360.378, 303.475, 363.313, 304.658)
        p.c(366.253, 305.843, 369.906, 307.847, 374.837, 310.695)
        p.z()
    }
    static let backTail1 = Path { p in
        p.m(240.855, 295.826)
        p.c(244.396, 291.207, 251.301, 285.217, 258.407, 281.177)
        p.c(261.973, 279.149, 265.8, 277.49, 269.451, 276.814)
        p.c(273.079, 276.141, 277.042, 276.359, 280.236, 278.808)
        p.c(283.5, 281.31, 284.555, 285.053, 284.555, 288.662)
        p.c(284.555, 292.234, 283.547, 296.132, 282.165, 299.823)
        p.c(279.389, 307.233, 274.718, 314.799, 271.343, 319.202)
        p.c(268.117, 323.409, 264.431, 327.553, 260.115, 329.623)
        p.c(257.865, 330.702, 255.382, 331.251, 252.716, 330.921)
        p.c(250.069, 330.592, 247.513, 329.432, 245.042, 327.537)
        p.c(235.129, 319.936, 233.255, 305.739, 240.855, 295.826)
        p.z()
    }
    static let frontLeftTail1 = Path { p in
        p.m(392.855, 228.826)
        p.c(396.396, 224.207, 403.301, 218.217, 410.407, 214.177)
        p.c(413.973, 212.149, 417.8, 210.49, 421.451, 209.814)
        p.c(425.079, 209.141, 429.042, 209.359, 432.236, 211.808)
        p.c(435.5, 214.31, 436.555, 218.053, 436.555, 221.662)
        p.c(436.555, 225.234, 435.547, 229.132, 434.165, 232.823)
        p.c(431.389, 240.233, 426.718, 247.799, 423.343, 252.202)
        p.c(420.117, 256.409, 416.431, 260.553, 412.115, 262.623)
        p.c(409.865, 263.702, 407.382, 264.251, 404.716, 263.921)
        p.c(402.069, 263.592, 399.513, 262.432, 397.042, 260.537)
        p.c(387.129, 252.936, 385.255, 238.739, 392.855, 228.826)
        p.z()
    }
    static let frontLeftLegA1 = Path { p in
        p.m(136.193, 313.893)
        p.c(127.658, 318.835, 115.828, 329.281, 107.272, 340.532)
        p.c(102.985, 346.169, 99.3701, 352.2, 97.4496, 358.022)
        p.c(95.5378, 363.817, 95.1535, 369.915, 98.1556, 375.13)
        p.c(101.202, 380.421, 106.578, 382.81, 112.388, 383.542)
        p.c(118.166, 384.271, 124.849, 383.448, 131.471, 381.886)
        p.c(144.745, 378.754, 158.805, 372.399, 167.107, 367.591)
        p.c(175.198, 362.906, 182.787, 357.668, 187.04, 351.192)
        p.c(189.222, 347.869, 190.572, 344.155, 190.622, 340.02)
        p.c(190.673, 335.903, 189.431, 331.648, 186.888, 327.231)
        p.c(176.692, 309.519, 153.983, 303.593, 136.193, 313.893)
        p.z()
    }
    static let frontLeftBody1 = Path { p in
        p.m(274, 108.5)
        p.c(358.776, 108.5, 427.5, 177.224, 427.5, 262)
        p.c(427.5, 283.185, 423.204, 300.216, 415.23, 313.799)
        p.c(407.247, 327.398, 395.718, 337.301, 381.649, 344.438)
        p.c(353.696, 358.617, 315.444, 362, 274, 362)
        p.c(232.556, 362, 194.304, 358.617, 166.351, 344.438)
        p.c(152.282, 337.301, 140.753, 327.398, 132.77, 313.799)
        p.c(124.796, 300.216, 120.5, 283.185, 120.5, 262)
        p.c(120.5, 177.224, 189.224, 108.5, 274, 108.5)
        p.z()
    }
    static let frontLeftBody2 = Path { p in
        p.m(424, 262)
        p.c(424, 344.843, 356.843, 301.5, 274, 301.5)
        p.c(191.157, 301.5, 124, 344.843, 124, 262)
        p.c(124, 179.157, 191.157, 112, 274, 112)
        p.c(356.843, 112, 424, 179.157, 424, 262)
        p.z()
    }
    static let frontLeftLegA2 = Path { p in
        p.m(359.153, 310.533)
        p.c(367.545, 318.925, 378.075, 334.819, 384.506, 350.659)
        p.c(387.728, 358.592, 390.014, 366.735, 390.397, 374.077)
        p.c(390.778, 381.396, 389.278, 388.432, 384.293, 393.417)
        p.c(379.247, 398.464, 372.434, 399.613, 365.478, 398.695)
        p.c(358.56, 397.782, 351.036, 394.787, 343.767, 390.913)
        p.c(329.203, 383.152, 314.733, 371.352, 306.533, 363.152)
        p.c(298.507, 355.126, 291.361, 346.704, 288.492, 337.93)
        p.c(287.027, 333.445, 286.651, 328.8, 287.879, 324.081)
        p.c(289.102, 319.38, 291.847, 314.873, 296.187, 310.533)
        p.c(313.575, 293.146, 341.765, 293.146, 359.153, 310.533)
        p.z()
    }
    static let frontLeftLegB1 = Path { p in
        p.m(437.337, 281.264)
        p.c(445.781, 283.514, 458.241, 289.726, 468.077, 297.398)
        p.c(473.007, 301.243, 477.471, 305.601, 480.439, 310.199)
        p.c(483.395, 314.778, 485.128, 320.026, 483.698, 325.334)
        p.c(482.246, 330.725, 478.094, 334.113, 473.23, 336.142)
        p.c(468.403, 338.155, 462.466, 339.027, 456.449, 339.246)
        p.c(444.387, 339.686, 430.946, 337.533, 422.767, 335.353)
        p.c(414.825, 333.237, 407.094, 330.506, 401.94, 325.871)
        p.c(399.287, 323.485, 397.263, 320.55, 396.278, 316.935)
        p.c(395.297, 313.338, 395.415, 309.332, 396.609, 304.9)
        p.c(401.392, 287.143, 419.615, 276.54, 437.337, 281.264)
        p.z()
    }
    static let frontLeftHead1 = Path { p in
        p.m(226, 77.5)
        p.c(310.776, 77.5, 379.5, 146.224, 379.5, 231)
        p.c(379.5, 252.185, 375.204, 269.216, 367.23, 282.799)
        p.c(359.247, 296.398, 347.718, 306.301, 333.649, 313.438)
        p.c(305.696, 327.617, 267.444, 331, 226, 331)
        p.c(184.556, 331, 146.304, 327.617, 118.351, 313.438)
        p.c(104.282, 306.301, 92.7527, 296.398, 84.7695, 282.799)
        p.c(76.7962, 269.216, 72.5, 252.185, 72.5, 231)
        p.c(72.5, 146.224, 141.224, 77.5, 226, 77.5)
        p.z()
    }
    static let backLeftHead1 = Path { p in
        p.m(186, 93.3867)
        p.c(263.106, 93.3867, 325.613, 155.895, 325.613, 233.002)
        p.c(325.613, 252.287, 321.707, 267.285, 314.842, 278.98)
        p.c(307.986, 290.66, 298.043, 299.277, 285.584, 305.598)
        p.c(260.489, 318.328, 225.466, 321.613, 186, 321.613)
        p.c(146.534, 321.613, 111.511, 318.328, 86.416, 305.598)
        p.c(73.957, 299.277, 64.0144, 290.66, 57.1582, 278.98)
        p.c(50.2928, 267.285, 46.3867, 252.287, 46.3867, 233.002)
        p.c(46.3868, 155.895, 108.894, 93.3867, 186, 93.3867)
        p.z()
    }
    static let backLeftLegB1 = Path { p in
        p.m(95.7227, 304.267)
        p.c(88.051, 304.267, 75.3181, 306.801, 64.5332, 311.356)
        p.c(59.1539, 313.629, 54.4762, 316.315, 51.2002, 319.267)
        p.c(47.9073, 322.234, 46.3869, 325.127, 46.3867, 327.884)
        p.c(46.3867, 330.556, 47.82, 333.077, 50.9941, 335.511)
        p.c(54.1973, 337.967, 58.8147, 340.029, 64.2021, 341.671)
        p.c(74.9496, 344.946, 87.7876, 346.259, 95.7227, 346.259)
        p.c(103.895, 346.259, 110.586, 345.553, 115.174, 343.226)
        p.c(117.379, 342.107, 119.023, 340.648, 120.145, 338.737)
        p.c(121.275, 336.811, 122.011, 334.193, 122.011, 330.555)
        p.c(122.011, 316.036, 110.241, 304.267, 95.7227, 304.267)
        p.z()
    }
    static let backLeftLegA1 = Path { p in
        p.m(359.675, 304.267)
        p.c(367.346, 304.267, 380.079, 306.801, 390.864, 311.356)
        p.c(396.244, 313.629, 400.921, 316.315, 404.197, 319.267)
        p.c(407.49, 322.234, 409.011, 325.127, 409.011, 327.884)
        p.c(409.011, 330.556, 407.577, 333.077, 404.403, 335.511)
        p.c(401.2, 337.967, 396.583, 340.029, 391.195, 341.671)
        p.c(380.448, 344.946, 367.61, 346.259, 359.675, 346.259)
        p.c(351.503, 346.259, 344.811, 345.553, 340.224, 343.226)
        p.c(338.019, 342.107, 336.374, 340.648, 335.253, 338.737)
        p.c(334.122, 336.811, 333.387, 334.193, 333.387, 330.555)
        p.c(333.387, 316.036, 345.156, 304.267, 359.675, 304.267)
        p.z()
    }
    static let backLeftBody1 = Path { p in
        p.m(249.435, 134.925)
        p.c(327.068, 134.925, 389.989, 197.699, 389.989, 275.117)
        p.c(389.989, 294.481, 386.057, 309.541, 379.145, 321.285)
        p.c(372.242, 333.014, 362.232, 341.669, 349.687, 348.017)
        p.c(324.42, 360.801, 289.161, 364.1, 249.435, 364.1)
        p.c(209.71, 364.1, 174.451, 360.801, 149.184, 348.017)
        p.c(136.639, 341.669, 126.629, 333.014, 119.726, 321.285)
        p.c(112.814, 309.541, 108.882, 294.481, 108.882, 275.117)
        p.c(108.882, 197.699, 171.802, 134.925, 249.435, 134.925)
        p.z()
    }
    static let backLeftBody2 = Path { p in
        p.m(249.853, 134.925)
        p.c(330.826, 134.925, 396.469, 200.567, 396.469, 281.54)
        p.c(396.469, 301.928, 392.313, 313.631, 385.673, 320.267)
        p.c(379.068, 326.869, 369.252, 329.206, 355.981, 328.971)
        p.c(342.704, 328.736, 326.855, 325.964, 308.757, 323.172)
        p.c(290.788, 320.399, 270.84, 317.654, 249.853, 317.654)
        p.c(228.866, 317.654, 208.919, 320.399, 190.95, 323.172)
        p.c(172.852, 325.964, 157.003, 328.736, 143.726, 328.971)
        p.c(130.455, 329.206, 120.638, 326.869, 114.033, 320.267)
        p.c(107.394, 313.631, 103.238, 301.928, 103.238, 281.54)
        p.c(103.238, 200.567, 168.88, 134.925, 249.853, 134.925)
        p.z()
    }
    static let backLeftLegA2 = Path { p in
        p.m(148.815, 310.695)
        p.c(139.457, 316.097, 125.838, 328.057, 115.988, 341.081)
        p.c(111.072, 347.582, 107.238, 354.162, 105.295, 360.15)
        p.c(103.344, 366.159, 103.438, 371.098, 105.599, 374.842)
        p.c(107.719, 378.513, 111.624, 380.674, 117.34, 381.425)
        p.c(123.092, 382.18, 130.219, 381.422, 137.873, 379.648)
        p.c(153.153, 376.104, 169.55, 368.747, 179.136, 363.213)
        p.c(183.583, 360.645, 186.205, 357.781, 187.656, 354.81)
        p.c(189.11, 351.833, 189.533, 348.45, 189.073, 344.604)
        p.c(188.129, 336.721, 183.584, 327.582, 177.897, 317.731)
        p.c(175.062, 312.82, 172.894, 309.377, 170.945, 307.047)
        p.c(169.018, 304.743, 167.592, 303.881, 166.337, 303.597)
        p.c(165.042, 303.304, 163.274, 303.475, 160.339, 304.658)
        p.c(157.399, 305.843, 153.746, 307.847, 148.815, 310.695)
        p.z()
    }
    static let backLeftLegB2 = Path { p in
        p.m(397.37, 310.695)
        p.c(406.728, 316.097, 420.347, 328.057, 430.197, 341.081)
        p.c(435.113, 347.582, 438.947, 354.162, 440.89, 360.15)
        p.c(442.841, 366.159, 442.747, 371.098, 440.586, 374.842)
        p.c(438.466, 378.513, 434.561, 380.674, 428.845, 381.425)
        p.c(423.093, 382.18, 415.966, 381.422, 408.312, 379.648)
        p.c(393.032, 376.104, 376.635, 368.747, 367.049, 363.213)
        p.c(362.602, 360.645, 359.98, 357.781, 358.529, 354.81)
        p.c(357.075, 351.833, 356.652, 348.45, 357.112, 344.604)
        p.c(358.056, 336.721, 362.601, 327.582, 368.288, 317.731)
        p.c(371.123, 312.82, 373.291, 309.377, 375.24, 307.047)
        p.c(377.167, 304.743, 378.593, 303.881, 379.848, 303.597)
        p.c(381.144, 303.304, 382.911, 303.475, 385.846, 304.658)
        p.c(388.786, 305.843, 392.439, 307.847, 397.37, 310.695)
        p.z()
    }
    static let backLeftTail1 = Path { p in
        p.m(281.855, 294.826)
        p.c(285.396, 290.207, 292.301, 284.217, 299.407, 280.177)
        p.c(302.973, 278.149, 306.8, 276.49, 310.451, 275.814)
        p.c(314.079, 275.141, 318.042, 275.359, 321.236, 277.808)
        p.c(324.5, 280.31, 325.555, 284.053, 325.555, 287.662)
        p.c(325.555, 291.234, 324.547, 295.132, 323.165, 298.823)
        p.c(320.389, 306.233, 315.718, 313.799, 312.343, 318.202)
        p.c(309.117, 322.409, 305.431, 326.553, 301.115, 328.623)
        p.c(298.865, 329.702, 296.382, 330.251, 293.716, 329.921)
        p.c(291.069, 329.592, 288.513, 328.432, 286.042, 326.537)
        p.c(276.129, 318.936, 274.255, 304.739, 281.855, 294.826)
        p.z()
    }
    static let longTail1 = Path { p in
        p.m(406.855, 1229.83)
        p.c(410.396, 1225.21, 417.301, 1219.22, 424.407, 1215.18)
        p.c(427.973, 1213.15, 431.8, 1211.49, 435.451, 1210.81)
        p.c(439.079, 1210.14, 443.042, 1210.36, 446.236, 1212.81)
        p.c(449.5, 1215.31, 450.555, 1219.05, 450.555, 1222.66)
        p.c(450.555, 1226.23, 449.547, 1230.13, 448.165, 1233.82)
        p.c(445.389, 1241.23, 440.718, 1248.8, 437.343, 1253.2)
        p.c(434.117, 1257.41, 430.431, 1261.55, 426.115, 1263.62)
        p.c(423.865, 1264.7, 421.382, 1265.25, 418.716, 1264.92)
        p.c(416.069, 1264.59, 413.513, 1263.43, 411.042, 1261.54)
        p.c(401.129, 1253.94, 399.255, 1239.74, 406.855, 1229.83)
        p.z()
    }
    static let longBody1 = Path { p in
        p.m(151.193, 1305.89)
        p.c(142.658, 1310.84, 130.828, 1321.28, 122.272, 1332.53)
        p.c(117.985, 1338.17, 114.37, 1344.2, 112.45, 1350.02)
        p.c(110.538, 1355.82, 110.153, 1361.92, 113.156, 1367.13)
        p.c(116.202, 1372.42, 121.578, 1374.81, 127.388, 1375.54)
        p.c(133.166, 1376.27, 139.849, 1375.45, 146.471, 1373.89)
        p.c(159.745, 1370.75, 173.805, 1364.4, 182.107, 1359.59)
        p.c(190.198, 1354.91, 197.787, 1349.67, 202.04, 1343.19)
        p.c(204.222, 1339.87, 205.572, 1336.15, 205.622, 1332.02)
        p.c(205.673, 1327.9, 204.431, 1323.65, 201.888, 1319.23)
        p.c(191.692, 1301.52, 168.983, 1295.59, 151.193, 1305.89)
        p.z()
    }
    static let longBody2 = Path { p in
        p.m(272, 1109.5)
        p.c(356.776, 1109.5, 425.5, 1178.22, 425.5, 1263)
        p.c(425.5, 1284.18, 421.204, 1301.22, 413.23, 1314.8)
        p.c(405.247, 1328.4, 393.718, 1338.3, 379.649, 1345.44)
        p.c(351.696, 1359.62, 313.444, 1363, 272, 1363)
        p.c(230.556, 1363, 192.304, 1359.62, 164.351, 1345.44)
        p.c(150.282, 1338.3, 138.753, 1328.4, 130.77, 1314.8)
        p.c(122.796, 1301.22, 118.5, 1284.18, 118.5, 1263)
        p.c(118.5, 1178.22, 187.224, 1109.5, 272, 1109.5)
        p.z()
    }
    static let longBody3 = Path { p in
        p.m(422, 1263)
        p.c(422, 1345.84, 354.843, 1302.5, 272, 1302.5)
        p.c(189.157, 1302.5, 122, 1345.84, 122, 1263)
        p.c(122, 1180.16, 189.157, 1113, 272, 1113)
        p.c(354.843, 1113, 422, 1180.16, 422, 1263)
        p.z()
    }
    static let longBody4 = Path { p in
        p.m(357.153, 1318.53)
        p.c(365.545, 1326.93, 376.075, 1342.82, 382.506, 1358.66)
        p.c(385.728, 1366.59, 388.014, 1374.74, 388.397, 1382.08)
        p.c(388.778, 1389.4, 387.278, 1396.43, 382.293, 1401.42)
        p.c(377.247, 1406.46, 370.434, 1407.61, 363.478, 1406.69)
        p.c(356.56, 1405.78, 349.036, 1402.79, 341.767, 1398.91)
        p.c(327.203, 1391.15, 312.733, 1379.35, 304.533, 1371.15)
        p.c(296.507, 1363.13, 289.361, 1354.7, 286.492, 1345.93)
        p.c(285.027, 1341.45, 284.651, 1336.8, 285.879, 1332.08)
        p.c(287.102, 1327.38, 289.847, 1322.87, 294.187, 1318.53)
        p.c(311.575, 1301.15, 339.765, 1301.15, 357.153, 1318.53)
        p.z()
    }
    static let longBody5 = Path { p in
        p.m(435.337, 1282.26)
        p.c(443.781, 1284.51, 456.241, 1290.73, 466.077, 1298.4)
        p.c(471.007, 1302.24, 475.471, 1306.6, 478.439, 1311.2)
        p.c(481.395, 1315.78, 483.128, 1321.03, 481.698, 1326.33)
        p.c(480.246, 1331.73, 476.094, 1335.11, 471.23, 1337.14)
        p.c(466.403, 1339.16, 460.466, 1340.03, 454.449, 1340.25)
        p.c(442.387, 1340.69, 428.946, 1338.53, 420.767, 1336.35)
        p.c(412.825, 1334.24, 405.094, 1331.51, 399.94, 1326.87)
        p.c(397.287, 1324.48, 395.263, 1321.55, 394.278, 1317.93)
        p.c(393.297, 1314.34, 393.415, 1310.33, 394.609, 1305.9)
        p.c(399.392, 1288.14, 417.615, 1277.54, 435.337, 1282.26)
        p.z()
    }
    static let longCollar1 = Path { p in
        p.m(328.42, 433)
        p.c(328.47, 426.87, 328.5, 420.79, 328.5, 414.75)
        p.c(328.5, 347.89, 323.24, 281.44, 317.98, 231.73)
        p.c(315.35, 206.88, 312.72, 186.19, 310.75, 171.72)
        p.c(309.76, 164.48, 308.94, 158.79, 308.36, 154.91)
        p.c(308.08, 152.97, 307.85, 151.49, 307.69, 150.48)
        p.c(307.62, 149.98, 307.56, 149.6, 307.52, 149.34)
        p.c(307.5, 149.21, 307.48, 149.12, 307.47, 149.05)
        p.c(307.47, 149.05, 307.46, 148.96, 307.46, 148.96)
        p.c(307.46, 148.96, 307.46, 148.95, 307.46, 148.95)
        p.c(307.46, 148.95, 307.4, 148.96, 304, 149.5)
        p.c(307.42, 148.75, 307.42, 148.75, 307.42, 148.75)
        p.c(307.42, 148.75, 307.42, 148.75, 307.42, 148.74)
        p.c(307.42, 148.74, 307.42, 148.74, 307.41, 148.73)
        p.c(307.41, 148.72, 307.41, 148.71, 307.4, 148.69)
        p.c(307.4, 148.65, 307.38, 148.59, 307.37, 148.52)
        p.c(307.33, 148.38, 307.29, 148.18, 307.22, 147.91)
        p.c(307.1, 147.38, 306.91, 146.61, 306.65, 145.64)
        p.c(306.15, 143.7, 305.38, 140.94, 304.32, 137.64)
        p.c(302.22, 131.04, 298.97, 122.2, 294.37, 113.33)
        p.c(285.35, 95.92, 270.35, 76.89, 247.52, 76.89)
        p.c(231.09, 76.89, 214.78, 77.6, 199.86, 84.71)
        p.c(184.78, 91.89, 171.57, 105.35, 160.67, 129.88)
        p.c(139.82, 176.84, 126.95, 265.55, 126.05, 433)
        p.z()
    }
    static let longCollar2 = Path { p in
        p.m(328.42, 433)
        p.c(328.47, 426.87, 328.5, 420.79, 328.5, 414.75)
        p.c(328.5, 347.89, 323.24, 281.44, 317.98, 231.73)
        p.c(315.35, 206.88, 312.72, 186.19, 310.75, 171.72)
        p.c(309.76, 164.48, 308.94, 158.79, 308.36, 154.91)
        p.c(308.08, 152.97, 307.85, 151.49, 307.69, 150.48)
        p.c(307.62, 149.98, 307.56, 149.6, 307.52, 149.34)
        p.c(307.5, 149.21, 307.48, 149.12, 307.47, 149.05)
        p.c(307.47, 149.05, 307.46, 148.96, 307.46, 148.96)
        p.c(307.46, 148.96, 307.46, 148.95, 307.46, 148.95)
        p.c(307.46, 148.95, 307.4, 148.96, 304, 149.5)
        p.c(307.42, 148.75, 307.42, 148.75, 307.42, 148.75)
        p.c(307.42, 148.75, 307.42, 148.75, 307.42, 148.74)
        p.c(307.42, 148.74, 307.42, 148.74, 307.41, 148.73)
        p.c(307.41, 148.72, 307.41, 148.71, 307.4, 148.69)
        p.c(307.4, 148.65, 307.38, 148.59, 307.37, 148.52)
        p.c(307.33, 148.38, 307.29, 148.18, 307.22, 147.91)
        p.c(307.1, 147.38, 306.91, 146.61, 306.65, 145.64)
        p.c(306.15, 143.7, 305.38, 140.94, 304.32, 137.64)
        p.c(302.22, 131.04, 298.97, 122.2, 294.37, 113.33)
        p.c(285.35, 95.92, 270.35, 76.89, 247.52, 76.89)
        p.c(231.09, 76.89, 214.78, 77.6, 199.86, 84.71)
        p.c(184.78, 91.89, 171.57, 105.35, 160.67, 129.88)
        p.c(139.82, 176.84, 126.95, 265.55, 126.05, 433)
    }
    static let neck = Path { p in
        p.m(304, 149.5)
        p.c(307.419, 148.751, 307.418, 148.75, 307.418, 148.748)
        p.c(307.418, 148.747, 307.417, 148.746, 307.417, 148.744)
        p.c(307.416, 148.741, 307.415, 148.736, 307.414, 148.73)
        p.c(307.412, 148.72, 307.409, 148.705, 307.404, 148.686)
        p.c(307.396, 148.647, 307.383, 148.592, 307.367, 148.521)
        p.c(307.335, 148.38, 307.287, 148.175, 307.224, 147.91)
        p.c(307.097, 147.381, 306.908, 146.614, 306.654, 145.644)
        p.c(306.146, 143.703, 305.377, 140.944, 304.323, 137.639)
        p.c(302.22, 131.039, 298.966, 122.202, 294.371, 113.334)
        p.c(285.347, 95.9178, 270.348, 76.8879, 247.522, 76.8877)
        p.c(231.091, 76.8877, 214.783, 77.5991, 199.858, 84.7061)
        p.c(184.779, 91.8868, 171.568, 105.351, 160.674, 129.877)
        p.c(139.04, 178.582, 126, 272.202, 126, 452)
        p.c(126, 541.889, 124.051, 639.443, 122.152, 735.251)
        p.c(120.254, 831.041, 118.405, 925.091, 118.611, 1007.91)
        p.c(118.817, 1090.68, 121.076, 1162.39, 127.418, 1213.46)
        p.c(130.585, 1238.95, 134.797, 1259.54, 140.395, 1273.85)
        p.c(143.191, 1281, 146.421, 1286.81, 150.227, 1290.89)
        p.c(154.088, 1295.02, 158.687, 1297.5, 164, 1297.5)
        p.c(169.305, 1297.5, 174.33, 1294.88, 178.982, 1290.67)
        p.c(183.649, 1286.46, 188.249, 1280.38, 192.787, 1272.77)
        p.c(201.871, 1257.54, 211.077, 1235.56, 220.193, 1208.31)
        p.c(238.442, 1153.76, 256.549, 1077.4, 272.581, 989.901)
        p.c(304.648, 814.891, 328.501, 594.863, 328.501, 414.749)
        p.c(328.501, 347.887, 323.238, 281.441, 317.98, 231.734)
        p.c(315.351, 206.875, 312.722, 186.19, 310.749, 171.715)
        p.c(309.763, 164.477, 308.94, 158.791, 308.364, 154.912)
        p.c(308.076, 152.973, 307.85, 151.485, 307.695, 150.48)
        p.c(307.618, 149.978, 307.558, 149.597, 307.518, 149.341)
        p.c(307.497, 149.213, 307.483, 149.115, 307.473, 149.05)
        p.l(307.458, 148.957)
        p.c(307.458, 148.955, 307.457, 148.952, 307.457, 148.951)
        p.c(307.456, 148.95, 307.399, 148.959, 304, 149.5)
        p.z()
        p.m(304, 149.5)
        p.l(307.419, 148.751)
        p.l(307.44, 148.85)
        p.l(307.456, 148.949)
        p.l(304, 149.5)
        p.z()
    }
    static let rootFill = Path { p in
        p.m(126.05, 433)
        p.c(126.02, 439.22, 126, 445.56, 126, 452)
        p.c(126, 541.89, 124.05, 639.44, 122.15, 735.25)
        p.c(120.25, 831.04, 118.41, 925.09, 118.61, 1007.91)
        p.c(118.82, 1090.68, 121.08, 1162.39, 127.42, 1213.46)
        p.c(130.59, 1238.95, 134.8, 1259.54, 140.4, 1273.85)
        p.c(143.19, 1281, 146.42, 1286.81, 150.23, 1290.89)
        p.c(154.09, 1295.02, 158.69, 1297.5, 164, 1297.5)
        p.c(169.31, 1297.5, 174.33, 1294.88, 178.98, 1290.67)
        p.c(183.65, 1286.46, 188.25, 1280.38, 192.79, 1272.77)
        p.c(201.87, 1257.54, 211.08, 1235.56, 220.19, 1208.31)
        p.c(238.44, 1153.76, 256.55, 1077.4, 272.58, 989.9)
        p.c(303.57, 820.76, 326.89, 609.57, 328.42, 433)
        p.z()
    }
    static let rootLine = Path { p in
        p.m(126.05, 433)
        p.c(126.02, 439.22, 126, 445.56, 126, 452)
        p.c(126, 541.89, 124.05, 639.44, 122.15, 735.25)
        p.c(120.25, 831.04, 118.41, 925.09, 118.61, 1007.91)
        p.c(118.82, 1090.68, 121.08, 1162.39, 127.42, 1213.46)
        p.c(130.59, 1238.95, 134.8, 1259.54, 140.4, 1273.85)
        p.c(143.19, 1281, 146.42, 1286.81, 150.23, 1290.89)
        p.c(154.09, 1295.02, 158.69, 1297.5, 164, 1297.5)
        p.c(169.31, 1297.5, 174.33, 1294.88, 178.98, 1290.67)
        p.c(183.65, 1286.46, 188.25, 1280.38, 192.79, 1272.77)
        p.c(201.87, 1257.54, 211.08, 1235.56, 220.19, 1208.31)
        p.c(238.44, 1153.76, 256.55, 1077.4, 272.58, 989.9)
        p.c(303.57, 820.76, 326.89, 609.57, 328.42, 433)
    }
}

// Turtle artwork parts in drawing order
enum TurtleParts {
    static let side: [ArtPart] = [
        ArtPart(.tail, origin: UnitPoint(x: 0.1, y: 0.9), shapes: [
            ArtShape(TurtlePaths.sideTail1, fill: .skin, stroke: .ink, width: 7),
        ]),
        ArtPart(.legA, origin: UnitPoint(x: 0.75, y: 0.12), shapes: [
            ArtShape(TurtlePaths.sideLegA1, fill: .skin, stroke: .ink, width: 7),
        ]),
        ArtPart(.still, shapes: [ArtShape(TurtlePaths.sideBody1, fill: .shell, stroke: .ink, width: 7)]),
        ArtPart(.still, shapes: [ArtShape(TurtlePaths.sideBody2, fill: .plates)]),
        ArtPart(.legA, origin: UnitPoint(x: 0.25, y: 0.12), shapes: [
            ArtShape(TurtlePaths.sideLegA2, fill: .skin, stroke: .ink, width: 7),
        ]),
        ArtPart(.legB, origin: UnitPoint(x: 0.08, y: 0.45), shapes: [
            ArtShape(TurtlePaths.sideLegB1, fill: .skin, stroke: .ink, width: 7),
        ]),
        ArtPart(.head, origin: UnitPoint(x: 0.85, y: 0.85), shapes: [
            ArtShape(TurtlePaths.sideHead1, fill: .skin, stroke: .ink, width: 7),
        ], children: [
            ArtPart(.eyes, origin: UnitPoint(x: 0.5, y: 0.5), shapes: [
                ArtShape(ellipse(62, 253.999, 17, 23, rotated: -9.64244), fill: .light),
                ArtShape(ellipse(131, 254, 17, 23, rotated: -7.9156), fill: .light),
            ]),
        ]),
    ]
    static let front: [ArtPart] = [
        ArtPart(.legB, origin: UnitPoint(x: 0.75, y: 0.12), shapes: [
            ArtShape(TurtlePaths.frontLegB1, fill: .skin, stroke: .ink, width: 6.77364),
        ]),
        ArtPart(.legA, origin: UnitPoint(x: 0.25, y: 0.12), shapes: [
            ArtShape(TurtlePaths.frontLegA1, fill: .skin, stroke: .ink, width: 6.77364),
        ]),
        ArtPart(.still, shapes: [ArtShape(TurtlePaths.frontBody1, fill: .shell, stroke: .ink, width: 6.77364)]),
        ArtPart(.still, shapes: [ArtShape(TurtlePaths.frontBody2, fill: .plates, stroke: .ink, width: 6.77364)]),
        ArtPart(.legA, origin: UnitPoint(x: 0.75, y: 0.12), shapes: [
            ArtShape(TurtlePaths.frontLegA2, fill: .skin, stroke: .ink, width: 6.77364),
        ]),
        ArtPart(.legB, origin: UnitPoint(x: 0.25, y: 0.12), shapes: [
            ArtShape(TurtlePaths.frontLegB2, fill: .skin, stroke: .ink, width: 6.77364),
        ]),
        ArtPart(.head, origin: UnitPoint(x: 0.5, y: 0.9), shapes: [
            ArtShape(TurtlePaths.frontHead1, fill: .skin, stroke: .ink, width: 6.77364),
        ], children: [
            ArtPart(.eyes, origin: UnitPoint(x: 0.5, y: 0.5), shapes: [
                ArtShape(ellipse(215.069, 269.467, 17.0003, 23.0003, rotated: 0), fill: .light),
                ArtShape(ellipse(284.069, 269.467, 17.0003, 23.0003, rotated: 0), fill: .light),
            ]),
            ArtPart(.closedEyes, shapes: [
                ArtShape(TurtlePaths.frontClosedEyes1, fill: .light),
                ArtShape(TurtlePaths.frontClosedEyes2, fill: .light),
            ]),
        ]),
    ]
    static let back: [ArtPart] = [
        ArtPart(.head, origin: UnitPoint(x: 0.5, y: 0.9), shapes: [
            ArtShape(TurtlePaths.backHead1, fill: .skin, stroke: .ink, width: 6.77364),
        ]),
        ArtPart(.legB, origin: UnitPoint(x: 0.75, y: 0.12), shapes: [
            ArtShape(TurtlePaths.backLegB1, fill: .skin, stroke: .ink, width: 6.77364),
        ]),
        ArtPart(.legA, origin: UnitPoint(x: 0.25, y: 0.12), shapes: [
            ArtShape(TurtlePaths.backLegA1, fill: .skin, stroke: .ink, width: 6.77364),
        ]),
        ArtPart(.still, shapes: [ArtShape(TurtlePaths.backBody1, fill: .shell, stroke: .ink, width: 6.77364)]),
        ArtPart(.still, shapes: [ArtShape(TurtlePaths.backBody2, fill: .plates, stroke: .ink, width: 6.77364)]),
        ArtPart(.legA, origin: UnitPoint(x: 0.75, y: 0.12), shapes: [
            ArtShape(TurtlePaths.backLegA2, fill: .skin, stroke: .ink, width: 6.77364),
        ]),
        ArtPart(.legB, origin: UnitPoint(x: 0.25, y: 0.12), shapes: [
            ArtShape(TurtlePaths.backLegB2, fill: .skin, stroke: .ink, width: 6.77364),
        ]),
        ArtPart(.tail, origin: UnitPoint(x: 0.45, y: 0.95), shapes: [
            ArtShape(TurtlePaths.backTail1, fill: .skin, stroke: .ink, width: 7),
        ]),
    ]
    static let frontLeft: [ArtPart] = [
        ArtPart(.tail, origin: UnitPoint(x: 0.1, y: 0.9), shapes: [
            ArtShape(TurtlePaths.frontLeftTail1, fill: .skin, stroke: .ink, width: 7),
        ]),
        ArtPart(.legA, origin: UnitPoint(x: 0.75, y: 0.12), shapes: [
            ArtShape(TurtlePaths.frontLeftLegA1, fill: .skin, stroke: .ink, width: 7),
        ]),
        ArtPart(.still, shapes: [ArtShape(TurtlePaths.frontLeftBody1, fill: .shell, stroke: .ink, width: 7)]),
        ArtPart(.still, shapes: [ArtShape(TurtlePaths.frontLeftBody2, fill: .plates)]),
        ArtPart(.legA, origin: UnitPoint(x: 0.25, y: 0.12), shapes: [
            ArtShape(TurtlePaths.frontLeftLegA2, fill: .skin, stroke: .ink, width: 7),
        ]),
        ArtPart(.legB, origin: UnitPoint(x: 0.08, y: 0.45), shapes: [
            ArtShape(TurtlePaths.frontLeftLegB1, fill: .skin, stroke: .ink, width: 7),
        ]),
        ArtPart(.head, origin: UnitPoint(x: 0.85, y: 0.85), shapes: [
            ArtShape(TurtlePaths.frontLeftHead1, fill: .skin, stroke: .ink, width: 7),
        ], children: [
            ArtPart(.eyes, origin: UnitPoint(x: 0.5, y: 0.5), shapes: [
                ArtShape(ellipse(159.311, 253.999, 17, 23, rotated: -6), fill: .light),
                ArtShape(ellipse(228.185, 254, 17, 23, rotated: -4), fill: .light),
            ]),
        ]),
    ]
    static let backLeft: [ArtPart] = [
        ArtPart(.head, origin: UnitPoint(x: 0.5, y: 0.9), shapes: [
            ArtShape(TurtlePaths.backLeftHead1, fill: .skin, stroke: .ink, width: 6.77364),
        ]),
        ArtPart(.legB, origin: UnitPoint(x: 0.75, y: 0.12), shapes: [
            ArtShape(TurtlePaths.backLeftLegB1, fill: .skin, stroke: .ink, width: 6.77364),
        ]),
        ArtPart(.legA, origin: UnitPoint(x: 0.25, y: 0.12), shapes: [
            ArtShape(TurtlePaths.backLeftLegA1, fill: .skin, stroke: .ink, width: 6.77364),
        ]),
        ArtPart(.still, shapes: [ArtShape(TurtlePaths.backLeftBody1, fill: .shell, stroke: .ink, width: 6.77364)]),
        ArtPart(.still, shapes: [ArtShape(TurtlePaths.backLeftBody2, fill: .plates, stroke: .ink, width: 6.77364)]),
        ArtPart(.legA, origin: UnitPoint(x: 0.75, y: 0.12), shapes: [
            ArtShape(TurtlePaths.backLeftLegA2, fill: .skin, stroke: .ink, width: 6.77364),
        ]),
        ArtPart(.legB, origin: UnitPoint(x: 0.25, y: 0.12), shapes: [
            ArtShape(TurtlePaths.backLeftLegB2, fill: .skin, stroke: .ink, width: 6.77364),
        ]),
        ArtPart(.tail, origin: UnitPoint(x: 0.45, y: 0.95), shapes: [
            ArtShape(TurtlePaths.backLeftTail1, fill: .skin, stroke: .ink, width: 7),
        ]),
    ]
    static let long: [ArtPart] = [
        ArtPart(.tail, origin: UnitPoint(x: 0.1, y: 0.9), shapes: [
            ArtShape(TurtlePaths.longTail1, fill: .skin, stroke: .ink, width: 7),
        ]),
        ArtPart(.still, shapes: [ArtShape(TurtlePaths.longBody1, fill: .skin, stroke: .ink, width: 7)]),
        ArtPart(.still, shapes: [ArtShape(TurtlePaths.longBody2, fill: .shell, stroke: .ink, width: 7)]),
        ArtPart(.still, shapes: [ArtShape(TurtlePaths.longBody3, fill: .plates)]),
        ArtPart(.still, shapes: [ArtShape(TurtlePaths.longBody4, fill: .skin, stroke: .ink, width: 7)]),
        ArtPart(.still, shapes: [ArtShape(TurtlePaths.longBody5, fill: .skin, stroke: .ink, width: 7)]),
    ]
    static let collar: [ArtShape] = [
        ArtShape(TurtlePaths.longCollar1, fill: .skin),
        ArtShape(TurtlePaths.longCollar2, stroke: .ink, width: 7),
    ]
    static let headEyes: [ArtShape] = [
        ArtShape(ellipse(60, 199.999, 17, 23, rotated: -9.64244), fill: .light),
        ArtShape(ellipse(129, 200, 17, 23, rotated: -7.9156), fill: .light),
    ]
}

// Long neck curve and head outlines in long view coordinates
enum NeckArt {
    // Share of the head outline still stroked once the head is fully stretched
    static let openOutline = 0.8393572266014637
    // Lowest point of the neck curve; the resting neck is squeezed toward it
    static let bottom = 1297.5
    // Highest point of the neck curve
    static let top = 76.8877
    // The resting neck narrows toward this x
    static let centreX = 164.0
    // Top of the neck tube when the neck is fully extended
    static let columnTop = 433.0
    // Left edge of the neck tube
    static let left = 126.0500361286803
    // Right edge of the neck tube
    static let right = 328.4211219822596
    static let restingHead: [Double] = [
        201.15, 275.82, 199.06, 275.97, 196.99, 276.1, 194.93, 276.22, 192.88, 276.33, 190.84, 276.43,
        188.81, 276.52, 186.8, 276.6, 184.8, 276.67, 182.8, 276.74, 180.81, 276.79, 178.83, 276.84,
        176.86, 276.88, 174.89, 276.92, 172.93, 276.94, 170.97, 276.97, 169.02, 276.98, 167.07, 276.99,
        165.12, 277.0, 163.17, 277.0, 161.21, 276.99, 159.26, 276.98, 157.31, 276.97, 155.35, 276.95,
        153.39, 276.92, 151.42, 276.89, 149.45, 276.85, 147.47, 276.8, 145.49, 276.74, 143.49, 276.68,
        141.49, 276.61, 139.48, 276.53, 137.45, 276.44, 135.42, 276.34, 133.37, 276.24, 131.31, 276.12,
        129.24, 275.99, 127.15, 275.84, 125.05, 275.69, 122.93, 275.52, 120.8, 275.34, 118.64, 275.14,
        116.48, 274.92, 114.29, 274.69, 112.09, 274.44, 109.86, 274.17, 107.62, 273.88, 105.36, 273.57,
        103.08, 273.24, 100.79, 272.88, 98.47, 272.49, 96.13, 272.07, 93.78, 271.63, 91.41, 271.15,
        89.02, 270.64, 86.62, 270.1, 84.21, 269.51, 81.78, 268.89, 79.34, 268.22, 76.89, 267.51,
        74.43, 266.75, 71.97, 265.94, 69.5, 265.08, 67.04, 264.16, 64.59, 263.19, 62.14, 262.16,
        59.7, 261.06, 57.28, 259.91, 54.89, 258.68, 52.52, 257.39, 50.18, 256.02, 47.87, 254.59,
        45.61, 253.09, 43.39, 251.51, 41.22, 249.86, 39.11, 248.14, 37.06, 246.34, 35.07, 244.48,
        33.15, 242.55, 31.31, 240.54, 29.54, 238.48, 27.84, 236.35, 26.23, 234.16, 24.7, 231.91,
        23.25, 229.61, 21.89, 227.26, 20.61, 224.86, 19.41, 222.41, 18.3, 219.93, 17.28, 217.42,
        16.33, 214.87, 15.47, 212.29, 14.68, 209.69, 13.97, 207.06, 13.33, 204.42, 12.77, 201.76,
        12.27, 199.09, 11.85, 196.41, 11.48, 193.72, 11.18, 191.02, 10.94, 188.32, 10.75, 185.62,
        10.62, 182.92, 10.53, 180.22, 10.5, 177.53, 10.52, 174.83, 10.58, 172.14, 10.68, 169.46,
        10.84, 166.78, 11.03, 164.11, 11.28, 161.44, 11.57, 158.79, 11.91, 156.14, 12.29, 153.5,
        12.71, 150.88, 13.19, 148.26, 13.7, 145.66, 14.26, 143.06, 14.87, 140.49, 15.52, 137.92,
        16.21, 135.38, 16.95, 132.84, 17.72, 130.33, 18.55, 127.83, 19.41, 125.35, 20.31, 122.88,
        21.26, 120.44, 22.24, 118.02, 23.27, 115.61, 24.33, 113.23, 25.44, 110.87, 26.58, 108.53,
        27.76, 106.21, 28.98, 103.92, 30.23, 101.65, 31.53, 99.41, 32.85, 97.19, 34.22, 95.0,
        35.62, 92.83, 37.05, 90.69, 38.52, 88.57, 40.02, 86.48, 41.55, 84.42, 43.11, 82.39,
        44.71, 80.39, 46.34, 78.41, 48.0, 76.47, 49.69, 74.56, 51.4, 72.67, 53.15, 70.82,
        54.93, 68.99, 56.73, 67.2, 58.56, 65.44, 60.42, 63.72, 62.3, 62.02, 64.21, 60.36,
        66.14, 58.73, 68.1, 57.13, 70.09, 55.57, 72.09, 54.04, 74.12, 52.55, 76.17, 51.09,
        78.25, 49.67, 80.34, 48.28, 82.46, 46.93, 84.59, 45.61, 86.75, 44.33, 88.92, 43.08,
        91.12, 41.87, 93.33, 40.7, 95.55, 39.57, 97.8, 38.47, 100.06, 37.41, 102.34, 36.39,
        104.63, 35.4, 106.93, 34.46, 109.25, 33.55, 111.59, 32.68, 113.93, 31.85, 116.29, 31.06,
        118.66, 30.31, 121.04, 29.59, 123.43, 28.92, 125.83, 28.28, 128.24, 27.69, 130.66, 27.13,
        133.08, 26.62, 135.51, 26.14, 137.95, 25.7, 140.4, 25.3, 142.85, 24.95, 145.31, 24.63,
        147.77, 24.35, 150.23, 24.11, 152.7, 23.91, 155.17, 23.75, 157.64, 23.63, 160.11, 23.55,
        162.58, 23.51, 165.06, 23.5, 167.53, 23.54, 170.01, 23.62, 172.48, 23.73, 174.95, 23.88,
        177.41, 24.08, 179.88, 24.31, 182.34, 24.58, 184.8, 24.9, 187.25, 25.25, 189.69, 25.64,
        192.13, 26.07, 194.57, 26.54, 196.99, 27.05, 199.41, 27.61, 201.82, 28.19, 204.22, 28.82,
        206.62, 29.49, 209.0, 30.2, 211.37, 30.95, 213.73, 31.73, 216.08, 32.56, 218.41, 33.42,
        220.73, 34.32, 223.04, 35.27, 225.33, 36.24, 227.61, 37.26, 229.88, 38.31, 232.12, 39.41,
        234.35, 40.54, 236.57, 41.7, 238.76, 42.9, 240.94, 44.14, 243.1, 45.42, 245.23, 46.73,
        247.35, 48.08, 249.45, 49.46, 251.53, 50.88, 253.58, 52.34, 255.62, 53.83, 257.63, 55.35,
        259.61, 56.91, 261.57, 58.5, 263.51, 60.12, 265.42, 61.78, 267.31, 63.47, 269.17, 65.19,
        271.01, 66.95, 272.82, 68.73, 274.59, 70.55, 276.35, 72.4, 278.07, 74.28, 279.76, 76.19,
        281.42, 78.13, 283.06, 80.1, 284.66, 82.1, 286.23, 84.13, 287.77, 86.18, 289.27, 88.27,
        290.74, 90.38, 292.18, 92.52, 293.58, 94.68, 294.95, 96.87, 296.28, 99.09, 297.58, 101.33,
        298.84, 103.59, 300.07, 105.88, 301.25, 108.2, 302.4, 110.53, 303.51, 112.89, 304.58, 115.27,
        305.61, 117.67, 306.6, 120.09, 307.56, 122.53, 308.46, 124.99, 309.33, 127.47, 310.16, 129.97,
        310.94, 132.48, 311.69, 135.01, 312.38, 137.56, 313.04, 140.12, 313.65, 142.69, 314.22, 145.28,
        314.74, 147.88, 315.22, 150.5, 315.65, 153.12, 316.04, 155.76, 316.38, 158.4, 316.68, 161.06,
        316.93, 163.72, 317.14, 166.39, 317.3, 169.07, 317.41, 171.75, 317.48, 174.44, 317.5, 177.14,
        317.47, 179.83, 317.4, 182.53, 317.27, 185.23, 317.09, 187.93, 316.86, 190.63, 316.57, 193.33,
        316.21, 196.02, 315.79, 198.7, 315.31, 201.37, 314.75, 204.03, 314.13, 206.68, 313.43, 209.31,
        312.65, 211.91, 311.8, 214.5, 310.86, 217.05, 309.85, 219.57, 308.75, 222.06, 307.57, 224.51,
        306.3, 226.91, 304.95, 229.27, 303.52, 231.58, 302.0, 233.84, 300.4, 236.03, 298.71, 238.17,
        296.95, 240.25, 295.12, 242.26, 293.21, 244.21, 291.23, 246.08, 289.19, 247.88, 287.09, 249.62,
        284.93, 251.28, 282.72, 252.86, 280.46, 254.38, 278.16, 255.82, 275.82, 257.19, 273.46, 258.5,
        271.06, 259.73, 268.65, 260.9, 266.22, 262.0, 263.77, 263.05, 261.31, 264.03, 258.85, 264.95,
        256.39, 265.82, 253.93, 266.64, 251.47, 267.4, 249.02, 268.12, 246.58, 268.79, 244.14, 269.42,
        241.73, 270.01, 239.32, 270.57, 236.93, 271.08, 234.56, 271.56, 232.2, 272.01, 229.87, 272.43,
        227.55, 272.82, 225.25, 273.19, 222.96, 273.52, 220.7, 273.84, 218.46, 274.13, 216.23, 274.41,
        214.03, 274.66, 211.84, 274.89, 209.67, 275.11, 207.51, 275.31, 205.38, 275.49, 203.26, 275.67,
        201.15, 275.82,
    ]
    static let stretchedHead: [Double] = [
        200.0, 272.39, 197.97, 272.53, 195.96, 272.65, 193.96, 272.77, 191.98, 272.87, 190.0, 272.96,
        188.04, 273.05, 186.09, 273.12, 184.15, 273.19, 182.21, 273.25, 180.29, 273.3, 178.37, 273.35,
        176.46, 273.39, 174.55, 273.42, 172.65, 273.45, 170.76, 273.47, 168.86, 273.48, 166.97, 273.49,
        165.08, 273.5, 163.19, 273.5, 161.3, 273.5, 159.41, 273.49, 157.52, 273.47, 155.62, 273.45,
        153.72, 273.42, 151.82, 273.39, 149.91, 273.35, 147.99, 273.31, 146.07, 273.26, 144.13, 273.2,
        142.19, 273.13, 140.24, 273.06, 138.28, 272.98, 136.31, 272.88, 134.32, 272.78, 132.33, 272.67,
        130.32, 272.55, 128.29, 272.41, 126.25, 272.27, 124.2, 272.11, 122.13, 271.94, 120.04, 271.75,
        117.94, 271.55, 115.81, 271.34, 113.67, 271.1, 111.52, 270.85, 109.34, 270.58, 107.14, 270.29,
        104.93, 269.97, 102.69, 269.63, 100.44, 269.27, 98.16, 268.88, 95.87, 268.47, 93.56, 268.02,
        91.23, 267.54, 88.89, 267.03, 86.53, 266.48, 84.15, 265.89, 81.77, 265.26, 79.37, 264.59,
        76.96, 263.88, 74.55, 263.11, 72.14, 262.3, 69.72, 261.43, 67.31, 260.51, 64.9, 259.53,
        62.5, 258.49, 60.12, 257.39, 57.75, 256.22, 55.41, 254.99, 53.1, 253.69, 50.82, 252.32,
        48.59, 250.88, 46.39, 249.36, 44.25, 247.78, 42.15, 246.12, 40.12, 244.39, 38.15, 242.59,
        36.25, 240.72, 34.42, 238.78, 32.67, 236.77, 30.99, 234.7, 29.4, 232.57, 27.89, 230.38,
        26.46, 228.14, 25.11, 225.85, 23.85, 223.51, 22.68, 221.12, 21.58, 218.7, 20.58, 216.24,
        19.65, 213.75, 18.8, 211.23, 18.03, 208.69, 17.34, 206.12, 16.72, 203.54, 16.17, 200.94,
        15.69, 198.32, 15.28, 195.7, 14.93, 193.07, 14.64, 190.44, 14.41, 187.8, 14.23, 185.16,
        14.1, 182.52, 14.03, 179.88, 14.0, 177.25, 14.02, 174.61, 14.08, 171.98, 14.19, 169.36,
        14.35, 166.74, 14.54, 164.13, 14.79, 161.53, 15.08, 158.94, 15.41, 156.35, 15.79, 153.77,
        16.21, 151.21, 16.67, 148.65, 17.18, 146.11, 17.74, 143.58, 18.33, 141.06, 18.97, 138.56,
        19.65, 136.07, 20.37, 133.6, 21.14, 131.14, 21.94, 128.7, 22.79, 126.28, 23.68, 123.88,
        24.61, 121.49, 25.57, 119.13, 26.58, 116.78, 27.62, 114.46, 28.7, 112.15, 29.82, 109.87,
        30.98, 107.61, 32.17, 105.37, 33.4, 103.16, 34.67, 100.97, 35.97, 98.81, 37.3, 96.67,
        38.67, 94.55, 40.07, 92.46, 41.51, 90.4, 42.98, 88.36, 44.48, 86.36, 46.01, 84.37,
        47.57, 82.42, 49.16, 80.5, 50.78, 78.6, 52.43, 76.73, 54.11, 74.9, 55.82, 73.09,
        57.56, 71.31, 59.32, 69.57, 61.11, 67.85, 62.92, 66.17, 64.76, 64.52, 66.63, 62.9,
        68.52, 61.31, 70.43, 59.76, 72.37, 58.23, 74.33, 56.75, 76.31, 55.29, 78.31, 53.87,
        80.34, 52.48, 82.38, 51.13, 84.45, 49.81, 86.53, 48.53, 88.64, 47.28, 90.76, 46.07,
        92.9, 44.89, 95.06, 43.75, 97.23, 42.64, 99.42, 41.57, 101.63, 40.54, 103.85, 39.55,
        106.08, 38.59, 108.33, 37.67, 110.6, 36.78, 112.87, 35.94, 115.16, 35.13, 117.46, 34.36,
        119.77, 33.63, 122.1, 32.93, 124.43, 32.27, 126.77, 31.66, 129.12, 31.08, 131.48, 30.54,
        133.84, 30.03, 136.22, 29.57, 138.6, 29.14, 140.98, 28.76, 143.37, 28.41, 145.77, 28.1,
        148.17, 27.83, 150.57, 27.59, 152.98, 27.4, 155.38, 27.24, 157.8, 27.13, 160.21, 27.05,
        162.62, 27.01, 165.03, 27.0, 167.44, 27.04, 169.86, 27.11, 172.27, 27.22, 174.68, 27.37,
        177.08, 27.56, 179.49, 27.79, 181.89, 28.06, 184.28, 28.36, 186.67, 28.7, 189.06, 29.08,
        191.44, 29.5, 193.81, 29.96, 196.18, 30.46, 198.54, 31.0, 200.89, 31.57, 203.23, 32.18,
        205.57, 32.83, 207.89, 33.52, 210.2, 34.25, 212.51, 35.02, 214.8, 35.82, 217.07, 36.66,
        219.34, 37.54, 221.59, 38.45, 223.83, 39.41, 226.05, 40.4, 228.26, 41.42, 230.45, 42.49,
        232.63, 43.59, 234.79, 44.72, 236.93, 45.89, 239.06, 47.1, 241.17, 48.34, 243.25, 49.62,
        245.32, 50.94, 247.37, 52.28, 249.4, 53.67, 251.4, 55.08, 253.39, 56.53, 255.35, 58.02,
        257.29, 59.53, 259.21, 61.08, 261.1, 62.67, 262.97, 64.28, 264.82, 65.93, 266.63, 67.61,
        268.43, 69.32, 270.19, 71.06, 271.93, 72.83, 273.64, 74.64, 275.33, 76.47, 276.98, 78.33,
        278.61, 80.22, 280.2, 82.14, 281.77, 84.09, 283.3, 86.07, 284.81, 88.07, 286.28, 90.1,
        287.72, 92.16, 289.13, 94.25, 290.5, 96.36, 291.84, 98.5, 293.15, 100.66, 294.42, 102.84,
        295.65, 105.05, 296.85, 107.29, 298.01, 109.54, 299.14, 111.82, 300.22, 114.12, 301.27, 116.44,
        302.29, 118.79, 303.26, 121.15, 304.19, 123.53, 305.08, 125.93, 305.94, 128.35, 306.75, 130.79,
        307.52, 133.24, 308.25, 135.71, 308.93, 138.2, 309.58, 140.7, 310.18, 143.22, 310.74, 145.74,
        311.25, 148.28, 311.73, 150.84, 312.15, 153.4, 312.54, 155.98, 312.88, 158.56, 313.17, 161.16,
        313.42, 163.76, 313.63, 166.37, 313.79, 168.98, 313.9, 171.61, 313.97, 174.23, 314.0, 176.87,
        313.98, 179.5, 313.91, 182.14, 313.79, 184.78, 313.62, 187.42, 313.4, 190.06, 313.12, 192.69,
        312.77, 195.32, 312.37, 197.95, 311.9, 200.56, 311.36, 203.16, 310.75, 205.75, 310.07, 208.32,
        309.31, 210.87, 308.48, 213.39, 307.56, 215.88, 306.57, 218.35, 305.49, 220.78, 304.32, 223.17,
        303.08, 225.51, 301.74, 227.81, 300.33, 230.06, 298.83, 232.26, 297.24, 234.4, 295.58, 236.48,
        293.83, 238.49, 292.02, 240.44, 290.12, 242.32, 288.17, 244.13, 286.14, 245.87, 284.06, 247.54,
        281.92, 249.14, 279.73, 250.66, 277.5, 252.12, 275.23, 253.5, 272.92, 254.81, 270.59, 256.05,
        268.22, 257.23, 265.84, 258.34, 263.45, 259.39, 261.04, 260.37, 258.63, 261.3, 256.21, 262.18,
        253.8, 263.0, 251.38, 263.77, 248.98, 264.49, 246.58, 265.17, 244.19, 265.8, 241.81, 266.4,
        239.45, 266.95, 237.11, 267.47, 234.78, 267.95, 232.46, 268.4, 230.17, 268.82, 227.89, 269.22,
        225.63, 269.58, 223.4, 269.92, 221.18, 270.24, 218.98, 270.54, 216.8, 270.81, 214.64, 271.07,
        212.49, 271.3, 210.37, 271.52, 208.26, 271.73, 206.17, 271.91, 204.1, 272.09, 202.04, 272.25,
        200.0, 272.39,
    ]
}
