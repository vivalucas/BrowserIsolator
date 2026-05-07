// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserIsolator",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BrowserIsolator",
            path: "Sources/BrowserIsolator"
        )
    ]
)
