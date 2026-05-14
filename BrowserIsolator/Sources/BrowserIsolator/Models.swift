import Foundation

struct Profile: Codable, Identifiable {
    var id: String { folder }
    let folder: String
    var displayName: String

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
}

struct AppConfig: Codable {
    var profiles: [Profile]

    static let `default` = AppConfig(
        profiles: [
            Profile(folder: "p1", displayName: ""),
            Profile(folder: "p2", displayName: ""),
            Profile(folder: "p3", displayName: "")
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

    func save(_ config: AppConfig) {
        AppPaths.ensureDirectories()
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            print("[BrowserIsolator] 配置文件保存失败: \(error)")
        }
    }
}