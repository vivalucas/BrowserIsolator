import Foundation

struct Profile: Codable, Identifiable {
    var id: String { folder }
    let folder: String
    var displayName: String
    var note: String
    var fingerprintEnabled: Bool
    var collectorDebugEnabled: Bool
    var lastUsed: Date?

    init(folder: String, displayName: String, note: String = "", fingerprintEnabled: Bool = false, collectorDebugEnabled: Bool = false, lastUsed: Date? = nil) {
        self.folder = folder
        self.displayName = displayName
        self.note = note
        self.fingerprintEnabled = fingerprintEnabled
        self.collectorDebugEnabled = collectorDebugEnabled
        self.lastUsed = lastUsed
    }

    /// Only for newly created environments; decoding and disk recovery retain legacy defaults.
    static func newEnvironment(folder: String) -> Profile {
        Profile(folder: folder, displayName: "", collectorDebugEnabled: true)
    }

    var instanceNumber: Int {
        guard folder.first == "p", !folder.dropFirst().isEmpty,
              folder.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(folder.dropFirst()), number > 0 else { return 0 }
        return number
    }

    var displayText: String {
        if displayName.isEmpty {
            return "环境\(instanceNumber)"
        } else {
            return "环境\(instanceNumber) - \(displayName)"
        }
    }

    enum CodingKeys: String, CodingKey {
        case folder
        case displayName
        case note
        case fingerprintEnabled
        case collectorDebugEnabled
        case lastUsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folder = try container.decode(String.self, forKey: .folder)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        fingerprintEnabled = try container.decodeIfPresent(Bool.self, forKey: .fingerprintEnabled) ?? false
        collectorDebugEnabled = try container.decodeIfPresent(Bool.self, forKey: .collectorDebugEnabled) ?? false
        lastUsed = try container.decodeIfPresent(Date.self, forKey: .lastUsed)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(folder, forKey: .folder)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(note, forKey: .note)
        try container.encode(fingerprintEnabled, forKey: .fingerprintEnabled)
        try container.encode(collectorDebugEnabled, forKey: .collectorDebugEnabled)
        try container.encodeIfPresent(lastUsed, forKey: .lastUsed)
    }
}

struct AppConfig: Codable {
    var profiles: [Profile]

    static let `default` = AppConfig(
        profiles: [
            .newEnvironment(folder: "p1"),
            .newEnvironment(folder: "p2"),
            .newEnvironment(folder: "p3")
        ]
    )
}

struct ConfigLoadResult {
    let config: AppConfig
    let alert: ConfigLoadAlert?
    var saveError: String? = nil
}

struct ConfigLoadAlert: Identifiable {
    enum Recovery {
        case backup
        case disk
        case defaults
    }

    let id = UUID()
    let recovery: Recovery
    let backupPath: String?
    var saveError: String? = nil
}

/// ~/Library/Application Support/BrowserIsolator/
struct AppPaths {
    static let supportDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("BrowserIsolator")
    }()

    static var configFile: URL { supportDir.appendingPathComponent("config.json") }
    static var configBackupFile: URL { supportDir.appendingPathComponent("config.json.bak") }
    static var profilesDir: URL { supportDir.appendingPathComponent("Profiles") }
    static var chromiumDir: URL { supportDir.appendingPathComponent("Chromium") }

    static func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: chromiumDir, withIntermediateDirectories: true)
    }
}

class ConfigStore {
    private let configURL: URL

    private let profilesURL: URL
    private var backupURL: URL { configURL.appendingPathExtension("bak") }

    init(configURL: URL = AppPaths.configFile, profilesURL: URL = AppPaths.profilesDir) {
        self.configURL = configURL
        self.profilesURL = profilesURL
    }

    func load() -> ConfigLoadResult {
        if let config = decodeConfig(at: configURL) {
            return ConfigLoadResult(config: config, alert: nil)
        }

        let mainFileExists = FileManager.default.fileExists(atPath: configURL.path)
        var corruptPath: String?
        if mainFileExists {
            let backupName = "config.corrupt-\(Int(Date().timeIntervalSince1970)).json"
            let backupURL = configURL.deletingLastPathComponent().appendingPathComponent(backupName)
            try? FileManager.default.removeItem(at: backupURL)
            if (try? FileManager.default.moveItem(at: configURL, to: backupURL)) != nil {
                corruptPath = backupURL.path
            }
        }

        if let backupConfig = decodeConfig(at: backupURL) {
            return persistLoadedConfig(backupConfig, alert: ConfigLoadAlert(recovery: .backup, backupPath: corruptPath))
        }

        if let rebuilt = rebuildFromProfileDirectories() {
            return persistLoadedConfig(rebuilt, alert: ConfigLoadAlert(recovery: .disk, backupPath: corruptPath))
        }
        if mainFileExists {
            return persistLoadedConfig(.default, alert: ConfigLoadAlert(recovery: .defaults, backupPath: corruptPath))
        }
        return persistLoadedConfig(.default, alert: nil)
    }

    // Persist before BrowserManager creates profile directories, so a restart does not
    // mistake newly generated defaults for existing environments requiring disk recovery.
    private func persistLoadedConfig(_ config: AppConfig, alert: ConfigLoadAlert?) -> ConfigLoadResult {
        do {
            try save(config)
            return ConfigLoadResult(config: config, alert: alert)
        } catch {
            var recoveryAlert = alert
            recoveryAlert?.saveError = error.localizedDescription
            return ConfigLoadResult(config: config, alert: recoveryAlert, saveError: error.localizedDescription)
        }
    }

    func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(config)
        let temporaryURL = configURL.appendingPathExtension("tmp")
        try data.write(to: temporaryURL, options: .atomic)
        let fm = FileManager.default
        if fm.fileExists(atPath: configURL.path) {
            try? fm.removeItem(at: backupURL)
            try fm.copyItem(at: configURL, to: backupURL)
        }
        if fm.fileExists(atPath: configURL.path) {
            _ = try fm.replaceItemAt(configURL, withItemAt: temporaryURL)
        } else {
            try fm.moveItem(at: temporaryURL, to: configURL)
        }
    }

    /// Persist the removal before touching browser data. Roll back metadata if recycling fails.
    func removingProfile(folder: String, from config: AppConfig, recycle: () throws -> Void) throws -> AppConfig {
        var updated = config
        updated.profiles.removeAll { $0.folder == folder }
        try save(updated)
        do {
            try recycle()
        } catch {
            try save(config)
            throw error
        }
        return updated
    }

    private func decodeConfig(at url: URL) -> AppConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard var config = try? JSONDecoder().decode(AppConfig.self, from: data) else { return nil }
        var seen = Set<String>()
        config.profiles = config.profiles.filter { profile in
            guard profile.instanceNumber > 0 else { return false }
            return seen.insert(profile.folder).inserted
        }
        return config
    }

    private func rebuildFromProfileDirectories() -> AppConfig? {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: profilesURL, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let profiles = urls.compactMap { url -> Profile? in
            let name = url.lastPathComponent
            guard Profile(folder: name, displayName: "").instanceNumber > 0,
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]),
                  values.isDirectory == true else { return nil }
            return Profile(folder: name, displayName: "", lastUsed: values.contentModificationDate)
        }.sorted { $0.instanceNumber < $1.instanceNumber }
        return profiles.isEmpty ? nil : AppConfig(profiles: profiles)
    }
}
