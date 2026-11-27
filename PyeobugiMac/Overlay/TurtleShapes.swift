import SwiftUI

// Every drawing uses a square box of `units` with the feet on y = foot.
// Side views face left; right-facing headings are mirrored by the figure
enum TurtleArt {
    static let units = 500.0
    static let foot = 400.0
    static let stroke = 7.0

    // Side view neck: a vertical tube from the shell up to where the head attaches
    static let neckX = 150.0
    static let neckBase = 330.0
    static let headAttach = 262.0
    static let neckWidth = 90.0

    // Side head ellipse relative to the attach point
    static let headCenter = CGPoint(x: -30, y: -47)
    static let headRadius = CGSize(width: 80, height: 58)
    // Extra room for the head tilting up as the neck stretches
    static let tiltMargin = 10.0
    static let stretchTilt = 14.0

    // Reach of one neck column from its centre toward the face and toward the back
    static let faceReach = -headCenter.x + headRadius.width + stroke / 2
    static let backReach = neckWidth / 2 + stroke / 2
    // Height of the head above its attach point
    static let headHeight = -headCenter.y + headRadius.height + stroke / 2 + tiltMargin

    static let skin = Color(hex: 0x34A8A8)
    static let ink = Color(hex: 0x0F3838)
    static let shell = Color(hex: 0x008180)
    static let shellLine = Color(hex: 0x014A49)
    static let light = Color(hex: 0xCFF4F0)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private extension Path {
    func rotated(_ degrees: Double, about pivot: CGPoint) -> Path {
        applying(
            CGAffineTransform(translationX: pivot.x, y: pivot.y)
                .rotated(by: degrees * .pi / 180)
                .translatedBy(x: -pivot.x, y: -pivot.y)
        )
    }

    func moved(_ dx: Double, _ dy: Double) -> Path {
        offsetBy(dx: dx, dy: dy)
    }

    // Vertical squash around a centre line, for blinking
    func squashed(_ height: Double, aroundY y: Double) -> Path {
        applying(CGAffineTransform(translationX: 0, y: y).scaledBy(x: 1, y: max(0.001, height)).translatedBy(x: 0, y: -y))
    }
}

private func circle(_ x: Double, _ y: Double, _ r: Double) -> Path {
    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
}

private func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> Path {
    Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry))
}

private func rounded(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> Path {
    Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
}

private func curve(_ from: CGPoint, _ to: CGPoint, _ control: CGPoint) -> Path {
    Path { p in
        p.move(to: from)
        p.addQuadCurve(to: to, control: control)
    }
}

// A filled piece with the ink outline
private struct Piece: View {
    let path: Path
    var fill = TurtleArt.skin

    var body: some View {
        path.fill(fill)
            .overlay(path.stroke(TurtleArt.ink, style: StrokeStyle(lineWidth: TurtleArt.stroke, lineCap: .round, lineJoin: .round)))
    }
}

// An ink line without fill
private struct Line: View {
    let path: Path
    var color = TurtleArt.ink
    var width = TurtleArt.stroke

    var body: some View {
        path.stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}

// Dome shell with a rim and a few plates
private struct Shell: View {
    let left: Double
    let right: Double
    let base: Double
    let crest: Double

    var body: some View {
        let mid = (left + right) / 2
        let dome = Path { p in
            p.move(to: CGPoint(x: left, y: base))
            p.addCurve(to: CGPoint(x: right, y: base), control1: CGPoint(x: left + 10, y: crest), control2: CGPoint(x: right - 10, y: crest))
            p.closeSubpath()
        }
        let inset = (right - left) * 0.14
        let innerCrest = crest + (base - crest) * 0.3
        let innerTop = base * 0.25 + innerCrest * 0.75
        let plates = Path { p in
            p.move(to: CGPoint(x: left + inset, y: base))
            p.addCurve(to: CGPoint(x: right - inset, y: base), control1: CGPoint(x: left + inset + 8, y: innerCrest), control2: CGPoint(x: right - inset - 8, y: innerCrest))
            p.move(to: CGPoint(x: mid, y: innerTop))
            p.addLine(to: CGPoint(x: mid, y: base))
            p.move(to: CGPoint(x: left + inset * 1.6, y: (base + innerTop) / 2 + 6))
            p.addLine(to: CGPoint(x: right - inset * 1.6, y: (base + innerTop) / 2 + 6))
        }
        ZStack {
            Piece(path: dome, fill: TurtleArt.shell)
            Line(path: plates, color: TurtleArt.shellLine, width: 6)
            Piece(path: rounded(left - 12, base - 14, right - left + 24, 28, 14), fill: TurtleArt.light)
        }
    }
}

// Side head whose origin is the top of the neck; angle tilts it, positive lifts the face
private struct SideHead: View {
    let at: CGPoint
    let angle: Double
    let morph: Double
    let eyeOpen: Double

    var body: some View {
        let c = TurtleArt.headCenter, r = TurtleArt.headRadius
        let place = { (path: Path) -> Path in
            path.rotated(angle, about: .zero).moved(at.x, at.y)
        }
        let eye = CGPoint(x: c.x - 28, y: c.y - 15)
        let mouthDrop = 8 * morph
        ZStack {
            Piece(path: place(ellipse(c.x, c.y, r.width, r.height)))
            Line(path: place(curve(CGPoint(x: c.x - 74, y: c.y + 17), CGPoint(x: c.x - 32, y: c.y + 23 + mouthDrop), CGPoint(x: c.x - 54, y: c.y + 25 + mouthDrop))))
            place(circle(c.x - 70, c.y - 11, 3.5)).fill(TurtleArt.ink)
            Piece(path: place(circle(eye.x, eye.y, 17).squashed(eyeOpen, aroundY: eye.y)), fill: TurtleArt.light)
            place(circle(eye.x - 5, eye.y, 10).squashed(eyeOpen, aroundY: eye.y)).fill(TurtleArt.ink)
        }
    }
}

// Neck tubes: filled body with outlines only on the two long sides
private struct Tubes: View {
    let tubes: [NeckTube]

    var body: some View {
        let pad = NeckStretch.tubePad
        let fill = Path { p in
            for t in tubes {
                let w = TurtleArt.neckWidth * t.widthScale
                p.addRect(CGRect(x: t.x - w / 2, y: t.top - pad, width: w, height: t.bottom - t.top + 2 * pad))
            }
        }
        let sides = Path { p in
            for t in tubes {
                let w = TurtleArt.neckWidth * t.widthScale
                for x in [t.x - w / 2, t.x + w / 2] {
                    p.move(to: CGPoint(x: x, y: t.top - pad))
                    p.addLine(to: CGPoint(x: x, y: t.bottom + pad))
                }
            }
        }
        ZStack {
            fill.fill(TurtleArt.skin)
            Line(path: sides)
        }
    }
}

private struct Heads: View {
    let heads: [NeckHead]
    let frame: TurtleFrame

    var body: some View {
        ZStack {
            ForEach(heads.indices, id: \.self) { i in
                let h = heads[i]
                SideHead(
                    at: CGPoint(x: h.x, y: h.attach + frame.headLift),
                    angle: TurtleArt.stretchTilt * h.morph + frame.headAngle,
                    morph: h.morph,
                    eyeOpen: frame.eyeOpen
                )
            }
        }
    }
}

private struct SideTurtle: View {
    let frame: TurtleFrame

    var body: some View {
        let neck = frame.neck ?? NeckLayout()
        ZStack {
            Tubes(tubes: neck.back)
            Heads(heads: neck.backHeads, frame: frame)
            Piece(path: Path { p in
                p.move(to: CGPoint(x: 430, y: 336))
                p.addQuadCurve(to: CGPoint(x: 480, y: 354), control: CGPoint(x: 465, y: 334))
                p.addLine(to: CGPoint(x: 432, y: 364))
                p.closeSubpath()
            }.rotated(frame.tailAngle, about: CGPoint(x: 432, y: 350)))
            Piece(path: rounded(368, 322, 46, 78, 20).rotated(frame.backLeg.angle, about: CGPoint(x: 391, y: 330)).moved(0, frame.backLeg.lift))
            Tubes(tubes: neck.front)
            Piece(path: rounded(196, 322, 46, 78, 20).rotated(frame.frontLeg.angle, about: CGPoint(x: 219, y: 330)).moved(0, frame.frontLeg.lift))
            Shell(left: 165, right: 440, base: 342, crest: 170)
            Heads(heads: neck.frontHeads, frame: frame)
        }
    }
}

// Two eyes looking at the viewer, or closed lids
private struct FaceEyes: View {
    let eyes: [(CGPoint, Double)]
    let frame: TurtleFrame
    let place: (Path) -> Path

    var body: some View {
        ZStack {
            ForEach(eyes.indices, id: \.self) { i in
                let (c, r) = eyes[i]
                if frame.eyesClosed {
                    Line(path: place(curve(CGPoint(x: c.x - r, y: c.y), CGPoint(x: c.x + r, y: c.y), CGPoint(x: c.x, y: c.y + r * 0.8))))
                } else {
                    Piece(path: place(circle(c.x, c.y, r).squashed(frame.eyeOpen, aroundY: c.y)), fill: TurtleArt.light)
                    place(circle(c.x, c.y + 2, r * 0.58).squashed(frame.eyeOpen, aroundY: c.y)).fill(TurtleArt.ink)
                }
            }
        }
    }
}

private struct FrontTurtle: View {
    let frame: TurtleFrame

    var body: some View {
        // The head shakes around the bottom of its face, shifting sideways in its own frame
        let pivot = CGPoint(x: 250, y: 258)
        let shake = CGAffineTransform(translationX: pivot.x, y: pivot.y)
            .rotated(by: frame.headAngle * .pi / 180)
            .translatedBy(x: frame.headShift, y: 0)
            .translatedBy(x: -pivot.x, y: -pivot.y)
        let place = { (path: Path) -> Path in path.applying(shake) }
        ZStack {
            Shell(left: 105, right: 395, base: 340, crest: 150)
            Piece(path: rounded(130, 318, 52, 82, 22))
            Piece(path: rounded(318, 318, 52, 82, 22))
            Piece(path: ellipse(250, 330, 100, 40), fill: TurtleArt.light)
            Piece(path: rounded(212, 240, 76, 70, 10))
            Piece(path: place(ellipse(250, 205, 80, 66)))
            FaceEyes(eyes: [(CGPoint(x: 220, y: 198), 18), (CGPoint(x: 280, y: 198), 18)], frame: frame, place: place)
            place(circle(243, 224, 3)).fill(TurtleArt.ink)
            place(circle(257, 224, 3)).fill(TurtleArt.ink)
            Line(path: place(curve(CGPoint(x: 232, y: 240), CGPoint(x: 268, y: 240), CGPoint(x: 250, y: 254))))
        }
    }
}

private struct FrontLeftTurtle: View {
    let frame: TurtleFrame

    var body: some View {
        ZStack {
            Piece(path: Path { p in
                p.move(to: CGPoint(x: 420, y: 338))
                p.addQuadCurve(to: CGPoint(x: 456, y: 352), control: CGPoint(x: 446, y: 334))
                p.addLine(to: CGPoint(x: 422, y: 360))
                p.closeSubpath()
            }.rotated(frame.tailAngle, about: CGPoint(x: 422, y: 348)))
            Piece(path: rounded(372, 326, 42, 74, 18))
            Shell(left: 140, right: 425, base: 342, crest: 165)
            Piece(path: rounded(150, 322, 50, 78, 20))
            Piece(path: rounded(296, 326, 46, 74, 18))
            Piece(path: rounded(160, 250, 74, 80, 10))
            Piece(path: ellipse(190, 210, 78, 64))
            FaceEyes(eyes: [(CGPoint(x: 160, y: 202), 16), (CGPoint(x: 216, y: 204), 14)], frame: frame, place: { $0 })
            Line(path: curve(CGPoint(x: 170, y: 242), CGPoint(x: 204, y: 244), CGPoint(x: 186, y: 254)))
        }
    }
}

private struct BackTurtle: View {
    let frame: TurtleFrame

    var body: some View {
        ZStack {
            Piece(path: ellipse(250, 182, 62, 50))
            Piece(path: rounded(135, 325, 50, 75, 20))
            Piece(path: rounded(315, 325, 50, 75, 20))
            Piece(path: Path { p in
                p.move(to: CGPoint(x: 238, y: 360))
                p.addLine(to: CGPoint(x: 250, y: 396))
                p.addLine(to: CGPoint(x: 262, y: 360))
                p.closeSubpath()
            }.rotated(frame.tailAngle, about: CGPoint(x: 250, y: 362)))
            Shell(left: 95, right: 405, base: 350, crest: 120)
        }
    }
}

private struct BackLeftTurtle: View {
    let frame: TurtleFrame

    var body: some View {
        ZStack {
            Piece(path: ellipse(170, 196, 62, 52))
            Piece(path: rounded(140, 330, 46, 70, 18))
            Piece(path: rounded(338, 330, 46, 70, 18))
            Piece(path: Path { p in
                p.move(to: CGPoint(x: 418, y: 342))
                p.addQuadCurve(to: CGPoint(x: 458, y: 362), control: CGPoint(x: 450, y: 340))
                p.addLine(to: CGPoint(x: 420, y: 366))
                p.closeSubpath()
            }.rotated(frame.tailAngle, about: CGPoint(x: 420, y: 354)))
            Shell(left: 120, right: 425, base: 348, crest: 140)
        }
    }
}

struct TurtleFigure: View {
    let frame: TurtleFrame

    var body: some View {
        let anchor = UnitPoint(x: 0.5, y: TurtleSize.footLine)
        drawing
            .frame(width: TurtleArt.units, height: TurtleArt.units)
            .scaleEffect(x: frame.flipped ? -1 : 1, y: 1)
            .scaleEffect(frame.size / TurtleArt.units, anchor: .topLeading)
            .frame(width: frame.size, height: frame.size, alignment: .topLeading)
            .scaleEffect(frame.bobScale, anchor: anchor)
            .rotationEffect(.degrees(frame.bobAngle), anchor: anchor)
            .offset(y: frame.bobOffset)
            .scaleEffect(frame.hopScale, anchor: anchor)
            .offset(y: frame.hopOffset)
    }

    @ViewBuilder
    private var drawing: some View {
        switch frame.look {
        case .side, .long: SideTurtle(frame: frame)
        case .front: FrontTurtle(frame: frame)
        case .frontLeft: FrontLeftTurtle(frame: frame)
        case .back: BackTurtle(frame: frame)
        case .backLeft: BackLeftTurtle(frame: frame)
        }
    }
}
