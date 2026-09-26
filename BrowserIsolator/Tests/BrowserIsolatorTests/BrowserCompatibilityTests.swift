import XCTest
@testable import BrowserIsolator

final class BrowserCompatibilityTests: XCTestCase {
    func testNewEnvironmentsEnableOnlyCollector() {
        let profiles = AppConfig.default.profiles + [.newEnvironment(folder: "p7")]
        XCTAssertEqual(AppConfig.default.profiles.map(\.folder), ["p1", "p2", "p3"])
        for profile in profiles {
            XCTAssertTrue(profile.collectorDebugEnabled)
            XCTAssertFalse(profile.fingerprintEnabled)
            XCTAssertEqual(preferredDebugPort(for: profile), 41000 + profile.instanceNumber)
        }
    }

    func testLegacyAndSavedModesRemainUnchanged() throws {
        for fingerprint in [false, true] {
            for collector in [nil, false, true] as [Bool?] {
                var json: [String: Any] = ["folder": "p7", "fingerprintEnabled": fingerprint]
                if let collector { json["collectorDebugEnabled"] = collector }
                let data = try JSONSerialization.data(withJSONObject: json)
                let profile = try JSONDecoder().decode(Profile.self, from: data)
                XCTAssertEqual(profile.collectorDebugEnabled, collector ?? false)
                XCTAssertEqual(profile.fingerprintEnabled, fingerprint)
                let reloaded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
                XCTAssertEqual(reloaded.collectorDebugEnabled, collector ?? false)
                XCTAssertEqual(reloaded.fingerprintEnabled, fingerprint)
            }
        }
    }

    func testNewEnvironmentCollectorCanBeDisabledAndPersisted() throws {
        var profile = Profile.newEnvironment(folder: "p7")
        profile.collectorDebugEnabled = false
        let reloaded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        XCTAssertFalse(reloaded.collectorDebugEnabled)
        XCTAssertNil(preferredDebugPort(for: reloaded))
    }

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
