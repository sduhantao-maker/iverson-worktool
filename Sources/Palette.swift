import Cocoa

/// Colors that follow Light and Dark Mode.
///
/// A `CGColor` is fixed once it is made, so layer-backed views resolve these in their own
/// appearance (`NSView.resolved(_:)`) every time they update their layers.
enum Palette {
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    static let windowBackground = dynamic(light: NSColor(white: 0.98, alpha: 1), dark: NSColor(white: 0.105, alpha: 1))
    static let contentBackground = dynamic(light: .white, dark: NSColor(white: 0.125, alpha: 1))
    static let cardFill = dynamic(light: NSColor(white: 0.985, alpha: 1), dark: NSColor(white: 0.165, alpha: 1))
    static let cardStroke = dynamic(light: NSColor(white: 0.86, alpha: 1), dark: NSColor(white: 1, alpha: 0.08))
    static let toolbarTop = dynamic(light: NSColor(white: 0.945, alpha: 1), dark: NSColor(white: 0.205, alpha: 1))
    static let toolbarBottom = dynamic(light: NSColor(white: 0.865, alpha: 1), dark: NSColor(white: 0.150, alpha: 1))
    static let toolbarStroke = dynamic(light: NSColor(white: 0.77, alpha: 1), dark: NSColor(white: 0, alpha: 0.65))
    static let trackOff = dynamic(light: NSColor(white: 0.80, alpha: 1), dark: NSColor(white: 0.32, alpha: 1))

    // Glass
    static let glassFill = dynamic(light: NSColor(white: 0, alpha: 0.05), dark: NSColor(white: 1, alpha: 0.075))
    static let glassFillHover = dynamic(light: NSColor(white: 0, alpha: 0.085), dark: NSColor(white: 1, alpha: 0.125))
    static let glassHighlightTop = dynamic(light: NSColor(white: 1, alpha: 0.85), dark: NSColor(white: 1, alpha: 0.16))
    static let glassRimTop = dynamic(light: NSColor(white: 1, alpha: 1), dark: NSColor(white: 1, alpha: 0.30))
    static let glassRimBottom = dynamic(light: NSColor(white: 0, alpha: 0.14), dark: NSColor(white: 1, alpha: 0.05))
    static let glassShadow = dynamic(light: NSColor(white: 0, alpha: 1), dark: NSColor(white: 0, alpha: 1))
}

extension NSView {
    /// A dynamic color as a `CGColor` for this view's current appearance.
    func resolved(_ color: NSColor) -> CGColor {
        var cgColor = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            cgColor = color.cgColor
        }
        return cgColor
    }

    /// A dynamic color as a fixed sRGB color for this view's current appearance.
    func resolvedColor(_ color: NSColor) -> NSColor {
        var resolved = color
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

extension NSColor {
    /// A straight mix in sRGB. Resolve dynamic colors first.
    func mix(_ other: NSColor, _ amount: CGFloat) -> NSColor {
        let t = min(max(amount, 0), 1)
        if t == 0 { return self }
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else {
            return t < 0.5 ? self : other
        }
        return NSColor(
            srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
            alpha: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t
        )
    }
}
