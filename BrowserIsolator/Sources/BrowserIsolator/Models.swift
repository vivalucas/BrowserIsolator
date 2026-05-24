import Foundation

struct Profile: Codable, Identifiable {
    var id: String { folder }
    let folder: String
    var displayName: String
    var note: String

    init(folder: String, displayName: String, note: String = "") {
        self.folder = folder
        self.displayName = displayName
        self.note = note
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folder = try container.decode(String.self, forKey: .folder)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(folder, forKey: .folder)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(note, forKey: .note)
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

    func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return .default
        }
        return config
    }

    func save(_ config: AppConfig) throws {
        AppPaths.ensureDirectories()
        let data = try JSONEncoder().encode(config)
        try data.write(to: configURL, options: .atomic)
    }
}
