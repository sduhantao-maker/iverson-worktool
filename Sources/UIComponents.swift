import Cocoa

struct CommandResult {
    let code: Int32
    let stdout: String
    let stderr: String
}

final class ToolbarBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
        bounds.fill()
        let gradient = NSGradient(colors: [
            NSColor(calibratedWhite: 0.94, alpha: 1),
            NSColor(calibratedWhite: 0.86, alpha: 1),
        ])
        gradient?.draw(in: bounds, angle: 270)
        NSColor(calibratedWhite: 0.77, alpha: 1).setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 0.5))
        path.line(to: NSPoint(x: bounds.maxX, y: 0.5))
        path.stroke()
    }
}

final class ToggleSwitch: NSControl {
    var isBusy: Bool = false

    var isOn: Bool = false {
        didSet { needsDisplay = true }
    }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 56, height: 30)
    }

    override func mouseDown(with event: NSEvent) {
        if !isEnabled || isBusy { return }
        isOn.toggle()
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        let trackRect = bounds.insetBy(dx: 1, dy: 2)
        let track = NSBezierPath(roundedRect: trackRect, xRadius: trackRect.height / 2, yRadius: trackRect.height / 2)
        let trackColor: NSColor
        if !isEnabled {
            trackColor = NSColor(calibratedWhite: isOn ? 0.72 : 0.84, alpha: 1)
        } else if isOn {
            trackColor = NSColor.systemBlue
        } else {
            trackColor = NSColor(calibratedWhite: 0.84, alpha: 1)
        }
        trackColor.setFill()
        track.fill()

        let knobSize: CGFloat = 24
        let knobX = isOn ? bounds.maxX - knobSize - 4 : bounds.minX + 4
        let knobRect = NSRect(x: knobX, y: bounds.midY - knobSize / 2, width: knobSize, height: knobSize)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
    }
}

final class CardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.985, alpha: 1).cgColor
        layer?.cornerRadius = 9
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 0.86, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class BadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.alignment = .center
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
        layer?.backgroundColor = fill.cgColor
    }
}

final class SymbolTile: NSView {
    private let imageView = NSImageView()

    init(symbol: String, fill: NSColor, tint: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = fill.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentTintColor = tint
        imageView.imageScaling = .scaleProportionallyDown
        if #available(macOS 11.0, *) {
            imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
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
}

final class ToolbarItem: NSView {
    private let iconContainer = NSView()
    private let image = NSImageView()
    private let label: NSTextField

    init(title: String, symbol: String) {
        label = makeLabel(title, font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.wantsLayer = true
        iconContainer.layer?.cornerRadius = 20

        image.translatesAutoresizingMaskIntoConstraints = false
        image.imageScaling = .scaleProportionallyDown
        if #available(macOS 11.0, *) {
            image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }

        label.alignment = .center

        addSubview(iconContainer)
        iconContainer.addSubview(image)
        addSubview(label)
        configure(active: false, accent: .systemBlue)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 82),
            heightAnchor.constraint(equalToConstant: 76),

            iconContainer.topAnchor.constraint(equalTo: topAnchor),
            iconContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 40),
            iconContainer.heightAnchor.constraint(equalToConstant: 40),

            image.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 24),
            image.heightAnchor.constraint(equalToConstant: 24),

            label.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(active: Bool, accent: NSColor, solid: Bool = false) {
        if active {
            iconContainer.layer?.backgroundColor = (solid ? accent : accent.withAlphaComponent(0.18)).cgColor
            image.contentTintColor = solid ? .white : accent
            label.textColor = accent
            label.font = .systemFont(ofSize: 11, weight: .semibold)
        } else {
            iconContainer.layer?.backgroundColor = NSColor.clear.cgColor
            image.contentTintColor = .secondaryLabelColor
            label.textColor = .secondaryLabelColor
            label.font = .systemFont(ofSize: 11, weight: .medium)
        }
    }
}

final class TriangleView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
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

func runCommand(_ path: String, _ args: [String]) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    do {
        try process.run()
    } catch {
        return CommandResult(code: 127, stdout: "", stderr: error.localizedDescription)
    }
    process.waitUntilExit()
    let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return CommandResult(code: process.terminationStatus, stdout: stdout, stderr: stderr)
}

func cleanMessage(_ primary: String, fallback: String) -> String {
    let message = primary.trimmingCharacters(in: .whitespacesAndNewlines)
    if !message.isEmpty { return message }
    return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
}

func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func appleScriptLiteral(_ value: String) -> String {
    "\"" + value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        + "\""
}
