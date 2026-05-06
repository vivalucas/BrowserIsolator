import Foundation
import AppKit
import Darwin

// MARK: - 下载状态

enum DownloadState: Equatable {
    case idle
    case fetchingInfo
    case downloading(progress: Double)
    case extracting
    case failed(String)
}

// MARK: - BrowserManager

@MainActor
class BrowserManager: ObservableObject {
    static var shared: BrowserManager?

    @Published var config: AppConfig
    @Published var runningProfiles: Set<String> = []
    @Published var startingProfiles: Set<String> = []
    @Published var chromiumReady: Bool = false
    @Published var downloadState: DownloadState = .idle

    private let configStore = ConfigStore()
    private var processes: [String: Process] = [:]
    private var fingerprintInjectors: [String: FingerprintInjector] = [:]
    private var refreshTimer: Timer?

    // Chrome 官方下载地址（Universal 版本，支持 Intel 和 Apple Silicon）
    private let chromeDownloadURL = "https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg"

    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let releasesURL = "https://github.com/vivalucas/BrowserIsolator/releases"
    private let latestReleaseAPI = "https://api.github.com/repos/vivalucas/BrowserIsolator/releases/latest"

    @Published var profileSizes: [String: Int64] = [:]
    @Published var profileLastUsed: [String: Date] = [:]

    @Published var updateAlert: UpdateAlert?
    @Published var showQuitConfirm: Bool = false

    enum UpdateAlert: Identifiable {
        case upToDate
        case updateAvailable(latest: String)
        case checkFailed

        var id: String {
            switch self {
            case .upToDate: return "upToDate"
            case .updateAvailable(let v): return "update-\(v)"
            case .checkFailed: return "checkFailed"
            }
        }
    }

    var chromiumExePath: String {
        AppPaths.chromiumDir
            .appendingPathComponent("Google Chrome.app")
            .appendingPathComponent("Contents/MacOS/Google Chrome")
            .path
    }

    init() {
        AppPaths.ensureDirectories()
        self.config = configStore.load()
        BrowserManager.shared = self
        ensureProfileDirs()
        refreshRunningStatus()
        startAutoRefresh()

        chromiumReady = FileManager.default.fileExists(atPath: chromiumExePath)
        if !chromiumReady {
            downloadChromium()
        }

        scanProfileInfo()
    }

    // MARK: - 启动 / 关闭

    func startProfile(_ profile: Profile) {
        guard chromiumReady, !runningProfiles.contains(profile.folder) else { return }
        let profileDir = AppPaths.profilesDir.appendingPathComponent(profile.folder).path

        startingProfiles.insert(profile.folder)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: chromiumExePath)
        process.arguments = [
            "--user-data-dir=\(profileDir)",
            "--no-first-run",
            "--test-type",
            "--remote-debugging-port=\(40000 + profile.instanceNumber)"
        ]
        do {
            try process.run()
            processes[profile.folder] = process
            runningProfiles.insert(profile.folder)

            // 启动指纹注入
            let debugPort = 40000 + profile.instanceNumber
            let injector = FingerprintInjector(debugPort: debugPort, instanceNumber: profile.instanceNumber)
            fingerprintInjectors[profile.folder] = injector
            Task.detached { await injector.startInjection() }

            // 启动成功，延迟移除 starting 状态，让用户能看到反馈
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.startingProfiles.remove(profile.folder)
            }
        } catch {
            startingProfiles.remove(profile.folder)
            print("[BrowserIsolator] 启动环境 \(profile.folder) 失败: \(error)")
        }
    }

    func stopProfile(_ profile: Profile) {
        startingProfiles.remove(profile.folder)
        if let injector = fingerprintInjectors.removeValue(forKey: profile.folder) {
            Task { await injector.disconnect() }
        }
        guard let process = processes.removeValue(forKey: profile.folder) else { return }
        if process.isRunning {
            let pid = process.processIdentifier
            kill(-pid, SIGTERM)
        }
        runningProfiles.remove(profile.folder)
    }

    func stopAll() {
        startingProfiles.removeAll()
        for (_, injector) in fingerprintInjectors { Task { await injector.disconnect() } }
        fingerprintInjectors.removeAll()
        for (_, process) in processes {
            if process.isRunning {
                let pid = process.processIdentifier
                kill(-pid, SIGTERM)
            }
        }
        processes.removeAll()
        runningProfiles.removeAll()
    }

    /// 发送 SIGTERM 并等待所有进程真正退出（用于 app 退出时调用）
    func stopAllAndWait() {
        for (_, injector) in fingerprintInjectors { Task { await injector.disconnect() } }
        fingerprintInjectors.removeAll()
        let group = DispatchGroup()
        for (_, process) in processes {
            if process.isRunning {
                let pid = process.processIdentifier
                kill(-pid, SIGTERM)
                group.enter()
                DispatchQueue.global().async {
                    process.waitUntilExit()
                    group.leave()
                }
            }
        }
        _ = group.wait(timeout: .now() + 5)
        processes.removeAll()
        runningProfiles.removeAll()
    }

    // MARK: - 状态检测

    func refreshRunningStatus() {
        var toRemove: [String] = []
        for (folder, process) in processes {
            if !process.isRunning {
                toRemove.append(folder)
            }
        }
        for folder in toRemove {
            processes.removeValue(forKey: folder)
            runningProfiles.remove(folder)
            if let injector = fingerprintInjectors.removeValue(forKey: folder) {
                Task { await injector.disconnect() }
            }
        }

        // CDP 注入健康检查：若 profile 在运行但注入未就绪，重新尝试
        Task {
            for folder in runningProfiles {
                let injector: FingerprintInjector
                if let existing = fingerprintInjectors[folder] {
                    let state = await existing.currentState()
                    if state == .injected { continue }
                    injector = existing
                } else {
                    guard let profile = config.profiles.first(where: { $0.folder == folder }) else { continue }
                    let port = 40000 + profile.instanceNumber
                    injector = FingerprintInjector(debugPort: port, instanceNumber: profile.instanceNumber)
                    fingerprintInjectors[folder] = injector
                }
                await injector.startInjection()
            }
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRunningStatus()
            }
        }
    }

    // MARK: - Profile 管理

    func addProfile() {
        let num = config.profiles.compactMap { Int($0.folder.dropFirst()) }
            .sorted().last ?? 0
        let folder = "p\(num + 1)"
        let profile = Profile(folder: folder, displayName: "")
        config.profiles.append(profile)
        let dir = AppPaths.profilesDir.appendingPathComponent(folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        configStore.save(config)
    }

    func deleteProfile(_ profile: Profile) {
        guard !runningProfiles.contains(profile.folder) else { return }
        let dir = AppPaths.profilesDir.appendingPathComponent(profile.folder)
        try? FileManager.default.removeItem(at: dir)
        config.profiles.removeAll { $0.folder == profile.folder }
        configStore.save(config)
    }

    func updateDisplayName(for profile: Profile, newName: String) {
        guard let idx = config.profiles.firstIndex(where: { $0.folder == profile.folder }) else { return }
        config.profiles[idx].displayName = newName
        configStore.save(config)
    }

    // MARK: - 检查更新

    func checkForUpdates() {
        Task {
            do {
                guard let url = URL(string: latestReleaseAPI) else { throw URLError(.badURL) }
                var request = URLRequest(url: url)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, _) = try await URLSession.shared.data(for: request)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let latestTag = json?["tag_name"] as? String else {
                    throw URLError(.cannotParseResponse)
                }
                let latest = latestTag.hasPrefix("v") ? String(latestTag.dropFirst()) : latestTag
                if latest.compare(currentVersion, options: .numeric) == .orderedDescending {
                    updateAlert = .updateAvailable(latest: latestTag)
                } else {
                    updateAlert = .upToDate
                }
            } catch {
                updateAlert = .checkFailed
                print("[BrowserIsolator] 检查更新失败: \(error)")
            }
        }
    }

    func openReleasesPage() {
        if let url = URL(string: releasesURL) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 下载浏览器

    func downloadChromium() {
        // 防止并发下载
        if case .downloading = downloadState { return }
        if case .extracting = downloadState { return }
        if case .fetchingInfo = downloadState { return }

        downloadState = .fetchingInfo

        Task {
            do {
                // 1. 下载 dmg
                print("[BrowserIsolator] 下载 Chrome from \(chromeDownloadURL)")
                let tempDMG = FileManager.default.temporaryDirectory
                    .appendingPathComponent("chrome-\(UUID().uuidString).dmg")
                try await downloadFile(from: chromeDownloadURL, to: tempDMG)

                // 2. 挂载 dmg 并直接安装
                downloadState = .extracting
                try await mountAndInstallChrome(from: tempDMG)

                // 3. 清理
                try? FileManager.default.removeItem(at: tempDMG)

                chromiumReady = true
                downloadState = .idle
                print("[BrowserIsolator] Chrome 安装完成: \(chromiumExePath)")
            } catch {
                print("[BrowserIsolator] 下载失败: \(error)")
                downloadState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - 下载私有方法

    private func downloadFile(from urlString: String, to destination: URL) async throws {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL else {
                    continuation.resume(throwing: URLError(.cannotCreateFile))
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            // 进度观测
            let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                let fraction = progress.fractionCompleted
                Task { @MainActor in
                    self?.downloadState = .downloading(progress: fraction)
                }
            }
            objc_setAssociatedObject(task, "obs", observation, .OBJC_ASSOCIATION_RETAIN)

            task.resume()
        }
    }

    /// 挂载 DMG 并直接安装 Chrome（省去中间拷贝，节省磁盘空间）
    private func mountAndInstallChrome(from dmgPath: URL) async throws {
        let fm = FileManager.default
        let mountPoint = fm.temporaryDirectory
            .appendingPathComponent("chrome-mount-\(UUID().uuidString)")

        // 挂载 dmg
        let mountProcess = Process()
        mountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mountProcess.arguments = ["attach", dmgPath.path, "-readonly", "-nobrowse", "-mountpoint", mountPoint.path]
        mountProcess.standardOutput = nil
        mountProcess.standardError = nil
        try mountProcess.run()
        mountProcess.waitUntilExit()

        guard mountProcess.terminationStatus == 0 else {
            throw NSError(domain: "BrowserIsolator", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "挂载安装包失败"
            ])
        }

        defer {
            // 卸载 dmg（即使后续操作失败也要卸载）
            let unmountProcess = Process()
            unmountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            unmountProcess.arguments = ["detach", mountPoint.path, "-force"]
            unmountProcess.standardOutput = nil
            unmountProcess.standardError = nil
            try? unmountProcess.run()
            unmountProcess.waitUntilExit()
        }

        let sourceApp = mountPoint.appendingPathComponent("Google Chrome.app")
        guard fm.fileExists(atPath: sourceApp.path) else {
            throw NSError(domain: "BrowserIsolator", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "安装包中找不到 Google Chrome.app"
            ])
        }

        // 直接从挂载点安装到目标目录
        let targetDir = AppPaths.chromiumDir
        let targetApp = targetDir.appendingPathComponent("Google Chrome.app")
        let backupDir = AppPaths.supportDir.appendingPathComponent("Chromium.backup")

        // 备份旧版本
        try? fm.removeItem(at: backupDir)
        if fm.fileExists(atPath: targetDir.path) {
            try fm.moveItem(at: targetDir, to: backupDir)
        }

        do {
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
            try fm.copyItem(at: sourceApp, to: targetApp)
            // 安装成功，删除备份
            try? fm.removeItem(at: backupDir)
        } catch {
            // 安装失败，恢复备份
            try? fm.removeItem(at: targetDir)
            if fm.fileExists(atPath: backupDir.path) {
                try fm.moveItem(at: backupDir, to: targetDir)
            }
            throw error
        }
    }

    private func ensureProfileDirs() {
        try? FileManager.default.createDirectory(at: AppPaths.profilesDir, withIntermediateDirectories: true)
        for p in config.profiles {
            try? FileManager.default.createDirectory(
                at: AppPaths.profilesDir.appendingPathComponent(p.folder),
                withIntermediateDirectories: true
            )
        }
    }

    /// 启动时扫描各环境的磁盘占用和最后使用时间
    private func scanProfileInfo() {
        let folders = config.profiles.map { $0.folder }
        Task.detached(priority: .utility) { [weak self] in
            var sizes: [String: Int64] = [:]
            var lastUsed: [String: Date] = [:]

            for folder in folders {
                let dir = AppPaths.profilesDir.appendingPathComponent(folder)
                let dirPath = dir.path
                let fm = FileManager.default

                if let attrs = try? fm.attributesOfItem(atPath: dirPath),
                   let date = attrs[.modificationDate] as? Date {
                    lastUsed[folder] = date
                }

                sizes[folder] = Self.directorySize(at: dirPath)
            }

            await MainActor.run { [weak self] in
                self?.profileSizes = sizes
                self?.profileLastUsed = lastUsed
            }
        }
    }

    private nonisolated static func directorySize(at path: String) -> Int64 {
        let fm = FileManager.default
        guard let subpaths = try? fm.subpathsOfDirectory(atPath: path) else { return 0 }
        var total: Int64 = 0
        for sub in subpaths {
            let fullPath = (path as NSString).appendingPathComponent(sub)
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let type = attrs[.type] as? FileAttributeType, type == .typeRegular,
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }
}