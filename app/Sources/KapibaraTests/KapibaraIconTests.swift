import XCTest
import AppKit
@testable import Kapibara

/// The neutral glyph follows macOS appearance; state-colored glyphs
/// preserve their own colors instead of letting macOS tint them.
final class KapibaraIconTests: XCTestCase {
    func testMenuBarImageIsTemplateWithExpectedHeight() {
        let image = KapibaraIcon.menuBarImage(height: 15)
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size.height, 15)
        XCTAssertGreaterThan(image.size.width, image.size.height)
    }

    func testMenuBarImageIsNotBlank() throws {
        let image = KapibaraIcon.menuBarImage(height: 30)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var opaque = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                opaque += 1
            }
        }
        XCTAssertGreaterThan(opaque, rep.pixelsWide * rep.pixelsHigh / 4)
    }

    func testColoredMenuBarImagesPreserveStateColors() throws {
        for height: CGFloat in [15, 30] {
            for color in [NSColor.systemGreen, .systemYellow, .systemGray] {
                let image = KapibaraIcon.menuBarImage(height: height, color: color)
                XCTAssertFalse(image.isTemplate)
                XCTAssertEqual(image.size.height, height)

                let tiff = try XCTUnwrap(image.tiffRepresentation)
                let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
                let expected = try XCTUnwrap(color.usingColorSpace(rep.colorSpace))
                var opaque = 0
                var maxChannelError: CGFloat = 0
                for x in 0..<rep.pixelsWide {
                    for y in 0..<rep.pixelsHigh {
                        // colorAt tags these as calibrated colors, but the
                        // component values belong to the bitmap's space.
                        let pixel = try XCTUnwrap(rep.colorAt(x: x, y: y))
                        guard pixel.alphaComponent > 0.99 else { continue }
                        opaque += 1
                        maxChannelError = max(
                            maxChannelError,
                            abs(pixel.redComponent - expected.redComponent),
                            abs(pixel.greenComponent - expected.greenComponent),
                            abs(pixel.blueComponent - expected.blueComponent)
                        )
                    }
                }
                XCTAssertGreaterThan(opaque, rep.pixelsWide * rep.pixelsHigh / 4)
                XCTAssertLessThan(maxChannelError, 0.02, "\(color), height \(height)")
            }
        }
    }
}
