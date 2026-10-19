// One-off generator for Resources/AppIcon.icns.
// Draws the Kapitsa mark (the K of diffracted beams) on an ink
// rounded background. Run via `make icon`.
//
// swiftc scripts/icon/main.swift Sources/Kapibara/KapibaraIcon.swift -o .build/icongen
// .build/icongen Resources/AppIcon.icns

import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    if let context = NSGraphicsContext.current?.cgContext {
        KapibaraIcon.draw(
            in: context,
            size: size,
            palette: (
                ink: KapibaraIcon.Brand.ink,
                green: KapibaraIcon.Brand.green,
                bright: KapibaraIcon.Brand.bright,
                dim: KapibaraIcon.Brand.dim
            )
        )
    }
    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
        fatalError("PNG encoding failed for \(url.path)")
    }
    try png.write(to: url)
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.icns")
let work = FileManager.default.temporaryDirectory
    .appendingPathComponent("Kapibara.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: work)
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

let entries: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for entry in entries {
    try writePNG(drawIcon(size: entry.size), to: work.appendingPathComponent(entry.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", work.path, "-o", output.path]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 {
    fatalError("iconutil failed")
}
print("Wrote \(output.path)")
