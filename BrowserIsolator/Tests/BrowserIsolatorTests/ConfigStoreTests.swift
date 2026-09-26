import XCTest
@testable import BrowserIsolator

final class ConfigStoreTests: XCTestCase {
    private var root: URL!
    private var configURL: URL { root.appendingPathComponent("config.json") }
    private var profilesURL: URL { root.appendingPathComponent("Profiles") }
    private var store: ConfigStore { ConfigStore(configURL: configURL, profilesURL: profilesURL) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testFirstLaunchModesSurviveRestartWithoutUserAction() throws {
        let first = store.load()
        XCTAssertNil(first.saveError)
        XCTAssertNil(first.alert)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        for profile in first.config.profiles {
            try FileManager.default.createDirectory(at: profilesURL.appendingPathComponent(profile.folder), withIntermediateDirectories: true)
        }
        let second = store.load()
        XCTAssertNil(second.alert)
        XCTAssertEqual(second.config.profiles.count, 3)
        XCTAssertTrue(second.config.profiles.allSatisfy { $0.collectorDebugEnabled && !$0.fingerprintEnabled })
    }

    func testExistingConfigIsNotRewrittenOnLoad() throws {
        let data = Data(#"{"profiles":[{"folder":"p7","fingerprintEnabled":true}]}"#.utf8)
        try data.write(to: configURL)
        let result = store.load()
        XCTAssertFalse(try XCTUnwrap(result.config.profiles.first).collectorDebugEnabled)
        XCTAssertTrue(result.config.profiles[0].fingerprintEnabled)
        XCTAssertEqual(try Data(contentsOf: configURL), data)
    }

    func testDiskRecoveryKeepsCollectorOff() throws {
        try FileManager.default.createDirectory(at: profilesURL.appendingPathComponent("p7"), withIntermediateDirectories: true)
        let result = store.load()
        guard case .disk? = result.alert?.recovery else { return XCTFail("Expected disk recovery") }
        XCTAssertNil(result.saveError)
        XCTAssertFalse(try XCTUnwrap(result.config.profiles.first).collectorDebugEnabled)
        XCTAssertFalse(store.load().config.profiles[0].collectorDebugEnabled)
    }

    func testBackupRecoveryPreservesExplicitModes() throws {
        let config = AppConfig(profiles: [Profile(folder: "p7", displayName: "", fingerprintEnabled: true, collectorDebugEnabled: false)])
        try JSONEncoder().encode(config).write(to: configURL.appendingPathExtension("bak"))
        try Data("broken".utf8).write(to: configURL)
        let result = store.load()
        guard case .backup? = result.alert?.recovery else { return XCTFail("Expected backup recovery") }
        XCTAssertNil(result.saveError)
        XCTAssertNotNil(result.alert?.backupPath)
        let reloaded = store.load().config.profiles[0]
        XCTAssertFalse(reloaded.collectorDebugEnabled)
        XCTAssertTrue(reloaded.fingerprintEnabled)
    }

    func testDefaultsAfterCorruptionArePersisted() throws {
        try Data("broken".utf8).write(to: configURL)
        let result = store.load()
        guard case .defaults? = result.alert?.recovery else { return XCTFail("Expected defaults recovery") }
        XCTAssertNil(result.saveError)
        XCTAssertTrue(store.load().config.profiles.allSatisfy(\.collectorDebugEnabled))
    }

    func testInitialSaveFailureIsReported() throws {
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blocked)
        let result = ConfigStore(configURL: blocked.appendingPathComponent("config.json"), profilesURL: profilesURL).load()
        XCTAssertNotNil(result.saveError)
        XCTAssertEqual(result.config.profiles.count, 3)
        XCTAssertTrue(result.config.profiles.allSatisfy(\.collectorDebugEnabled))
    }

    func testRecoverySaveFailureIsIncludedInRecoveryAlert() throws {
        try FileManager.default.createDirectory(at: profilesURL.appendingPathComponent("p7"), withIntermediateDirectories: true)
        // Block the temporary save path without relying on permission bits or user data.
        try FileManager.default.createDirectory(at: configURL.appendingPathExtension("tmp"), withIntermediateDirectories: true)
        let result = store.load()
        guard case .disk? = result.alert?.recovery else { return XCTFail("Expected disk recovery") }
        XCTAssertNotNil(result.saveError)
        XCTAssertEqual(result.alert?.saveError, result.saveError)
        XCTAssertFalse(result.config.profiles[0].collectorDebugEnabled)
    }
}
