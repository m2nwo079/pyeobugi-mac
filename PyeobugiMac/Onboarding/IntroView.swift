import AppKit
import CoreText
import QuartzCore
import SwiftUI

// The intro screen in SwiftUI; `start` runs once the screen has turned navy
struct IntroScreen: NSViewRepresentable {
    let start: () -> Void

    func makeNSView(context: Context) -> IntroView {
        IntroView(onStart: start)
    }

    func updateNSView(_ view: IntroView, context: Context) {}

    static func dismantleNSView(_ view: IntroView, coordinator: ()) {
        view.stop()
    }
}

private func srgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

private enum IntroColor {
    static let main1 = srgb(0x16202F)
    static let main2 = srgb(0x2A3747)
    static let main3 = srgb(0x74ABB4)
    static let main5 = srgb(0xEEF3F3)
    static let grey700 = srgb(0x5B636E)
    static let grey900 = srgb(0x2D333B)
    // The start button under the pointer is drawn 1.25 times brighter
    static let main2Hover = srgb(0x344559)
    static let main3Hover = srgb(0x91D6E1)
    static let main5Hover = srgb(0xFFFFFF)
}

// Turtle part images in the 420 x 420 turtle box
private enum IntroArt {
    static let legs = CGRect(x: 57, y: 255, width: 306, height: 43.25)
    static let shell = CGRect(x: 76.75, y: 105, width: 266, height: 209)
    static let flipperLeft = CGRect(x: 57.5, y: 254.25, width: 81.75, height: 75.5)
    static let flipperRight = CGRect(x: 281.75, y: 254.25, width: 81.75, height: 75.5)
    static let head = CGRect(x: 77, y: 74, width: 265.75, height: 218.5)
    static let eyes = CGRect(x: 128.5, y: 171.25, width: 162.25, height: 112)
    static let eyesClosed = CGRect(x: 164.5, y: 220.75, width: 90, height: 10.75)
    static let laptop = CGRect(x: 42, y: 24, width: 1196, height: 808)
    static let sheen = CGRect(x: 0, y: 0, width: 1100, height: 560)
    static let logo = CGRect(x: 217, y: -136, width: 846, height: 520)
    static let screenBorder = 17.6727
    static let screenRadius = 26.5
    static let notch = CGSize(width: 119.9, height: 40.3)
    static let notchTop = -17.7
    static let notchRadius = 4.4
    // Start copy inside the screen's padding box
    static let content = CGPoint(x: -18 + 64, y: -17 + 110)
    static let contentWidth = 1033.0 - 64 * 2
}

// MARK: - Text

private struct IntroTextStyle {
    let font: CTFont
    let lineHeight: Double
    let tracking: Double
    let color: CGColor

    static func pretendard(_ weight: String, size: Double, lineHeight: Double, tracking: Double = 0,
                           color: CGColor) -> IntroTextStyle {
        IntroTextStyle(font: CTFontCreateWithName("Pretendard-\(weight)" as CFString, size, nil),
                  lineHeight: size * lineHeight, tracking: size * tracking, color: color)
    }

    func line(_ text: String) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTKernAttributeName as String): tracking,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    func width(_ text: String) -> Double {
        CTLineGetTypographicBounds(line(text), nil, nil, nil)
    }

    // Baseline in a line box that starts at `top`: glyphs sit in the middle of the box, with ascent and descent
    // rounded to whole points
    func baseline(top: Double) -> Double {
        let ascent = CTFontGetAscent(font).rounded(), descent = CTFontGetDescent(font).rounded()
        return top + (lineHeight - ascent - descent) / 2 + ascent
    }
}

// Draws lines of text at given baselines. The layer is a little larger than its box so glyphs are never clipped
private final class IntroTextLayer: CALayer {
    static let margin = 8.0
    var lines: [(CTLine, CGPoint)] = []

    convenience init(box: CGRect) {
        self.init()
        frame = box.insetBy(dx: -Self.margin, dy: -Self.margin)
        needsDisplayOnBoundsChange = true
    }

    func addLine(_ text: String, _ style: IntroTextStyle, x: Double, top: Double) {
        lines.append((style.line(text), CGPoint(x: x, y: style.baseline(top: top))))
        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        // Inside the flipped view the context already has y pointing down; otherwise flip it here
        if !contentsAreFlipped() {
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        ctx.translateBy(x: Self.margin, y: Self.margin)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (line, origin) in lines {
            ctx.textPosition = origin
            CTLineDraw(line, ctx)
        }
    }
}

// Alpha of a part image, used to hit-test only the painted pixels of the turtle
private struct IntroAlphaMask {
    let width: Int
    let height: Int
    let alpha: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        self.width = width
        self.height = height
        var data = [UInt8](repeating: 0, count: width * height)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        alpha = data
    }

    // Point in the image's box of the given size, y down
    func contains(_ p: CGPoint, in size: CGSize) -> Bool {
        guard p.x >= 0, p.y >= 0, p.x < size.width, p.y < size.height else { return false }
        let x = Int(p.x / size.width * Double(width)), y = Int(p.y / size.height * Double(height))
        // The first bitmap row is the top of the image
        return alpha[y * width + x] > 0
    }
}

// MARK: - View

// The intro stage: a 1280 x 832 scene scaled to cover the view, one Core Animation layer per moving part.
// Frames only change layer transforms, opacity and the screen frame
final class IntroView: NSView {
    private enum Target {
        case button, turtle
    }

    private let scene: IntroScene
    private let onStart: () -> Void
    private let bundle: Bundle
    private let stage = CALayer()
    private var bindings: [(node: IntroNode, layer: CALayer)] = []
    private let screenLayer = CALayer()
    private let padLayer = CALayer()
    private var notchLayer = CALayer()
    private var fillLayer = CALayer()
    private var flipsLayer = CALayer()
    private var frontLayer = CALayer()
    private var buttonLayer = CALayer()
    private let ringLayer = CAShapeLayer()
    private var buttonText: IntroTextLayer?
    private var logoLayer = CALayer()
    private var logoImage: NSImage?
    private var hitParts: [(layer: CALayer, mask: IntroAlphaMask)] = []
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var started = false
    private var stopped = false
    private var closeObserver: NSObjectProtocol?
    private var mouse: CGPoint?
    private var pressed: Target?
    private var ringVisible = false
    private var hovered = false
    private var shownStage: IntroScene.Stage?

    init(onStart: @escaping () -> Void, bundle: Bundle = .main,
         reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        self.onStart = onStart
        self.bundle = bundle
        scene = IntroScene(reduceMotion: reduceMotion)
        super.init(frame: CGRect(origin: .zero, size: IntroScene.size))
        Self.registerFonts(bundle)
        let root = CALayer()
        root.backgroundColor = IntroColor.main1
        layer = root
        wantsLayer = true
        build(in: root)
        scene.onStart = { [weak self] in self?.finish() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // Stage coordinates have a top-left origin with y down; AppKit flips the root layer to match
    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { true }

    private static var fontsRegistered = false

    private static func registerFonts(_ bundle: Bundle) {
        guard !fontsRegistered else { return }
        fontsRegistered = true
        let urls = ["Pretendard-Regular", "Pretendard-SemiBold"].compactMap { bundle.url(forResource: $0, withExtension: "otf") }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }

    // MARK: Layers

    private func image(_ name: String) -> CGImage? {
        bundle.image(forResource: name)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    @discardableResult
    private func imageLayer(_ name: String, _ frame: CGRect, in parent: CALayer) -> CALayer {
        let layer = CALayer()
        layer.contents = image(name)
        layer.frame = frame
        parent.addSublayer(layer)
        return layer
    }

    // A layer for a node: its box in the parent, transforms about the node's origin
    @discardableResult
    private func nodeLayer(_ node: IntroNode, _ frame: CGRect, in parent: CALayer) -> CALayer {
        let layer = CALayer()
        layer.anchorPoint = .zero
        layer.bounds = CGRect(origin: .zero, size: frame.size)
        layer.position = frame.origin
        layer.allowsGroupOpacity = true
        parent.addSublayer(layer)
        bindings.append((node, layer))
        return layer
    }

    private func build(in root: CALayer) {
        let box420 = CGRect(x: 0, y: 0, width: 420, height: 420)
        stage.anchorPoint = .zero
        stage.bounds = CGRect(origin: .zero, size: IntroScene.size)
        stage.masksToBounds = true
        stage.backgroundColor = IntroColor.main1
        root.addSublayer(stage)

        imageLayer("IntroBackground", stage.bounds, in: stage)
        logoImage = bundle.image(forResource: "IntroLogo")
        logoLayer = nodeLayer(scene.logo, IntroArt.logo, in: stage)

        let laptop = nodeLayer(scene.laptop, stage.bounds, in: stage)
        imageLayer("IntroLaptop", IntroArt.laptop, in: laptop)

        let turtleBody = nodeLayer(scene.turtleBody, IntroScene.turtleBox, in: laptop)
        let body = nodeLayer(scene.body, box420, in: turtleBody)
        imageLayer("IntroTurtleLegs", IntroArt.legs, in: body)
        let shell = nodeLayer(scene.shell, box420, in: body)
        imageLayer("IntroTurtleShell", IntroArt.shell, in: shell)

        buildScreen(in: laptop)

        frontLayer = nodeLayer(scene.turtleFront, IntroScene.turtleBox, in: laptop)
        flipsLayer = nodeLayer(scene.flips, box420, in: frontLayer)
        let left = nodeLayer(scene.flipperLeft, box420, in: flipsLayer)
        let leftImage = imageLayer("IntroTurtleFlipperLeft", IntroArt.flipperLeft, in: left)
        let right = nodeLayer(scene.flipperRight, box420, in: flipsLayer)
        let rightImage = imageLayer("IntroTurtleFlipperRight", IntroArt.flipperRight, in: right)
        let bob = nodeLayer(scene.bob, box420, in: frontLayer)
        let head = nodeLayer(scene.head, box420, in: bob)
        let headImage = imageLayer("IntroTurtleHead", IntroArt.head, in: head)
        let look = nodeLayer(scene.look, box420, in: head)
        let blink = nodeLayer(scene.blink, box420, in: look)
        imageLayer("IntroTurtleEyes", IntroArt.eyes, in: blink)
        let closed = nodeLayer(scene.closed, box420, in: head)
        imageLayer("IntroTurtleEyesClosed", IntroArt.eyesClosed, in: closed)

        hitParts = [headImage, leftImage, rightImage].compactMap { layer in
            guard let contents = layer.contents else { return nil }
            // Contents are always a CGImage here
            return IntroAlphaMask(contents as! CGImage).map { (layer, $0) }
        }
    }

    private func buildScreen(in laptop: CALayer) {
        screenLayer.anchorPoint = .zero
        screenLayer.backgroundColor = IntroColor.main5
        screenLayer.borderColor = IntroColor.main1
        screenLayer.borderWidth = IntroArt.screenBorder
        screenLayer.cornerRadius = IntroArt.screenRadius
        screenLayer.masksToBounds = true
        laptop.addSublayer(screenLayer)

        // Padding box: everything inside the screen is clipped to it and placed from its top-left corner
        padLayer.anchorPoint = .zero
        padLayer.position = CGPoint(x: IntroArt.screenBorder, y: IntroArt.screenBorder)
        padLayer.backgroundColor = IntroColor.main5
        padLayer.cornerRadius = IntroArt.screenRadius - IntroArt.screenBorder
        padLayer.masksToBounds = true
        screenLayer.addSublayer(padLayer)
        imageLayer("IntroScreenSheen", IntroArt.sheen, in: padLayer)

        notchLayer = nodeLayer(scene.notch, CGRect(origin: .zero, size: IntroArt.notch), in: padLayer)
        notchLayer.backgroundColor = IntroColor.main1
        notchLayer.cornerRadius = IntroArt.notchRadius

        let origin = IntroArt.content, width = IntroArt.contentWidth
        let display = IntroTextStyle.pretendard("Regular", size: 40, lineHeight: 1.2, tracking: -0.03, color: IntroColor.grey900)
        let body = IntroTextStyle.pretendard("Regular", size: 16, lineHeight: 1.5, color: IntroColor.grey700)
        let item = IntroTextStyle.pretendard("Regular", size: 16, lineHeight: 1.5, color: IntroColor.grey900)
        let number = IntroTextStyle.pretendard("Regular", size: 12, lineHeight: 1.4, color: IntroColor.grey900)
        let label = IntroTextStyle.pretendard("SemiBold", size: 14, lineHeight: 1.4, color: IntroColor.main5)

        // Loading text with four dots that pulse one after another
        let loading = nodeLayer(scene.loadingText, CGRect(x: origin.x, y: origin.y, width: width, height: 48), in: padLayer)
        let word = IntroTextLayer(box: loading.bounds)
        word.addLine("Loading", display, x: 0, top: 0)
        loading.addSublayer(word)
        var x = display.width("Loading")
        for dot in scene.dots {
            let dotWidth = display.width(".")
            let layer = nodeLayer(dot, CGRect(x: x, y: 0, width: dotWidth, height: 48), in: loading)
            let text = IntroTextLayer(box: layer.bounds)
            text.addLine(".", display, x: 0, top: 0)
            layer.addSublayer(text)
            x += dotWidth
        }

        // Start copy: heading and description, three points, and the start button, 36 apart
        let content = nodeLayer(scene.startContent, CGRect(x: origin.x, y: origin.y, width: width, height: 372), in: padLayer)
        let intro = nodeLayer(scene.startItems[0], CGRect(x: 0, y: 0, width: width, height: 160), in: content)
        let introText = IntroTextLayer(box: intro.bounds)
        introText.addLine("당신의 자세 건강,", display, x: 0, top: 0)
        introText.addLine("펴부기가 지켜드릴게요.", display, x: 0, top: 48)
        introText.addLine("공부하거나 일하는 동안 웹캠으로 앉은 자세를 살피고,", body, x: 0, top: 112)
        introText.addLine("자세가 구부정해지기 시작하면 펴부기가 알려드려요.", body, x: 0, top: 136)
        intro.addSublayer(introText)

        let points = nodeLayer(scene.startItems[1], CGRect(x: 0, y: 196, width: width, height: 96), in: content)
        let pointText = IntroTextLayer(box: points.bounds)
        for (i, text) in Self.points.enumerated() {
            let top = Double(i) * 36
            let circle = CALayer()
            circle.frame = CGRect(x: 0, y: top + 4, width: 16, height: 16)
            circle.borderWidth = 1
            circle.borderColor = IntroColor.grey900
            circle.cornerRadius = 8
            points.addSublayer(circle)
            let digit = String(i + 1)
            // Centred in the 14 x 14 content box inside the border
            pointText.addLine(digit, number, x: 1 + (14 - number.width(digit)) / 2, top: top + 4 + 1 + (14 - number.lineHeight) / 2)
            pointText.addLine(text, item, x: 24, top: top)
        }
        points.addSublayer(pointText)

        let row = nodeLayer(scene.startItems[2], CGRect(x: 0, y: 328, width: width, height: 44), in: content)
        buttonLayer = nodeLayer(scene.button, CGRect(x: 0, y: 0, width: 200, height: 44), in: row)
        buttonLayer.cornerRadius = 6
        buttonLayer.backgroundColor = IntroColor.main2
        let text = IntroTextLayer(box: buttonLayer.bounds)
        // Centred in the content box inside 10 x 16 padding
        text.addLine("시작하기", label, x: 16 + (168 - label.width("시작하기")) / 2, top: 10 + (24 - label.lineHeight) / 2)
        buttonLayer.addSublayer(text)
        buttonText = text
        // Focus ring: 3 wide, 3 outside the button, following its corners
        ringLayer.path = CGPath(roundedRect: buttonLayer.bounds.insetBy(dx: -4.5, dy: -4.5), cornerWidth: 10.5,
                                cornerHeight: 10.5, transform: nil)
        ringLayer.fillColor = nil
        ringLayer.strokeColor = IntroColor.main3
        ringLayer.lineWidth = 3
        ringLayer.isHidden = true
        buttonLayer.addSublayer(ringLayer)

        fillLayer = nodeLayer(scene.screenFill, .zero, in: padLayer)
        fillLayer.backgroundColor = IntroColor.main1
    }

    private static let points = [
        "웹캠으로 자세를 실시간으로 살펴요",
        "영상은 기기 안에서만 처리돼요",
        "자세가 무너지면 펴부기가 알려줘요",
    ]

    // MARK: Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            stop()
            return
        }
        guard !started, !stopped else { return }
        started = true
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        applyScale()
        fit()
        window.makeFirstResponder(self)
        startTime = CACurrentMediaTime()
        scene.run()
        let link = displayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
        render()
    }

    // Stops the display link, every pending step of the sequence and pointer tracking
    func stop() {
        guard !stopped else { return }
        stopped = true
        link?.invalidate()
        link = nil
        for area in trackingAreas { removeTrackingArea(area) }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
    }

    private func finish() {
        stop()
        onStart()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyScale()
    }

    private func applyScale() {
        let scale = window?.backingScaleFactor ?? 2
        func visit(_ layer: CALayer) {
            layer.contentsScale = scale
            if layer is IntroTextLayer { layer.setNeedsDisplay() }
            layer.sublayers?.forEach(visit)
        }
        if let layer { visit(layer) }
        logoLayer.contents = logoImage?.layerContents(forContentsScale: scale)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fit()
    }

    // Scales the stage to cover the view while keeping its aspect ratio, centred
    private func fit() {
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        let s = max(w / IntroScene.size.width, h / IntroScene.size.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.setAffineTransform(CGAffineTransform(translationX: (w - IntroScene.size.width * s) / 2,
                                                   y: (h - IntroScene.size.height * s) / 2).scaledBy(x: s, y: s))
        CATransaction.commit()
    }

    @objc private func step(_ link: CADisplayLink) {
        render()
    }

    private func render() {
        guard !stopped else { return }
        let t = (CACurrentMediaTime() - startTime) * 1000
        scene.frame(at: t)
        guard !stopped else { return }
        apply(at: t)
    }

    // Applies the scene at time t to the layers
    func apply(at t: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (node, layer) in bindings {
            let value = node.value(at: t)
            layer.setAffineTransform(node.placed(value.transform))
            layer.opacity = Float(value.opacity)
        }
        let rect = scene.screen.value(at: t).rect
        let border = IntroArt.screenBorder
        screenLayer.bounds = CGRect(origin: .zero, size: rect.size)
        screenLayer.position = rect.origin
        let pad = CGSize(width: rect.width - border * 2, height: rect.height - border * 2)
        padLayer.bounds = CGRect(origin: .zero, size: pad)
        notchLayer.position = CGPoint(x: pad.width / 2 - IntroArt.notch.width / 2, y: IntroArt.notchTop)
        fillLayer.bounds = padLayer.bounds
        flipsLayer.zPosition = scene.flipsOnTop ? 2 : 0
        updateHover()
        let hover = hovered
        buttonLayer.backgroundColor = hover ? IntroColor.main2Hover : IntroColor.main2
        ringLayer.strokeColor = hover ? IntroColor.main3Hover : IntroColor.main3
        ringLayer.isHidden = !(ringVisible && scene.buttonFocused)
        CATransaction.commit()
        if shownStage != scene.stage {
            shownStage = scene.stage
            NSAccessibility.post(element: self, notification: .layoutChanged)
        }
    }

    // The button label also brightens; it is redrawn only when the hover state changes
    private func updateHover() {
        let now = scene.interactive && mouse.map { target(at: $0) == .button } == true
        guard now != hovered else { return }
        hovered = now
        buttonText?.lines = buttonText?.lines.map { line, origin in
            let label = IntroTextStyle.pretendard("SemiBold", size: 14, lineHeight: 1.4,
                                             color: now ? IntroColor.main5Hover : IntroColor.main5)
            return (label.line("시작하기"), origin)
        } ?? []
        buttonText?.setNeedsDisplay()
    }

    // MARK: Input

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        guard !stopped else { return }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate,
                                                               .activeAlways, .inVisibleRect], owner: self))
    }

    private func stagePoint(_ p: CGPoint) -> CGPoint {
        p.applying(stage.affineTransform().inverted())
    }

    private func target(at p: CGPoint) -> Target? {
        let s = stagePoint(p)
        for (layer, mask) in hitParts where mask.contains(layer.convert(s, from: stage), in: layer.bounds.size) {
            return .turtle
        }
        if scene.interactive, buttonLayer.bounds.contains(buttonLayer.convert(s, from: stage)) {
            return .button
        }
        return nil
    }

    private func pointer(_ event: NSEvent) {
        guard !stopped else { return }
        let p = convert(event.locationInWindow, from: nil)
        mouse = p
        scene.pointerMoved(to: stagePoint(p), turtle: stage.convert(frontLayer.bounds, from: frontLayer))
        updateCursor()
    }

    override func mouseMoved(with event: NSEvent) { pointer(event) }

    override func mouseDragged(with event: NSEvent) { pointer(event) }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        NSCursor.arrow.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor()
    }

    private func updateCursor() {
        guard !stopped, let mouse else { return }
        (target(at: mouse) == nil ? NSCursor.arrow : NSCursor.pointingHand).set()
    }

    override func mouseDown(with event: NSEvent) {
        guard !stopped else { return }
        let p = convert(event.locationInWindow, from: nil)
        pressed = target(at: p)
        // A click moves focus away from the ring; clicking elsewhere also blurs the button
        ringVisible = false
        if pressed != .button { scene.buttonFocused = false }
    }

    override func mouseUp(with event: NSEvent) {
        guard !stopped else { return }
        let hit = target(at: convert(event.locationInWindow, from: nil))
        defer { pressed = nil }
        guard let hit, hit == pressed else { return }
        switch hit {
        case .button: scene.expand()
        case .turtle: scene.poke()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard !stopped else { return super.keyDown(with: event) }
        switch event.keyCode {
        // Tab and Shift-Tab: the button is the only focusable element, so focus goes on and off it
        case 48:
            if scene.buttonFocused {
                ringVisible = false
                scene.buttonFocused = false
            } else if scene.interactive {
                ringVisible = true
                scene.buttonFocused = true
            }
        // Return and keypad Enter press the focused button
        case 36, 76:
            if scene.buttonFocused { scene.expand() }
        // Space presses it when released
        case 49:
            break
        default:
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49, !stopped, scene.buttonFocused {
            scene.expand()
        } else {
            super.keyUp(with: event)
        }
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityChildren() -> [Any]? {
        guard let root = layer else { return [] }
        func frame(_ layer: CALayer, _ rect: CGRect? = nil) -> CGRect {
            NSAccessibility.screenRect(fromView: self, rect: layer.convert(rect ?? layer.bounds, to: root))
        }
        func text(_ label: String, _ layer: CALayer, _ rect: CGRect? = nil) -> NSAccessibilityElement {
            NSAccessibilityElement.element(withRole: .staticText, frame: frame(layer, rect), label: label, parent: self)
                as! NSAccessibilityElement
        }
        if scene.stage == .loading {
            return [text("Loading", bindings.first { $0.node === scene.loadingText }!.layer)]
        }
        let content = bindings.first { $0.node === scene.startContent }!.layer
        var elements: [Any] = [
            text("당신의 자세 건강, 펴부기가 지켜드릴게요.", content, CGRect(x: 0, y: 0, width: IntroArt.contentWidth, height: 96)),
            text("공부하거나 일하는 동안 웹캠으로 앉은 자세를 살피고, 자세가 구부정해지기 시작하면 펴부기가 알려드려요.", content,
                 CGRect(x: 0, y: 112, width: IntroArt.contentWidth, height: 48)),
        ]
        for (i, point) in Self.points.enumerated() {
            elements.append(text("\(i + 1). \(point)", content,
                                 CGRect(x: 0, y: 196 + Double(i) * 36, width: IntroArt.contentWidth, height: 24)))
        }
        if scene.interactive {
            let button = IntroButtonElement()
            button.setAccessibilityRole(.button)
            button.setAccessibilityLabel("시작하기")
            button.setAccessibilityParent(self)
            button.setAccessibilityFrame(frame(buttonLayer))
            button.press = { [weak self] in self?.scene.expand() }
            elements.append(button)
        }
        return elements
    }
}

private final class IntroButtonElement: NSAccessibilityElement {
    var press: () -> Void = {}

    override func accessibilityPerformPress() -> Bool {
        press()
        return true
    }
}
