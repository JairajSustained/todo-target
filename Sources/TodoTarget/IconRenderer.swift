import AppKit

enum IconRenderer {
    /// Colours for levels 0 to 3: red, orange, yellow-green, green.
    /// The number inside the circle carries the meaning when colour alone is not enough.
    static let levelColors: [NSColor] = [
        NSColor(srgbRed: 0.90, green: 0.22, blue: 0.24, alpha: 1),
        NSColor(srgbRed: 0.98, green: 0.60, blue: 0.10, alpha: 1),
        NSColor(srgbRed: 0.66, green: 0.80, blue: 0.14, alpha: 1),
        NSColor(srgbRed: 0.16, green: 0.69, blue: 0.33, alpha: 1),
    ]

    static func color(level: Int) -> NSColor {
        levelColors[min(max(level, 0), 3)]
    }

    /// A non-template image, 18 pt tall. A filled circle with the done count inside,
    /// plus a small `↺` badge when `catchUp` is true.
    static func image(level: Int, doneCount: Int, catchUp: Bool) -> NSImage {
        let height: CGFloat = 18
        let width: CGFloat = catchUp ? 29 : 18
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let circle = NSRect(x: 0.5, y: 0.5, width: 17, height: 17)
            color(level: level).setFill()
            NSBezierPath(ovalIn: circle).fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            let ring = NSBezierPath(ovalIn: circle)
            ring.lineWidth = 1
            ring.stroke()

            // Dark text on the light colours, white on red and green.
            let textColor: NSColor = (level == 1 || level == 2) ? NSColor.black.withAlphaComponent(0.85) : .white
            drawCentered(String(doneCount), in: circle, font: .systemFont(ofSize: 11, weight: .bold), color: textColor)

            if catchUp {
                // A fixed dark pill with a white glyph reads on light and dark menu bars alike.
                let badge = NSRect(x: 19, y: 2, width: 10, height: 14)
                NSColor(white: 0.22, alpha: 1).setFill()
                NSBezierPath(roundedRect: badge, xRadius: 3, yRadius: 3).fill()
                drawCentered("↺", in: badge, font: .systemFont(ofSize: 11, weight: .bold), color: .white)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawCentered(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let s = NSAttributedString(string: text, attributes: attrs)
        let size = s.size()
        s.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }
}
