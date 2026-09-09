import XCTest
@testable import BrowserIsolator

final class BrowserCompatibilityTests: XCTestCase {
    func testCollectorAndVariationPortRulesMatchWindows() {
        let base = Profile(folder: "p7", displayName: "")
        XCTAssertNil(preferredDebugPort(for: base))

        let variation = Profile(folder: "p7", displayName: "", fingerprintEnabled: true)
        XCTAssertEqual(preferredDebugPort(for: variation), 40007)

        let collector = Profile(folder: "p7", displayName: "", collectorDebugEnabled: true)
        XCTAssertEqual(preferredDebugPort(for: collector), 41007)

        let combined = Profile(folder: "p7", displayName: "", fingerprintEnabled: true, collectorDebugEnabled: true)
        XCTAssertEqual(preferredDebugPort(for: combined), 41007)
    }

    func testChromeArgumentsMatchWindowsCollectorContract() {
        let arguments = browserLaunchArguments(
            profileDir: "/tmp/Profiles/p2",
            debugPort: 41002,
            additionalArguments: ["https://example.com"]
        )
        XCTAssertEqual(arguments, [
            "--user-data-dir=/tmp/Profiles/p2",
            "--no-first-run",
            "--remote-debugging-address=127.0.0.1",
            "--remote-debugging-port=41002",
            "https://example.com"
        ])
        XCTAssertFalse(arguments.contains("--test-type"))
    }
}
