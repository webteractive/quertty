import AppKit

/// Renders the Zetty app icon from the ACTIVE color scheme, so the Dock icon
/// follows theme changes while the app runs (the bundled .icns stays the
/// static Twilight rendition for Finder and the login switcher).
///
/// Same composition as the shipped icon: squircle plate on the scheme's
/// surface ramp, a glowing accent Z with a block cursor at its foot, and
/// faint rising z's — sessions sleep when you quit. Call on the main thread
/// (it reads QTheme and uses AppKit drawing).
enum AppIconRenderer {

    /// Draws the icon at Dock resolution using `QTheme.current` tokens.
    static func image(size canvas: CGFloat = 512) -> NSImage {
        let theme = QTheme.current
        let scale = canvas / 1024
        let image = NSImage(size: NSSize(width: canvas, height: canvas))
        image.lockFocus()

        // ── Squircle plate (surface ramp) ───────────────────────────
        let margin = 100 * scale
        let plate = NSRect(x: margin, y: margin,
                           width: canvas - 2 * margin, height: canvas - 2 * margin)
        let platePath = NSBezierPath(roundedRect: plate, xRadius: 184 * scale, yRadius: 184 * scale)
        NSGraphicsContext.current?.saveGraphicsState()
        platePath.setClip()
        NSGradient(colors: [theme.bg3Color, theme.bg0Color])?.draw(in: plate, angle: -90)
        NSGraphicsContext.current?.restoreGraphicsState()

        theme.borderColor.setStroke()
        let border = NSBezierPath(roundedRect: plate.insetBy(dx: 3 * scale, dy: 3 * scale),
                                  xRadius: 181 * scale, yRadius: 181 * scale)
        border.lineWidth = 6 * scale
        border.stroke()

        // ── Faint rising z's (sleeping sessions) ────────────────────
        for (index, glyphSize) in [(0, CGFloat(96)), (1, CGFloat(72)), (2, CGFloat(54))] {
            let z = NSAttributedString(string: "z", attributes: [
                .font: QTheme.monoFont(size: glyphSize * scale, weight: .bold),
                .foregroundColor: theme.fg3Color.withAlphaComponent(0.55 - CGFloat(index) * 0.15),
            ])
            z.draw(at: NSPoint(x: (640 + CGFloat(index) * 82) * scale,
                               y: (610 + CGFloat(index) * 92) * scale))
        }

        // ── The Z + cursor (accent, glowing) ────────────────────────
        NSGraphicsContext.current?.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = theme.accentColor.withAlphaComponent(0.85)
        glow.shadowBlurRadius = 52 * scale
        glow.shadowOffset = .zero
        glow.set()

        let zGlyph = NSAttributedString(string: "Z", attributes: [
            .font: QTheme.monoFont(size: 560 * scale, weight: .bold),
            .foregroundColor: theme.accentColor,
        ])
        let zSize = zGlyph.size()
        let zOrigin = NSPoint(x: (canvas - zSize.width) / 2 - 60 * scale,
                              y: (canvas - zSize.height) / 2 - 30 * scale)
        zGlyph.draw(at: zOrigin)

        let cursor = NSRect(x: zOrigin.x + zSize.width + 30 * scale,
                            y: zOrigin.y + 118 * scale,
                            width: 96 * scale, height: 180 * scale)
        theme.accentColor.setFill()
        NSBezierPath(roundedRect: cursor, xRadius: 14 * scale, yRadius: 14 * scale).fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        image.unlockFocus()
        return image
    }
}
