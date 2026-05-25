import Foundation

struct Profile: Codable, Identifiable {
    var id: String { folder }
    let folder: String
    var displayName: String
    var note: String
    var fingerprintEnabled: Bool

    init(folder: String, displayName: String, note: String = "", fingerprintEnabled: Bool = false) {
        self.folder = folder
        self.displayName = displayName
        self.note = note
        self.fingerprintEnabled = fingerprintEnabled
    }

    var instanceNumber: Int {
        Int(folder.dropFirst()) ?? 0
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folder = try container.decode(String.self, forKey: .folder)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        fingerprintEnabled = try container.decodeIfPresent(Bool.self, forKey: .fingerprintEnabled) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(folder, forKey: .folder)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(note, forKey: .note)
        try container.encode(fingerprintEnabled, forKey: .fingerprintEnabled)
    }
}

struct AppConfig: Codable {
    var profiles: [Profile]

    static let `default` = AppConfig(
        profiles: [
            Profile(folder: "p1", displayName: "", note: ""),
            Profile(folder: "p2", displayName: "", note: ""),
            Profile(folder: "p3", displayName: "", note: "")
        ]
    )
}

struct ConfigLoadResult {
    let config: AppConfig
    let alert: ConfigLoadAlert?
}

struct ConfigLoadAlert: Identifiable {
    let id = UUID()
    let backupPath: String?
}

/// ~/Library/Application Support/BrowserIsolator/
struct AppPaths {
    static let supportDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("BrowserIsolator")
    }()

    static var configFile: URL { supportDir.appendingPathComponent("config.json") }
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

    init() {
        self.configURL = AppPaths.configFile
    }

    func load() -> ConfigLoadResult {
        guard let data = try? Data(contentsOf: configURL) else {
            if FileManager.default.fileExists(atPath: configURL.path) {
                return ConfigLoadResult(config: .default, alert: ConfigLoadAlert(backupPath: nil))
            }
            return ConfigLoadResult(config: .default, alert: nil)
        }
        if let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return ConfigLoadResult(config: config, alert: nil)
        }

        if FileManager.default.fileExists(atPath: configURL.path) {
            let backupName = "config.corrupt-\(Int(Date().timeIntervalSince1970)).json"
            let backupURL = configURL.deletingLastPathComponent().appendingPathComponent(backupName)
            try? FileManager.default.removeItem(at: backupURL)
            if (try? FileManager.default.moveItem(at: configURL, to: backupURL)) != nil {
                return ConfigLoadResult(config: .default, alert: ConfigLoadAlert(backupPath: backupURL.path))
            }
        }
        return ConfigLoadResult(config: .default, alert: ConfigLoadAlert(backupPath: nil))
    }

    func save(_ config: AppConfig) throws {
        AppPaths.ensureDirectories()
        let data = try JSONEncoder().encode(config)
        try data.write(to: configURL, options: .atomic)
    }
}
