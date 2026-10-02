// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserIsolator",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .target(name: "IsolatorCore", resources: [.process("Resources")]),
        .executableTarget(name: "isolator", dependencies: ["IsolatorCore"], path: "Sources/IsolatorCLI"),
        .executableTarget(
            name: "BrowserIsolator",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                "IsolatorCore"
            ],
            path: "Sources/BrowserIsolator"
        ),
        .executableTarget(name: "AutomationHarness", dependencies: ["IsolatorCore"], path: "Tests/AutomationHarness"),
        .testTarget(
            name: "BrowserIsolatorTests",
            dependencies: ["BrowserIsolator", "IsolatorCore"],
            path: "Tests/BrowserIsolatorTests"
        )
    ]
)
