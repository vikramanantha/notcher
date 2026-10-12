// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacNotcher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacNotcher",
            path: "Sources/MacNotcher",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
