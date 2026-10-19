import AppKit

/// The Kapibara app icon: the Kapitsa mark (a K whose stem is four
/// fringes of a standing wave, whose arms are the diffracted beams)
/// on an ink rounded square. Brand colors from the Kapitsa press kit.
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

    /// Draws the mark centered in a `size` square, with a margin that
    /// keeps the beams inside the rounded corners.
    static func draw(in context: CGContext, size: CGFloat, palette: (ink: NSColor, green: NSColor, bright: NSColor, dim: NSColor)) {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)

        // Rounded-square ink background.
        let radius = size * 0.2237
        let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        palette.ink.setFill()
        background.fill()

        // The mark lives in a centered square, half the icon's size.
        let markSide = size * 0.5
        let markX = (size - markSide) / 2
        let markY = (size - markSide) / 2

        context.saveGState()
        // Clip to the mark square so the beams never cross the margin.
        context.addRect(CGRect(x: markX, y: markY, width: markSide, height: markSide))
        context.clip()

        let stemX = markX + markSide * 0.28
        let stemTop = markY + markSide * 0.85
        let stemBottom = markY + markSide * 0.15
        let stemMid = markY + markSide * 0.5

        // Four fringes form the K's stem: thin vertical lines, the
        // outer two dim, the inner two green.
        let fringeSpacing = markSide * 0.045
        let fringeWidth = markSide * 0.018
        for i in 0..<4 {
            let x = stemX + CGFloat(i) * fringeSpacing
            let color = i == 1 || i == 2 ? palette.green : palette.dim
            color.setFill()
            context.fill(CGRect(x: x, y: stemBottom, width: fringeWidth, height: stemTop - stemBottom))
        }

        // The incoming beam: a bright horizontal line from the left
        // edge to the stem, at mid height.
        palette.bright.setFill()
        let beamHeight = markSide * 0.05
        context.fill(CGRect(
            x: markX,
            y: stemMid - beamHeight / 2,
            width: stemX - markX + fringeWidth,
            height: beamHeight
        ))

        // The diffracted beams: the middle one straight on (bright),
        // the outer two as the K's arms (green).
        let armLength = markSide * 0.42
        let armWidth = markSide * 0.05
        let armEndX = stemX + fringeSpacing * 3 + armLength

        // Middle beam, straight through.
        palette.bright.setFill()
        context.fill(CGRect(
            x: stemX + fringeSpacing * 3 + fringeWidth,
            y: stemMid - beamHeight / 2,
            width: armEndX - (stemX + fringeSpacing * 3 + fringeWidth),
            height: beamHeight
        ))

        // Upper arm.
        drawArm(
            in: context,
            from: CGPoint(x: stemX + fringeSpacing * 1.5, y: stemMid),
            to: CGPoint(x: armEndX, y: stemTop),
            width: armWidth,
            color: palette.green
        )
        // Lower arm.
        drawArm(
            in: context,
            from: CGPoint(x: stemX + fringeSpacing * 1.5, y: stemMid),
            to: CGPoint(x: armEndX, y: stemBottom),
            width: armWidth,
            color: palette.green
        )

        context.restoreGState()
    }

    private static func drawArm(in context: CGContext, from start: CGPoint, to end: CGPoint, width: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }
}
