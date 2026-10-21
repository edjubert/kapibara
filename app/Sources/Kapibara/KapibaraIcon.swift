import AppKit

/// The Kapibara mascot: a capybara peeking out of the water, a glowing
/// Kapitsa-green head (eyes, ears and nostrils above the surface) on an
/// ink rounded square. Brand colors from the Kapitsa press kit.
///
/// The artwork is authored on a 512-unit canvas with a top-left origin
/// (same as docs/logo.svg) and mapped onto the target rect.
///
/// This file is also compiled standalone by `make icon`, so it must
/// not reference Bundle.module (see L10n.swift).
enum KapibaraIcon {
    /// Brand palette, from docs/assets/brand/README.md.
    enum Brand {
        static let ink = NSColor(srgbRed: 0x0B / 255, green: 0x0F / 255, blue: 0x0D / 255, alpha: 1)
        static let green = NSColor(srgbRed: 0x3F / 255, green: 0xB5 / 255, blue: 0x5A / 255, alpha: 1)
        static let bright = NSColor(srgbRed: 0x9D / 255, green: 0xF0 / 255, blue: 0xB0 / 255, alpha: 1)
        static let dim = NSColor(srgbRed: 0x1E / 255, green: 0x5A / 255, blue: 0x30 / 255, alpha: 1)
    }

    /// Bottom of the head gradient, a shade darker than Brand.green.
    private static let deepGreen = NSColor(srgbRed: 0x2E / 255, green: 0x8C / 255, blue: 0x46 / 255, alpha: 1)

    /// Y of the water surface on the 512 canvas.
    private static let waterline: CGFloat = 312

    /// Eye position and size on the 512 canvas (set high on the skull).
    private static let eyeY: CGFloat = 232
    private static let eyeRadius: CGFloat = 10

    /// Muzzle block on the 512 canvas, sitting on the waterline.
    private static let muzzleRect = CGRect(x: 192, y: 278, width: 128, height: 34)

    /// Ripple lines under the surface: y, x range, opacity.
    private static let ripples: [(y: CGFloat, from: CGFloat, to: CGFloat, alpha: CGFloat)] = [
        (312, 76, 436, 0.9),
        (346, 112, 400, 0.5),
        (376, 160, 352, 0.32),
        (404, 208, 304, 0.18),
    ]

    /// Bounds of the menu bar glyph on the 512 canvas.
    private static let glyphBounds = CGRect(x: 60, y: 128, width: 392, height: 230)

    /// Maps 512-unit, top-left-origin artwork coordinates into `rect`
    /// (bottom-left origin, as AppKit draws).
    private struct Canvas {
        let rect: CGRect
        let scale: CGFloat
        let yOffset: CGFloat

        init(in rect: CGRect, yOffset: CGFloat = 0) {
            self.rect = rect
            self.scale = rect.width / 512
            self.yOffset = yOffset
        }

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.maxY - y * scale + yOffset)
        }

        func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
            CGRect(
                x: rect.minX + x * scale,
                y: rect.maxY - (y + height) * scale + yOffset,
                width: width * scale,
                height: height * scale
            )
        }
    }

    /// Draws the app icon in a `size` square.
    static func draw(in context: CGContext, size: CGFloat, palette: (ink: NSColor, green: NSColor, bright: NSColor, dim: NSColor)) {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let canvas = Canvas(in: rect)
        let k = canvas.scale

        // Rounded-square ink background.
        let radius = size * 0.2237
        palette.ink.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        // Water: an elliptical green wash fading out below the surface.
        if let wash = NSGradient(
            starting: palette.green.withAlphaComponent(0.38),
            ending: palette.green.withAlphaComponent(0)
        ) {
            context.saveGState()
            context.clip(to: canvas.rect(x: 0, y: waterline, width: 512, height: 512 - waterline))
            let center = canvas.point(256, waterline)
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: 1, y: 0.55)
            wash.draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: 200 * k, options: [])
            context.restoreGState()
        }

        let head = headShape(canvas)

        // Neon glow: a shadowed solid fill under the gradient head.
        context.saveGState()
        context.setShadow(offset: .zero, blur: 14 * k, color: palette.green.withAlphaComponent(0.85).cgColor)
        palette.green.setFill()
        head.fill()
        context.restoreGState()

        context.saveGState()
        head.addClip()
        if let gradient = NSGradient(starting: palette.green, ending: deepGreen) {
            gradient.draw(in: canvas.rect(x: 120, y: 144, width: 272, height: waterline - 144), angle: -90)
        }
        context.restoreGState()

        // Inner ears.
        palette.dim.setFill()
        NSBezierPath(ovalIn: canvas.rect(x: 153, y: 157, width: 22, height: 26)).fill()
        NSBezierPath(ovalIn: canvas.rect(x: 337, y: 157, width: 22, height: 26)).fill()

        // Eyes, with a bright glint.
        for x: CGFloat in [194, 318] {
            palette.ink.setFill()
            NSBezierPath(ovalIn: circle(canvas, x, eyeY, eyeRadius)).fill()
            palette.bright.setFill()
            NSBezierPath(ovalIn: circle(canvas, x + 2.5, eyeY - 2.5, 3.5)).fill()
        }

        // Wide, flat muzzle with its two nostrils.
        palette.dim.setFill()
        NSBezierPath(
            roundedRect: canvas.rect(x: muzzleRect.minX, y: muzzleRect.minY, width: muzzleRect.width, height: muzzleRect.height),
            xRadius: 12 * k,
            yRadius: 12 * k
        ).fill()
        palette.ink.setFill()
        NSBezierPath(ovalIn: circle(canvas, 232, 292, 4.5)).fill()
        NSBezierPath(ovalIn: circle(canvas, 280, 292, 4.5)).fill()

        // Surface line and ripples.
        for ripple in ripples {
            let line = NSBezierPath()
            line.move(to: canvas.point(ripple.from, ripple.y))
            line.line(to: canvas.point(ripple.to, ripple.y))
            line.lineWidth = 8 * k
            line.lineCapStyle = .round
            palette.green.withAlphaComponent(ripple.alpha).setStroke()
            line.stroke()
        }
    }

    /// Menu bar glyph: the head with the eyes cut out and two lines of
    /// water. With no color, macOS tints the template for its appearance.
    /// With a color, draw it into the image and disable template tinting:
    /// MenuBarExtra ignores foreground styles on template images.
    static func menuBarImage(
        height: CGFloat = 15,
        color: NSColor? = nil,
        submerge: CGFloat = 0,
        rippleScale: CGFloat = 1
    ) -> NSImage {
        let bounds = glyphBounds
        let size = NSSize(width: height * bounds.width / bounds.height, height: height)
        let ink = color ?? .black
        let image = NSImage(size: size, flipped: false) { rect in
            // Frame the glyph's bounds exactly onto the image rect.
            let scale = rect.width / bounds.width
            let glyphRect = CGRect(
                x: rect.minX - bounds.minX * scale,
                y: rect.minY - (512 - bounds.maxY) * scale,
                width: 512 * scale,
                height: 512 * scale
            )
            // Move the capybara independently of the water and clip it
            // at the surface, while keeping its eyes above water.
            let waterCanvas = Canvas(in: glyphRect)
            let canvas = Canvas(in: glyphRect, yOffset: -submerge * 50 * scale)
            let context = NSGraphicsContext.current
            context?.saveGraphicsState()
            NSBezierPath(rect: waterCanvas.rect(x: 0, y: 0, width: 512, height: waterline)).addClip()

            ink.setFill()
            headShape(canvas).fill()

            // Cut the eyes and the muzzle out of the head, then put the
            // muzzle back at partial opacity: the darker tone it has in
            // the app icon. (A single even-odd path would also punch
            // holes where the ears overlap the skull.)
            let muzzle = NSBezierPath(
                roundedRect: canvas.rect(x: muzzleRect.minX, y: muzzleRect.minY, width: muzzleRect.width, height: muzzleRect.height),
                xRadius: 12 * canvas.scale,
                yRadius: 12 * canvas.scale
            )
            context?.compositingOperation = .clear
            NSBezierPath(ovalIn: circle(canvas, 194, eyeY, eyeRadius)).fill()
            NSBezierPath(ovalIn: circle(canvas, 318, eyeY, eyeRadius)).fill()
            muzzle.fill()
            context?.compositingOperation = .sourceOver
            ink.withAlphaComponent(0.4).setFill()
            muzzle.fill()
            ink.setFill()
            context?.restoreGraphicsState()

            // Thicker than the app icon's lines: they must survive at
            // menu bar size.
            ink.setStroke()
            for (y, from, to) in [(waterline, 76, 436), (350, 112, 400)] as [(CGFloat, CGFloat, CGFloat)] {
                let line = NSBezierPath()
                let start = 256 + (from - 256) * rippleScale
                let end = 256 + (to - 256) * rippleScale
                line.move(to: waterCanvas.point(start, y))
                line.line(to: waterCanvas.point(end, y))
                line.lineWidth = 16 * canvas.scale
                line.lineCapStyle = .round
                line.stroke()
            }
            return true
        }
        image.isTemplate = color == nil
        return image
    }

    private static func circle(_ canvas: Canvas, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGRect {
        canvas.rect(x: x - r, y: y - r, width: r * 2, height: r * 2)
    }

    /// The boxy skull with rounded ears flowing smoothly into its contour.
    private static func headShape(_ canvas: Canvas) -> NSBezierPath {
        let p = canvas.point
        let path = NSBezierPath()

        path.move(to: p(128, waterline))
        path.line(to: p(128, 236))
        path.curve(to: p(140, 194), controlPoint1: p(128, 215), controlPoint2: p(143, 205))
        path.curve(to: p(135, 166), controlPoint1: p(137, 182), controlPoint2: p(134, 176))
        path.curve(to: p(147, 143), controlPoint1: p(135, 155), controlPoint2: p(139, 143))
        path.curve(to: p(168, 143), controlPoint1: p(155, 143), controlPoint2: p(162, 137))
        path.curve(to: p(184, 166), controlPoint1: p(174, 151), controlPoint2: p(183, 154))
        path.curve(to: p(192, 172), controlPoint1: p(185, 170), controlPoint2: p(190, 172))
        path.line(to: p(320, 172))
        path.curve(to: p(328, 166), controlPoint1: p(322, 172), controlPoint2: p(327, 170))
        path.curve(to: p(344, 143), controlPoint1: p(329, 154), controlPoint2: p(338, 151))
        path.curve(to: p(365, 143), controlPoint1: p(350, 137), controlPoint2: p(357, 143))
        path.curve(to: p(377, 166), controlPoint1: p(373, 143), controlPoint2: p(377, 155))
        path.curve(to: p(372, 194), controlPoint1: p(378, 176), controlPoint2: p(375, 182))
        path.curve(to: p(384, 236), controlPoint1: p(369, 205), controlPoint2: p(384, 215))
        path.line(to: p(384, waterline))
        path.close()

        return path
    }
}
