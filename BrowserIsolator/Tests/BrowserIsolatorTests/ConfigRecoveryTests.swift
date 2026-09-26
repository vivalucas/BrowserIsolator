import XCTest
@testable import BrowserIsolator

final class ConfigRecoveryTests: XCTestCase {
    private func withStore(_ body: (ConfigStore, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profiles = root.appendingPathComponent("Profiles")
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.json")
        try body(ConfigStore(configURL: config, profilesURL: profiles), config, profiles)
    }

    func testCorruptPrimaryRestoresBackupAndPreservesDiagnostic() throws {
        try withStore { store, config, _ in
            let old = AppConfig(profiles: [Profile(folder: "p8", displayName: "Saved", note: "Keep")])
            try JSONEncoder().encode(old).write(to: config.appendingPathExtension("bak"))
            try Data("broken".utf8).write(to: config)
            let result = store.load()
            XCTAssertEqual(result.alert?.recovery, .backup)
            XCTAssertEqual(result.config.profiles.first?.note, "Keep")
            XCTAssertNotNil(result.alert?.backupPath)
            XCTAssertEqual(store.load().config.profiles.first?.folder, "p8")
        }
    }

    func testDiskRecoveryDoesNotEnableCollectorOrIncludeFiles() throws {
        try withStore { store, config, profiles in
            try Data("broken".utf8).write(to: config)
            try FileManager.default.createDirectory(at: profiles.appendingPathComponent("p7"), withIntermediateDirectories: true)
            try Data().write(to: profiles.appendingPathComponent("p8"))
            try FileManager.default.createDirectory(at: profiles.appendingPathComponent("x9"), withIntermediateDirectories: true)
            let result = store.load()
            XCTAssertEqual(result.alert?.recovery, .disk)
            XCTAssertEqual(result.config.profiles.map(\.folder), ["p7"])
            XCTAssertFalse(result.config.profiles[0].collectorDebugEnabled)
        }
    }

    func testValidConfigKeepsMissingDirectoryAndFiltersInvalidIdentity() throws {
        try withStore { store, config, _ in
            let profiles = ["p7", "x8", "p-1", "p0", "p+2", "p7"].map { Profile(folder: $0, displayName: "Keep") }
            try JSONEncoder().encode(AppConfig(profiles: profiles)).write(to: config)
            let result = store.load()
            XCTAssertNil(result.alert)
            XCTAssertEqual(result.config.profiles.map(\.folder), ["p7"])
            XCTAssertEqual(result.config.profiles[0].displayName, "Keep")
        }
    }

    func testSavingTwiceRetainsPreviousConfigInBackup() throws {
        try withStore { store, config, _ in
            try store.save(AppConfig(profiles: [Profile(folder: "p1", displayName: "Before")]))
            try store.save(AppConfig(profiles: [Profile(folder: "p1", displayName: "After")]))
            XCTAssertEqual(store.load().config.profiles[0].displayName, "After")
            let previous = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: config.appendingPathExtension("bak")))
            XCTAssertEqual(previous.profiles[0].displayName, "Before")
        }
    }

    func testLargeProfileNumberCannotOverflowPortCalculation() {
        let profile = Profile.newEnvironment(folder: "p\(Int.max)")
        XCTAssertGreaterThan(preferredDebugPort(for: profile)!, 65535)
    }
    func testDeleteSaveFailureNeverRecyclesDirectory() throws {
        try withStore { store, config, _ in
            let original = AppConfig(profiles: [Profile(folder: "p7", displayName: "Keep")])
            try store.save(original)
            try FileManager.default.createDirectory(at: config.appendingPathExtension("tmp"), withIntermediateDirectories: true)
            var recycled = false
            XCTAssertThrowsError(try store.removingProfile(folder: "p7", from: original) { recycled = true })
            XCTAssertFalse(recycled)
            XCTAssertEqual(store.load().config.profiles.first?.displayName, "Keep")
        }
    }

    func testRecycleFailureRestoresConfiguration() throws {
        try withStore { store, _, _ in
            let original = AppConfig(profiles: [Profile(folder: "p7", displayName: "Keep")])
            try store.save(original)
            XCTAssertThrowsError(try store.removingProfile(folder: "p7", from: original) {
                throw CocoaError(.fileWriteNoPermission)
            })
            XCTAssertEqual(store.load().config.profiles.first?.displayName, "Keep")
        }
    }

    func testSuccessfulDeletionStaysDeletedAfterReload() throws {
        try withStore { store, _, _ in
            let original = AppConfig(profiles: [Profile(folder: "p7", displayName: "Keep")])
            try store.save(original)
            let result = try store.removingProfile(folder: "p7", from: original) {}
            XCTAssertTrue(result.profiles.isEmpty)
            XCTAssertTrue(store.load().config.profiles.isEmpty)
        }
    }

}
