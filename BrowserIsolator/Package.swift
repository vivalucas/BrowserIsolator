// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserIsolator",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "BrowserIsolator",
            path: "Sources/BrowserIsolator"
        )
    ]
)