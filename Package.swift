// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Notcher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Notcher",
            path: "Sources/Notcher",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
