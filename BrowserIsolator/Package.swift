// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserIsolator",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .executableTarget(
            name: "BrowserIsolator",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/BrowserIsolator"
        )
    ]
)
