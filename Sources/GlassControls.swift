import Cocoa
import QuartzCore

// Glass controls. Their motion follows the "UI Moments" reference: a switch knob that
// turns into a stretching glass lens (Stretch Toggle), buttons that squash and spring back
// (Squash Play), a send button that launches a paper plane (Paper Plane), an install
// button that shrinks into a ring and ticks (Download Ring), and a selection blob that
// stretches as it slides (Gooey Tab Bar).

// MARK: - Motion

/// A damped spring, integrated in small fixed steps. It behaves the same at any frame
/// rate, so tests and the render harness can step it without a display.
struct Spring {
    var value: CGFloat
    var velocity: CGFloat = 0
    var target: CGFloat
    var stiffness: CGFloat
    var damping: CGFloat
    var tolerance: CGFloat

    init(_ value: CGFloat, stiffness: CGFloat, damping: CGFloat, tolerance: CGFloat = 0.0005) {
        self.value = value
        self.target = value
        self.stiffness = stiffness
        self.damping = damping
        self.tolerance = tolerance
    }

    var isSettled: Bool {
        abs(value - target) < tolerance && abs(velocity) < tolerance * 10
    }

    mutating func snap() {
        value = target
        velocity = 0
    }

    mutating func step(_ dt: CGFloat) {
        if isSettled {
            snap()
            return
        }
        let substeps = max(1, Int((dt * 600).rounded(.up)))
        let h = dt / CGFloat(substeps)
        for _ in 0..<substeps {
            let acceleration = -stiffness * (value - target) - damping * velocity
            velocity += acceleration * h
            value += velocity * h
        }
        if isSettled { snap() }
    }
}

enum Motion {
    static let frame: CGFloat = 1.0 / 120.0

    static var isReduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// Calls `tick` at display rate until it returns false.
final class AnimationDriver {
    private var timer: Timer?
    private var lastTime: CFTimeInterval = 0
    private let tick: (CGFloat) -> Bool

    init(tick: @escaping (CGFloat) -> Bool) {
        self.tick = tick
    }

    func start() {
        guard timer == nil else { return }
        lastTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: Double(Motion.frame), repeats: true) { [weak self] _ in
            self?.fire()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func fire() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(max(now - lastTime, 1.0 / 480.0), 1.0 / 20.0))
        lastTime = now
        if !tick(dt) { stop() }
    }

    deinit {
        timer?.invalidate()
    }
}

@inline(__always) func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
    min(max(value, lower), upper)
}

@inline(__always) func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

private func withoutImplicitAnimation(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}

private func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    guard rect.width > 0, rect.height > 0 else { return CGPath(rect: .zero, transform: nil) }
    let r = max(0, min(radius, rect.width / 2, rect.height / 2))
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

// MARK: - Glass material

/// A capsule of glass: a translucent fill, a highlight that fades down from the top edge,
/// and a rim that is bright above and faint below.
final class GlassLayer: CALayer {
    let fill = CALayer()
    let highlight = CAGradientLayer()
    let rim = CAGradientLayer()
    private let highlightMask = CAShapeLayer()
    private let rimMask = CAShapeLayer()

    override init() {
        super.init()
        addSublayer(fill)
        addSublayer(highlight)
        addSublayer(rim)
        highlight.startPoint = CGPoint(x: 0.5, y: 1)
        highlight.endPoint = CGPoint(x: 0.5, y: 0)
        highlight.locations = [0, 0.55, 1]
        highlight.mask = highlightMask
        rim.startPoint = CGPoint(x: 0.5, y: 1)
        rim.endPoint = CGPoint(x: 0.5, y: 0)
        rimMask.fillColor = nil
        rimMask.strokeColor = NSColor.black.cgColor
        rimMask.lineWidth = 1
        rim.mask = rimMask
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func layout(cornerRadius radius: CGFloat) {
        let rect = bounds
        let r = max(0, min(radius, rect.width / 2, rect.height / 2))
        fill.frame = rect
        fill.cornerRadius = r
        highlight.frame = rect
        highlightMask.frame = rect
        highlightMask.path = roundedPath(rect, radius: r)
        rim.frame = rect
        rimMask.frame = rect
        rimMask.path = roundedPath(rect.insetBy(dx: 0.5, dy: 0.5), radius: r - 0.5)
    }
}

/// A shadow drawn only outside its shape, so it never darkens see-through glass.
final class OuterShadowLayer: CALayer {
    private let cutout = CAShapeLayer()

    override init() {
        super.init()
        cutout.fillRule = .evenOdd
        mask = cutout
        shadowColor = NSColor.black.cgColor
        shadowOffset = CGSize(width: 0, height: -1)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(radius: CGFloat) {
        let shape = roundedPath(bounds, radius: radius)
        shadowPath = shape
        let outline = CGMutablePath()
        outline.addRect(bounds.insetBy(dx: -24, dy: -24))
        outline.addPath(shape)
        cutout.frame = bounds
        cutout.path = outline
    }
}

// MARK: - Glass switch

/// An on/off switch. While it is held or moving, the knob turns into a glass lens: it
/// clears, swells a little and stretches along its path, then settles back to solid.
final class ToggleSwitch: NSControl {
    enum Size {
        case regular
        case small
    }

    var size: Size = .regular {
        didSet {
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            position.target = isOn ? 1 : 0
            setAccessibilityValue(isOn ? 1 : 0)
            animate()
        }
    }

    /// While busy the switch ignores clicks, and the knob breathes as glass.
    var isBusy = false {
        didSet {
            if isBusy != oldValue { animate() }
        }
    }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.45 }
    }

    private var position = Spring(0, stiffness: 380, damping: 24)
    private var press = Spring(0, stiffness: 700, damping: 40)
    private var hover = Spring(0, stiffness: 400, damping: 34)
    private var breath: CGFloat = 0

    private let track = CALayer()
    private let trackTint = CALayer()
    private let knobShadow = OuterShadowLayer()
    private let knob = GlassLayer()
    private lazy var driver = AnimationDriver { [weak self] dt in
        self?.advance(dt) ?? false
    }

    private var isTracking = false
    private var didDrag = false
    private var dragStartX: CGFloat = 0
    private var dragStartPosition: CGFloat = 0

    convenience init(size: Size) {
        self.init(frame: .zero)
        self.size = size
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        track.masksToBounds = true
        track.addSublayer(trackTint)
        layer?.addSublayer(track)
        layer?.addSublayer(knobShadow)
        layer?.addSublayer(knob)
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityValue(0)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        size == .regular ? NSSize(width: 56, height: 30) : NSSize(width: 38, height: 22)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        render()
    }

    override func layout() {
        super.layout()
        render()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        render()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hover.target = 1
        animate()
    }

    override func mouseExited(with event: NSEvent) {
        hover.target = 0
        animate()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, !isBusy else { return }
        isTracking = true
        didDrag = false
        dragStartX = convert(event.locationInWindow, from: nil).x
        dragStartPosition = position.target
        press.target = 1
        animate()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTracking else { return }
        let dx = convert(event.locationInWindow, from: nil).x - dragStartX
        if abs(dx) > 3 { didDrag = true }
        guard didDrag else { return }
        let travel = max(1, bounds.width - bounds.height)
        position.target = clamp(dragStartPosition + dx / travel, 0, 1)
        animate()
    }

    override func mouseUp(with event: NSEvent) {
        guard isTracking else { return }
        isTracking = false
        press.target = 0
        let newValue = didDrag ? position.target >= 0.5 : !isOn
        if newValue != isOn {
            isOn = newValue
            sendAction(action, to: target)
        } else {
            position.target = isOn ? 1 : 0
        }
        animate()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, !isBusy else { return false }
        isOn.toggle()
        sendAction(action, to: target)
        return true
    }

    /// Sets the state. Without animation the knob jumps, which suits the first display.
    func setOn(_ on: Bool, animated: Bool) {
        isOn = on
        if !animated {
            position.target = on ? 1 : 0
            position.snap()
            render()
        }
    }

    /// Steps every animation by `seconds`. Used by tests and the render harness.
    func advanceAnimations(by seconds: CGFloat) {
        var elapsed: CGFloat = 0
        while elapsed < seconds {
            _ = advance(Motion.frame)
            elapsed += Motion.frame
        }
    }

    private func animate() {
        if Motion.isReduced {
            position.snap()
            press.snap()
            hover.snap()
            render()
            return
        }
        driver.start()
    }

    private func advance(_ dt: CGFloat) -> Bool {
        position.step(dt)
        press.step(dt)
        hover.step(dt)
        if isBusy { breath += dt * 4.2 }
        render()
        return isBusy || !(position.isSettled && press.isSettled && hover.isSettled)
    }

    private func render() {
        let rect = bounds
        guard rect.width > 4, rect.height > 4 else { return }
        withoutImplicitAnimation {
            let regular = size == .regular
            let trackRect = regular ? rect.insetBy(dx: 1, dy: 2) : rect.insetBy(dx: 1, dy: 1)
            let trackRadius = trackRect.height / 2
            track.frame = trackRect
            track.cornerRadius = trackRadius
            trackTint.frame = track.bounds
            trackTint.cornerRadius = trackRadius

            let p = clamp(position.value, -0.06, 1.06)
            let speed = abs(position.velocity)
            let busyGlass: CGFloat = isBusy ? (Motion.isReduced ? 0.5 : 0.5 + 0.22 * sin(breath)) : 0
            let glass = clamp(max(press.value, speed / 4, busyGlass), 0, 1)

            // The knob: stretched by speed and by the press, then swollen into a lens.
            let inset: CGFloat = regular ? 2.5 : 2
            let diameter = trackRect.height - inset * 2
            let stretch = min(0.35, speed * 0.05) + 0.18 * clamp(press.value, 0, 1)
            let baseWidth = diameter * (1 + stretch)
            let squash = 1 - min(0.12, speed * 0.014)
            let lens = 1 + 0.10 * glass
            let minX = trackRect.minX + inset + baseWidth / 2
            let maxX = trackRect.maxX - inset - baseWidth / 2
            let centerX = lerp(minX, maxX, p)
            let width = baseWidth * lens
            let height = diameter * squash * lens
            let knobRect = CGRect(x: centerX - width / 2, y: trackRect.midY - height / 2, width: width, height: height)
            knob.frame = knobRect
            knob.layout(cornerRadius: height / 2)
            knobShadow.frame = knobRect
            knobShadow.update(radius: height / 2)

            track.backgroundColor = resolved(Palette.trackOff)
            trackTint.backgroundColor = resolved(.controlAccentColor)
            trackTint.opacity = Float(clamp(p, 0, 1))

            knob.fill.backgroundColor = NSColor.white.cgColor
            knob.fill.opacity = Float(1 - 0.82 * glass)
            knob.highlight.colors = [
                NSColor(white: 1, alpha: 0.55 + 0.40 * glass + 0.10 * hover.value).cgColor,
                NSColor(white: 1, alpha: 0).cgColor,
                NSColor(white: 1, alpha: 0.30 * glass).cgColor,
            ]
            knob.rim.colors = [
                NSColor(white: 1, alpha: 0.35 + 0.60 * glass).cgColor,
                NSColor(white: 0, alpha: 0.10 + 0.10 * glass).cgColor,
            ]
            knobShadow.shadowOpacity = Float(0.30 * (1 - glass) + 0.16 * glass)
            knobShadow.shadowRadius = 1.5 + 3 * glass
        }
    }
}

// MARK: - Glass button

/// A capsule button made of glass. A press squashes it toward its base; the release
/// springs back past the rest shape, like jelly. While busy it can shrink into a ring
/// spinner, or roll its title. It ticks on success and shakes on failure, and it can
/// launch a symbol, such as a paper plane, when the work starts.
final class GlassButton: NSControl {
    enum Style {
        case primary
        case secondary
        case destructive
    }

    enum Size {
        case regular
        case small
    }

    enum BusyStyle {
        /// Shrinks into a circle with a spinning ring (Download Ring).
        case ring
        /// Keeps its shape and rolls the title to `busyTitle` (Paper Plane).
        case roll
    }

    let style: Style
    let buttonSize: Size
    let busyStyle: BusyStyle
    let symbolName: String?
    /// A symbol that flies out of the button when it turns busy.
    var flyingSymbolName: String?
    /// The title rolled in while busy, for `.roll`.
    var busyTitle: String?

    private(set) var title: String
    private(set) var isBusy = false

    /// Spins the symbol, for a refresh button.
    var isSpinningIcon = false {
        didSet {
            if isSpinningIcon != oldValue { animate() }
        }
    }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.45 }
    }

    private var press = Spring(0, stiffness: 900, damping: 48)
    private var hover = Spring(0, stiffness: 420, damping: 34)
    private var morph = Spring(0, stiffness: 240, damping: 23)
    private var success = Spring(0, stiffness: 260, damping: 24)
    private var failure = Spring(0, stiffness: 260, damping: 24)
    private var shake = Spring(0, stiffness: 1300, damping: 15, tolerance: 0.02)
    private var roll = Spring(0, stiffness: 320, damping: 28)
    private var iconPop = Spring(1, stiffness: 520, damping: 18)
    private var spin: CGFloat = 0
    private var flight: CGFloat = 1
    private var pendingTitle: String?
    private var restingTitle: String
    private var revertWork: DispatchWorkItem?
    private var pressedInside = false
    private var imageCache: [String: Any] = [:]

    private let body = CALayer()
    private let bodyShadow = OuterShadowLayer()
    private let glass = GlassLayer()
    private let contentClip = CALayer()
    private let iconLayer = CALayer()
    private let titleLayer = CATextLayer()
    private let nextTitleLayer = CATextLayer()
    private let spinner = CAShapeLayer()
    private let check = CAShapeLayer()
    private let cross = CAShapeLayer()
    private let planeLayer = CALayer()
    private lazy var driver = AnimationDriver { [weak self] dt in
        self?.advance(dt) ?? false
    }

    init(
        title: String,
        symbol: String? = nil,
        style: Style = .secondary,
        size: Size = .regular,
        busyStyle: BusyStyle = .ring
    ) {
        self.title = title
        self.restingTitle = title
        self.symbolName = symbol
        self.style = style
        self.buttonSize = size
        self.busyStyle = busyStyle
        super.init(frame: .zero)
        wantsLayer = true
        buildLayers()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    /// A round button that shows only a symbol.
    convenience init(icon symbol: String, toolTip: String, size: Size = .regular) {
        self.init(title: "", symbol: symbol, style: .secondary, size: size, busyStyle: .ring)
        self.toolTip = toolTip
        setAccessibilityLabel(toolTip)
    }

    required init?(coder: NSCoder) {
        nil
    }

    private var height: CGFloat { buttonSize == .regular ? 30 : 26 }
    private var labelFont: NSFont { .systemFont(ofSize: buttonSize == .regular ? 12.5 : 11.5, weight: .semibold) }
    private var iconPointSize: CGFloat { buttonSize == .regular ? 12 : 11 }
    private var iconSide: CGFloat { iconPointSize + 4 }

    override var intrinsicContentSize: NSSize {
        if title.isEmpty { return NSSize(width: height, height: height) }
        let textWidth = (title as NSString).size(withAttributes: [.font: labelFont]).width
        let iconWidth: CGFloat = symbolName == nil ? 0 : iconSide + 6
        return NSSize(width: ceil(textWidth + iconWidth + 30), height: height)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        render()
    }

    override func layout() {
        super.layout()
        render()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        imageCache.removeAll()
        render()
    }

    private func buildLayers() {
        guard let host = layer else { return }
        host.masksToBounds = false
        body.anchorPoint = CGPoint(x: 0.5, y: 0)
        host.addSublayer(body)
        body.addSublayer(bodyShadow)
        body.addSublayer(glass)
        body.addSublayer(contentClip)
        contentClip.masksToBounds = true
        contentClip.addSublayer(iconLayer)
        contentClip.addSublayer(titleLayer)
        contentClip.addSublayer(nextTitleLayer)
        body.addSublayer(spinner)
        body.addSublayer(check)
        body.addSublayer(cross)
        host.addSublayer(planeLayer)
        iconLayer.contentsGravity = .resizeAspect
        planeLayer.contentsGravity = .resizeAspect
        for text in [titleLayer, nextTitleLayer] {
            text.alignmentMode = .center
            text.truncationMode = .end
            text.font = labelFont
            text.fontSize = labelFont.pointSize
        }
        spinner.fillColor = nil
        spinner.lineWidth = 2
        spinner.lineCap = .round
        spinner.strokeStart = 0
        spinner.strokeEnd = 0.72
        check.fillColor = nil
        check.lineWidth = 2.2
        check.lineCap = .round
        check.lineJoin = .round
        cross.fillColor = nil
        cross.lineWidth = 2.2
        cross.lineCap = .round
    }

    // MARK: Public

    /// Changes the title shown at rest.
    func setTitle(_ newTitle: String) {
        restingTitle = newTitle
        guard !isBusy, pendingTitle == nil, revertWork == nil else { return }
        title = newTitle
        setAccessibilityLabel(newTitle)
        invalidateIntrinsicContentSize()
        render()
    }

    func setBusy(_ busy: Bool) {
        guard busy != isBusy else { return }
        isBusy = busy
        revertWork?.cancel()
        revertWork = nil
        if busy {
            success.target = 0
            failure.target = 0
            switch busyStyle {
            case .ring:
                morph.target = 1
            case .roll:
                if let busyTitle { rollTitle(to: busyTitle) }
            }
            if flyingSymbolName != nil, !Motion.isReduced { flight = 0 }
        } else {
            morph.target = 0
            if title != restingTitle || pendingTitle != nil { rollTitle(to: restingTitle) }
        }
        animate()
    }

    /// Ends the busy phase: a tick on success, a shake on failure, then back to rest.
    func finish(success ok: Bool, title message: String? = nil, holdFor hold: TimeInterval = 1.4) {
        isBusy = false
        revertWork?.cancel()
        if ok {
            success.target = 1
        } else {
            failure.target = 1
            if !Motion.isReduced { shake.velocity += 420 }
        }
        if let message, busyStyle == .roll { rollTitle(to: message) }
        animate()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.revertWork = nil
            self.success.target = 0
            self.failure.target = 0
            self.morph.target = 0
            if self.title != self.restingTitle || self.pendingTitle != nil {
                self.rollTitle(to: self.restingTitle)
            }
            self.animate()
        }
        revertWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: work)
    }

    /// Steps every animation by `seconds`. Used by tests and the render harness.
    func advanceAnimations(by seconds: CGFloat) {
        var elapsed: CGFloat = 0
        while elapsed < seconds {
            _ = advance(Motion.frame)
            elapsed += Motion.frame
        }
    }

    // MARK: Events

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hover.target = 1
        animate()
    }

    override func mouseExited(with event: NSEvent) {
        hover.target = 0
        animate()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, !isBusy else { return }
        pressedInside = true
        press.stiffness = 900
        press.damping = 48
        press.target = 1
        animate()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        guard inside != pressedInside else { return }
        pressedInside = inside
        press.target = inside ? 1 : 0
        animate()
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let shouldFire = inside && pressedInside && isEnabled && !isBusy
        pressedInside = false
        // Released: a soft spring overshoots past rest, so the capsule stretches like jelly.
        press.stiffness = 520
        press.damping = 10
        press.target = 0
        animate()
        if shouldFire { sendAction(action, to: target) }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, !isBusy else { return false }
        sendAction(action, to: target)
        return true
    }

    // MARK: Animation

    private func rollTitle(to newTitle: String) {
        if let pendingTitle { commitRoll(pendingTitle) }
        guard newTitle != title else { return }
        if Motion.isReduced {
            commitRoll(newTitle)
            return
        }
        pendingTitle = newTitle
        roll.value = 0
        roll.velocity = 0
        roll.target = 1
    }

    private func commitRoll(_ newTitle: String) {
        title = newTitle
        pendingTitle = nil
        roll.value = 0
        roll.target = 0
        roll.velocity = 0
        setAccessibilityLabel(newTitle)
    }

    private func animate() {
        if Motion.isReduced {
            press.snap()
            hover.snap()
            morph.snap()
            success.snap()
            failure.snap()
            shake.snap()
            iconPop.snap()
            if let pendingTitle { commitRoll(pendingTitle) }
            flight = 1
            render()
            if isSpinningIcon || (isBusy && busyStyle == .ring) { driver.start() }
            return
        }
        driver.start()
    }

    private func advance(_ dt: CGFloat) -> Bool {
        press.step(dt)
        hover.step(dt)
        morph.step(dt)
        success.step(dt)
        failure.step(dt)
        shake.step(dt)
        roll.step(dt)
        iconPop.step(dt)
        if flight < 1 {
            flight = min(1, flight + dt / 0.8)
            if flight >= 1 {
                iconPop.value = 0.25
                iconPop.target = 1
            }
        }
        let spinnerVisible = isBusy && busyStyle == .ring && morph.value > 0.3
        if spinnerVisible || isSpinningIcon { spin += dt * 2 * .pi * 1.1 }
        if let pendingTitle, roll.target == 1, roll.value > 0.995 { commitRoll(pendingTitle) }
        render()
        let settled = press.isSettled && hover.isSettled && morph.isSettled && success.isSettled
            && failure.isSettled && shake.isSettled && roll.isSettled && iconPop.isSettled
        return !settled || flight < 1 || spinnerVisible || isSpinningIcon || pendingTitle != nil
    }

    private func symbolContents(_ name: String, color: NSColor, pointSize: CGFloat, scale: CGFloat) -> Any? {
        // Component getters throw for gray colors such as NSColor.white, so key on sRGB.
        let rgb = color.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let key = String(
            format: "%@|%.3f|%.3f|%.3f|%.3f|%.1f|%.1f",
            name, rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent, pointSize, scale
        )
        if let cached = imageCache[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [rgb]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        let contents = image.layerContents(forContentsScale: scale)
        if imageCache.count > 32 { imageCache.removeAll() }
        imageCache[key] = contents
        return contents
    }

    private func titleWidth(_ text: String) -> CGFloat {
        text.isEmpty ? 0 : ceil((text as NSString).size(withAttributes: [.font: labelFont]).width)
    }

    private func render() {
        let rect = bounds
        guard rect.width > 2, rect.height > 2 else { return }
        withoutImplicitAnimation { renderLayers(in: rect) }
    }

    private func renderLayers(in rect: CGRect) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let h = rect.height
        let m = clamp(morph.value, 0, 1)
        let bodyWidth = lerp(rect.width, h, m)
        let p = press.value
        let ok = clamp(success.value, 0, 1)
        let bad = clamp(failure.value, 0, 1)
        let hv = clamp(hover.value, 0, 1)

        body.bounds = CGRect(x: 0, y: 0, width: bodyWidth, height: h)
        body.position = CGPoint(x: rect.midX + shake.value, y: rect.minY)
        body.transform = CATransform3DMakeScale(1 + 0.05 * p, 1 - 0.10 * p, 1)
        let radius = h / 2
        glass.frame = body.bounds
        glass.layout(cornerRadius: radius)
        bodyShadow.frame = body.bounds
        bodyShadow.update(radius: radius)
        contentClip.frame = body.bounds
        contentClip.cornerRadius = radius

        // Colors
        let green = resolvedColor(.systemGreen)
        let red = resolvedColor(.systemRed)
        var fill: NSColor
        var ink: NSColor
        switch style {
        case .primary:
            fill = resolvedColor(.controlAccentColor).mix(NSColor.white, 0.08 * hv)
            ink = .white
        case .secondary:
            fill = resolvedColor(Palette.glassFill).mix(resolvedColor(Palette.glassFillHover), hv)
            ink = resolvedColor(.labelColor)
        case .destructive:
            fill = resolvedColor(Palette.glassFill).mix(red.withAlphaComponent(0.16), hv)
            ink = red
        }
        fill = fill.mix(green, ok)
        fill = fill.mix(style == .primary ? red : red.withAlphaComponent(0.22), bad * 0.85)
        ink = ink.mix(.white, ok)
        if style == .primary { ink = ink.mix(.white, bad) }

        glass.fill.backgroundColor = fill.cgColor
        let highlightTop = style == .primary || ok > 0.5
            ? NSColor(white: 1, alpha: 0.30 + 0.08 * hv)
            : resolvedColor(Palette.glassHighlightTop)
        glass.highlight.colors = [
            highlightTop.cgColor,
            highlightTop.withAlphaComponent(0).cgColor,
            NSColor(white: 1, alpha: style == .primary ? 0.10 : 0.04).cgColor,
        ]
        let rimTop = (style == .primary ? NSColor(white: 1, alpha: 0.45) : resolvedColor(Palette.glassRimTop)).mix(red, bad)
        let rimBottom = (style == .primary ? NSColor(white: 0, alpha: 0.18) : resolvedColor(Palette.glassRimBottom))
            .mix(red.withAlphaComponent(0.6), bad)
        glass.rim.colors = [rimTop.cgColor, rimBottom.cgColor]
        let shadowStrength: CGFloat = isDarkAppearance ? 0.45 : (style == .primary ? 0.22 : 0.10)
        bodyShadow.shadowOpacity = Float(shadowStrength + 0.06 * hv)
        bodyShadow.shadowRadius = 1.5 + 1.5 * hv

        // Content: an optional symbol, then the title, centered in the button.
        let contentAlpha = 1 - clamp(m * 1.8, 0, 1)
        let bodyOriginX = (rect.width - bodyWidth) / 2
        let hasIcon = symbolName != nil
        let gap: CGFloat = (hasIcon && !title.isEmpty) ? 6 : 0
        func layoutStart(for text: String) -> CGFloat {
            let width = (hasIcon ? iconSide : 0) + (text.isEmpty ? 0 : gap + titleWidth(text))
            return (rect.width - width) / 2 - bodyOriginX
        }
        let rollValue = clamp(roll.value, 0, 1)
        let currentStart = layoutStart(for: title)
        let nextStart = pendingTitle.map(layoutStart(for:)) ?? currentStart
        let iconX = lerp(currentStart, nextStart, rollValue)

        if let symbolName {
            iconLayer.bounds = CGRect(x: 0, y: 0, width: iconSide, height: iconSide)
            iconLayer.position = CGPoint(x: iconX + iconSide / 2, y: h / 2)
            iconLayer.contentsScale = scale
            iconLayer.contents = symbolContents(symbolName, color: ink, pointSize: iconPointSize, scale: scale)
            let flying = flight < 1 && flyingSymbolName != nil
            iconLayer.opacity = Float(flying ? 0 : contentAlpha)
            var transform = CATransform3DMakeScale(iconPop.value, iconPop.value, 1)
            if isSpinningIcon || spin != 0 { transform = CATransform3DRotate(transform, -spin, 0, 0, 1) }
            iconLayer.transform = transform
        }

        let lineHeight = ceil(labelFont.ascender - labelFont.descender) + 1
        let titleY = (h - lineHeight) / 2 + 0.5
        let rise = lineHeight + 4
        for (layer, text, start, offset, alpha) in [
            (titleLayer, title, currentStart, rise * rollValue, 1 - rollValue),
            (nextTitleLayer, pendingTitle ?? "", nextStart, -rise * (1 - rollValue), pendingTitle == nil ? 0 : rollValue),
        ] {
            let width = titleWidth(text) + 2
            let x = start + (hasIcon ? iconSide + gap : 0)
            layer.string = text
            layer.foregroundColor = ink.cgColor
            layer.contentsScale = scale
            layer.bounds = CGRect(x: 0, y: 0, width: width, height: lineHeight)
            layer.position = CGPoint(x: x + width / 2 - 1, y: titleY + lineHeight / 2 + offset)
            layer.opacity = Float(contentAlpha * alpha)
        }

        // Ring spinner (busy) and tick (success), centered in the shrunken body.
        let center = CGPoint(x: bodyWidth / 2, y: h / 2)
        let ringRadius = max(4, h / 2 - 7)
        spinner.bounds = body.bounds
        spinner.position = center
        spinner.path = CGPath(
            ellipseIn: CGRect(x: center.x - ringRadius, y: center.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2),
            transform: nil
        )
        spinner.strokeColor = ink.cgColor
        spinner.transform = CATransform3DMakeRotation(-spin, 0, 0, 1)
        spinner.opacity = Float(clamp((m - 0.55) * 2.6, 0, 1) * (1 - ok) * (1 - bad))

        let s = h * 0.17
        let tick = CGMutablePath()
        tick.move(to: CGPoint(x: center.x - s, y: center.y + 0.05 * s))
        tick.addLine(to: CGPoint(x: center.x - 0.3 * s, y: center.y - 0.7 * s))
        tick.addLine(to: CGPoint(x: center.x + s, y: center.y + 0.75 * s))
        check.frame = body.bounds
        check.path = tick
        check.strokeColor = NSColor.white.cgColor
        check.strokeEnd = ok
        check.opacity = Float(ok > 0.02 && m > 0.5 ? 1 : 0)

        let c = h * 0.15
        let crossPath = CGMutablePath()
        crossPath.move(to: CGPoint(x: center.x - c, y: center.y + c))
        crossPath.addLine(to: CGPoint(x: center.x + c, y: center.y - c))
        crossPath.move(to: CGPoint(x: center.x + c, y: center.y + c))
        crossPath.addLine(to: CGPoint(x: center.x - c, y: center.y - c))
        cross.frame = body.bounds
        cross.path = crossPath
        cross.strokeColor = NSColor.white.cgColor
        cross.strokeEnd = bad
        cross.opacity = Float(bad > 0.02 && m > 0.5 ? 1 : 0)

        // The paper plane: off the button along a curve, tilting and fading.
        if let flyingSymbolName, flight < 1 {
            let t = flight
            let startPoint = CGPoint(x: rect.midX - bodyWidth / 2 + iconX + iconSide / 2 + shake.value, y: rect.minY + h / 2)
            let control = CGPoint(x: startPoint.x + 34, y: startPoint.y + 8)
            let endPoint = CGPoint(x: startPoint.x + 96, y: startPoint.y + 50)
            let u = 1 - t
            let point = CGPoint(
                x: u * u * startPoint.x + 2 * u * t * control.x + t * t * endPoint.x,
                y: u * u * startPoint.y + 2 * u * t * control.y + t * t * endPoint.y
            )
            let side = iconSide + 2
            planeLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            planeLayer.position = point
            planeLayer.contentsScale = scale
            planeLayer.contents = symbolContents(flyingSymbolName, color: ink, pointSize: iconPointSize + 1, scale: scale)
            let grow = 1 + 0.18 * sin(.pi * t) - 0.30 * t
            planeLayer.transform = CATransform3DRotate(CATransform3DMakeScale(grow, grow, 1), 0.22 * t, 0, 0, 1)
            planeLayer.opacity = Float(t < 0.6 ? 1 : max(0, 1 - (t - 0.6) / 0.4))
        } else {
            planeLayer.opacity = 0
        }
    }
}

// MARK: - Gooey selection

/// A glass blob behind the selected item. When the selection moves it slides over,
/// stretching along its path like a drop of liquid, and settles into the new shape.
final class GooeyIndicator: NSView {
    enum Axis {
        case horizontal
        case vertical
    }

    let axis: Axis
    /// nil makes a capsule, or a circle for a square target.
    var cornerRadius: CGFloat?
    var tintAlpha: CGFloat = 0.16

    private var centerX = Spring(0, stiffness: 260, damping: 22, tolerance: 0.05)
    private var centerY = Spring(0, stiffness: 260, damping: 22, tolerance: 0.05)
    private var width = Spring(0, stiffness: 260, damping: 26, tolerance: 0.05)
    private var height = Spring(0, stiffness: 260, damping: 26, tolerance: 0.05)
    private var fromTint: NSColor = .controlAccentColor
    private var toTint: NSColor = .controlAccentColor
    private var travelStart = CGPoint.zero
    private var isPlaced = false
    private let blob = GlassLayer()
    private let blobShadow = OuterShadowLayer()
    private lazy var driver = AnimationDriver { [weak self] dt in
        self?.advance(dt) ?? false
    }

    init(axis: Axis) {
        self.axis = axis
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(blobShadow)
        layer?.addSublayer(blob)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        render()
    }

    override func layout() {
        super.layout()
        render()
    }

    /// Moves the blob onto `rect`, given in this view's coordinates.
    func move(to rect: CGRect, tint: NSColor, animated: Bool) {
        let target = CGPoint(x: rect.midX, y: rect.midY)
        let sameTarget = isPlaced
            && abs(centerX.target - target.x) < 0.5 && abs(centerY.target - target.y) < 0.5
            && abs(width.target - rect.width) < 0.5 && abs(height.target - rect.height) < 0.5
        if sameTarget {
            toTint = tint
            render()
            return
        }
        fromTint = currentTint()
        toTint = tint
        travelStart = CGPoint(x: centerX.value, y: centerY.value)
        centerX.target = target.x
        centerY.target = target.y
        width.target = rect.width
        height.target = rect.height
        if !isPlaced || !animated || Motion.isReduced {
            centerX.snap()
            centerY.snap()
            width.snap()
            height.snap()
            fromTint = tint
            isPlaced = true
            render()
            return
        }
        driver.start()
    }

    /// Steps every animation by `seconds`. Used by tests and the render harness.
    func advanceAnimations(by seconds: CGFloat) {
        var elapsed: CGFloat = 0
        while elapsed < seconds {
            _ = advance(Motion.frame)
            elapsed += Motion.frame
        }
    }

    private func progress() -> CGFloat {
        let total = hypot(centerX.target - travelStart.x, centerY.target - travelStart.y)
        guard total > 0.5 else { return 1 }
        let remaining = hypot(centerX.target - centerX.value, centerY.target - centerY.value)
        return clamp(1 - remaining / total, 0, 1)
    }

    private func currentTint() -> NSColor {
        resolvedColor(fromTint).mix(resolvedColor(toTint), progress())
    }

    private func advance(_ dt: CGFloat) -> Bool {
        centerX.step(dt)
        centerY.step(dt)
        width.step(dt)
        height.step(dt)
        render()
        return !(centerX.isSettled && centerY.isSettled && width.isSettled && height.isSettled)
    }

    private func render() {
        withoutImplicitAnimation {
            guard isPlaced else {
                blob.opacity = 0
                blobShadow.opacity = 0
                return
            }
            blob.opacity = 1
            blobShadow.opacity = 1
            let speed = axis == .horizontal ? abs(centerX.velocity) : abs(centerY.velocity)
            let stretch = min(speed * 0.045, axis == .horizontal ? 30 : 16)
            var w = width.value
            var h = height.value
            if axis == .horizontal {
                w += stretch
                h -= min(stretch * 0.16, 5)
            } else {
                h += stretch
                w -= min(stretch * 0.10, 3)
            }
            let frame = CGRect(x: centerX.value - w / 2, y: centerY.value - h / 2, width: max(w, 1), height: max(h, 1))
            let radius = cornerRadius ?? min(frame.width, frame.height) / 2
            blob.frame = frame
            blob.layout(cornerRadius: radius)
            blobShadow.frame = frame
            blobShadow.update(radius: radius)

            let tint = currentTint()
            let travel = sin(.pi * progress())
            blob.fill.backgroundColor = tint.withAlphaComponent(tintAlpha * (1 - 0.6 * travel)).cgColor
            let top = resolvedColor(Palette.glassHighlightTop)
            blob.highlight.colors = [
                top.withAlphaComponent(top.alphaComponent * 0.8).cgColor,
                top.withAlphaComponent(0).cgColor,
                top.withAlphaComponent(0).cgColor,
            ]
            blob.rim.colors = [
                resolvedColor(Palette.glassRimTop).cgColor,
                tint.withAlphaComponent(0.35).cgColor,
            ]
            blobShadow.shadowOpacity = isDarkAppearance ? 0.35 : 0.10
            blobShadow.shadowRadius = 3
        }
    }
}
