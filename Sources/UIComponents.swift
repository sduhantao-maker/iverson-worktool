import Cocoa

/// A plain view filled with a color that follows Light and Dark Mode.
final class FillView: NSView {
    var fillColor: NSColor {
        didSet { needsDisplay = true }
    }

    init(color: NSColor) {
        fillColor = color
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = resolved(fillColor)
    }
}

final class ToolbarBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(colors: [Palette.toolbarTop, Palette.toolbarBottom])
        gradient?.draw(in: bounds, angle: 270)
        Palette.toolbarStroke.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 0.5))
        path.line(to: NSPoint(x: bounds.maxX, y: 0.5))
        path.stroke()
    }
}

final class CardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = 9
        layer.borderWidth = 1
        layer.backgroundColor = resolved(Palette.cardFill)
        layer.borderColor = resolved(Palette.cardStroke)
    }
}

final class BadgeView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var fill: NSColor = .clear

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        configure(text: " ", fill: .clear, textColor: .secondaryLabelColor)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(text: String, fill: NSColor, textColor: NSColor) {
        label.stringValue = text
        label.textColor = textColor
        self.fill = fill
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = 12
        layer?.backgroundColor = resolved(fill)
    }
}

final class SymbolTile: NSView {
    private let imageView = NSImageView()
    private let fill: NSColor

    init(symbol: String, fill: NSColor, tint: NSColor) {
        self.fill = fill
        super.init(frame: .zero)
        wantsLayer = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentTintColor = tint
        imageView.imageScaling = .scaleProportionallyDown
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = 7
        layer?.backgroundColor = resolved(fill)
    }
}

/// One choice in the KeepGoing toolbar: a symbol over a label. Click it to choose it.
/// The glass bubble behind the chosen symbol is a `GooeyIndicator` owned by the toolbar.
final class ToolbarItem: NSControl {
    static let iconSide: CGFloat = 40

    let accent: NSColor
    var onSelect: (() -> Void)?

    var isSelectedItem = false {
        didSet {
            applyColors()
            setAccessibilityValue(isSelectedItem ? 1 : 0)
        }
    }

    override var isEnabled: Bool {
        didSet { applyColors() }
    }

    private let image = NSImageView()
    private let label: NSTextField
    private var isHovering = false

    init(title: String, symbol: String, accent: NSColor) {
        self.accent = accent
        label = makeLabel(title, font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        image.translatesAutoresizingMaskIntoConstraints = false
        image.imageScaling = .scaleProportionallyDown
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        label.alignment = .center

        addSubview(image)
        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 82),
            heightAnchor.constraint(equalToConstant: 76),

            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.centerYAnchor.constraint(equalTo: topAnchor, constant: Self.iconSide / 2),
            image.widthAnchor.constraint(equalToConstant: 24),
            image.heightAnchor.constraint(equalToConstant: 24),

            label.topAnchor.constraint(equalTo: topAnchor, constant: Self.iconSide + 8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
        applyColors()
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// The circle the selection bubble covers, in `view`'s coordinates.
    func iconFrame(in view: NSView) -> CGRect {
        let side = Self.iconSide
        let local = CGRect(x: (bounds.width - side) / 2, y: isFlipped ? 0 : bounds.height - side, width: side, height: side)
        return convert(local, to: view)
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
        isHovering = true
        applyColors()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyColors()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onSelect?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onSelect?()
        return true
    }

    private func applyColors() {
        let hot = isHovering && isEnabled
        image.contentTintColor = isSelectedItem ? accent : (hot ? .labelColor : .secondaryLabelColor)
        label.textColor = isSelectedItem ? accent : (hot ? .labelColor : .secondaryLabelColor)
        label.font = .systemFont(ofSize: 11, weight: isSelectedItem ? .semibold : .medium)
        alphaValue = isEnabled ? 1 : 0.55
    }
}

final class TriangleView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Palette.contentBackground.setFill()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.midX, y: bounds.maxY))
        path.line(to: NSPoint(x: bounds.maxX, y: bounds.minY))
        path.line(to: NSPoint(x: bounds.minX, y: bounds.minY))
        path.close()
        path.fill()
    }
}

func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = font
    label.textColor = color
    return label
}
