// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kapibara",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Kapibara",
            path: "Sources/Kapibara",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KapibaraTests",
            dependencies: ["Kapibara"],
            path: "Sources/KapibaraTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
