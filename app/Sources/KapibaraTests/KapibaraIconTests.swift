import XCTest
import AppKit
@testable import Kapibara

/// The menu bar glyph must stay a template image (so macOS tints it) and
/// must actually draw something.
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
}
