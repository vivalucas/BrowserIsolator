import Foundation
import AppKit
import ApplicationServices
import Darwin

// MARK: - 下载状态

enum DownloadState: Equatable {
    case idle
    case fetchingInfo
    case downloading(progress: Double)
    case extracting
    case verifying
    case failed(String)
}

// MARK: - 浏览器错误

enum BrowserError: LocalizedError {
    case noAvailablePort(preferred: Int, range: Int)
    case chromiumNotReady(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAvailablePort(let preferred, let range):
            return "无法找到可用端口（尝试范围：\(preferred)-\(preferred + range - 1)）"
        case .chromiumNotReady(let reason):
            return "浏览器不可用：\(reason)"
        case .downloadFailed(let reason):
            return "下载浏览器失败：\(reason)"
        }
    }
}

// MARK: - BrowserManager

@MainActor
class BrowserManager: ObservableObject {
    static var shared: BrowserManager?

    @Published var config: AppConfig
    @Published var runningProfiles: Set<String> = []
    @Published var startingProfiles: Set<String> = []
    @Published var stoppingProfiles: Set<String> = []
    @Published var chromiumReady: Bool = false
    @Published var downloadState: DownloadState = .idle

    private let configStore = ConfigStore()
    private var processes: [String: Process] = [:]
    private var fingerprintInjectors: [String: FingerprintInjector] = [:]
    private var debugPorts: [String: Int] = [:]
    private var pendingExternalURLs: [String: [URL]] = [:]

    // Chrome 官方下载地址（Universal 版本，支持 Intel 和 Apple Silicon）
    private let chromeDownloadURL = "https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg"

    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let releasesURL = "https://github.com/vivalucas/BrowserIsolator/releases"
    private let issuesURL = "https://github.com/vivalucas/BrowserIsolator/issues"
    let contactEmail = "lucas6.zju@vip.163.com"
    private let latestReleaseAPI = "https://api.github.com/repos/vivalucas/BrowserIsolator/releases/latest"
    private static let defaultOpenProfileFolderKey = "DefaultOpenProfileFolder"

    @Published var profileSizes: [String: Int64] = [:]
    @Published var profileLastUsed: [String: Date] = [:]
    @Published var profileErrors: [String: String] = [:]
    @Published var configLoadAlert: ConfigLoadAlert?
    @Published var configSaveAlert: ConfigSaveAlert?
    private var profileScanGeneration: UInt64 = 0


    @Published var updateAlert: UpdateAlert?
    @Published var showQuitConfirm: Bool = false
    @Published var externalLinkAlert: ExternalLinkAlert?

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

    struct ExternalLinkAlert: Identifiable {
        enum Kind {
            case link(URL)
            case noAvailableProfile(URL?)
        }

        let id = UUID()
        let kind: Kind
    }

    struct ConfigSaveAlert: Identifiable {
        let id = UUID()
        let message: String
    }



    var chromiumExePath: String {
        AppPaths.chromiumDir
            .appendingPathComponent("Google Chrome.app")
            .appendingPathComponent("Contents/MacOS/Google Chrome")
            .path
    }

    func debugPort(for profile: Profile) -> Int? {
        debugPorts[profile.folder]
    }

    var chromeVersionText: String? {
        let infoPlist = AppPaths.chromiumDir
            .appendingPathComponent("Google Chrome.app")
            .appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlist),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist["CFBundleShortVersionString"] as? String
    }

    var existingChromiumAvailable: Bool {
        isChromiumExecutableReady()
    }

    init() {
        AppPaths.ensureDirectories()
        let loadResult = configStore.load()
        self.config = loadResult.config
        self.configLoadAlert = loadResult.alert
        BrowserManager.shared = self
        ensureProfileDirs()

        chromiumReady = isChromiumExecutableReady()
        if !chromiumReady {
            downloadChromium()
        }

        scanProfileInfo()
    }

    // MARK: - 启动 / 关闭

    func startProfile(_ profile: Profile, urls: [URL] = []) {
        guard chromiumReady,
              !stoppingProfiles.contains(profile.folder) else { return }

        if startingProfiles.contains(profile.folder) {
            if !urls.isEmpty {
                pendingExternalURLs[profile.folder, default: []].append(contentsOf: urls)
            }
            return
        }

        if runningProfiles.contains(profile.folder) {
            if !urls.isEmpty {
                do {
                    let process = launchProfileProcess(profile, additionalArguments: urls.map(\.absoluteString))
                    try process.run()
                } catch {
                    print("[BrowserIsolator] 向已运行环境 \(profile.folder) 打开链接失败: \(error)")
                }
            }
            return
        }

        startingProfiles.insert(profile.folder)

        do {
            profileErrors.removeValue(forKey: profile.folder)
            try validateChromiumExecutable()
            let debugPort = try debugPortIfNeeded(for: profile)

            let process = launchProfileProcess(
                profile,
                debugPort: debugPort,
                additionalArguments: urls.map(\.absoluteString)
            )
            process.terminationHandler = { [weak self, folder = profile.folder] _ in
                Task { @MainActor in
                    self?.handleProcessTerminated(folder)
                }
            }
            try process.run()
            processes[profile.folder] = process
            if let debugPort {
                debugPorts[profile.folder] = debugPort
            }
            runningProfiles.insert(profile.folder)
            profileLastUsed[profile.folder] = Date()

            if let debugPort {
                // 启动 browser-level CDP 监听；新 tab 由 Target 事件驱动注入。
                let injector = FingerprintInjector(debugPort: debugPort, instanceNumber: profile.instanceNumber)
                fingerprintInjectors[profile.folder] = injector
                Task { await injector.startInjection() }
            }

            // 启动成功，延迟移除 starting 状态，让用户能看到反馈
            Task { [weak self, profile] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.startingProfiles.remove(profile.folder)
                if let queuedURLs = self?.pendingExternalURLs.removeValue(forKey: profile.folder),
                   !queuedURLs.isEmpty {
                    self?.startProfile(profile, urls: queuedURLs)
                }
            }
        } catch {
            startingProfiles.remove(profile.folder)
            debugPorts.removeValue(forKey: profile.folder)
            pendingExternalURLs.removeValue(forKey: profile.folder)
            profileErrors[profile.folder] = error.localizedDescription
            print("[BrowserIsolator] 启动环境 \(profile.folder) 失败: \(error)")
        }
    }

    private func launchProfileProcess(
        _ profile: Profile,
        debugPort: Int? = nil,
        additionalArguments: [String] = []
    ) -> Process {
        let profileDir = AppPaths.profilesDir.appendingPathComponent(profile.folder).path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: chromiumExePath)
        var arguments = [
            "--user-data-dir=\(profileDir)",
            "--no-first-run",
            "--test-type"
        ]
        if let debugPort {
            arguments.append("--remote-debugging-address=127.0.0.1")
            arguments.append("--remote-debugging-port=\(debugPort)")
        }
        arguments.append(contentsOf: additionalArguments)
        process.arguments = arguments
        return process
    }

    private func debugPortIfNeeded(for profile: Profile) throws -> Int? {
        guard profile.fingerprintEnabled else { return nil }
        return try findAvailablePort(preferred: 40000 + profile.instanceNumber)
    }

    /// 从首选端口开始查找可用端口，最多尝试 10 个
    private func findAvailablePort(preferred: Int) throws -> Int {
        for offset in 0..<10 {
            let port = preferred + offset
            if isPortAvailable(port) { return port }
        }
        throw BrowserError.noAvailablePort(preferred: preferred, range: 10)
    }

    private func isPortAvailable(_ port: Int) -> Bool {
        if debugPorts.values.contains(port) { return false }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = UInt32(0x7F000001).bigEndian // 127.0.0.1

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return true }
        defer { close(sock) }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in
                Darwin.bind(sock, addrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    func stopProfile(_ profile: Profile) {
        startingProfiles.remove(profile.folder)
        pendingExternalURLs.removeValue(forKey: profile.folder)
        if let injector = fingerprintInjectors.removeValue(forKey: profile.folder) {
            Task { await injector.disconnect() }
        }
        debugPorts.removeValue(forKey: profile.folder)
        guard let process = processes[profile.folder] else { return }
        stoppingProfiles.insert(profile.folder)
        if !process.isRunning {
            finishStoppedProfile(profile.folder)
            return
        }
        let pid = process.processIdentifier
        process.terminationHandler = nil
        kill(pid, SIGTERM)
        Task { [weak self, folder = profile.folder] in
            await Self.waitForProcessExit(process, pid: pid, timeout: 5)
            self?.finishStoppedProfile(folder)
        }
    }

    func stopAll() {
        startingProfiles.removeAll()
        pendingExternalURLs.removeAll()
        for (_, injector) in fingerprintInjectors { Task { await injector.disconnect() } }
        fingerprintInjectors.removeAll()
        debugPorts.removeAll()
        let stoppedFolders = Array(runningProfiles)
        let processesToStop = processes
        stoppingProfiles.formUnion(stoppedFolders)
        let runningProcesses = processesToStop.compactMap { _, process -> (Process, pid_t)? in
            process.terminationHandler = nil
            guard process.isRunning else { return nil }
            return (process, process.processIdentifier)
        }
        for (_, pid) in runningProcesses {
            kill(pid, SIGTERM)
        }
        Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for (process, pid) in runningProcesses {
                    group.addTask {
                        await Self.waitForProcessExit(process, pid: pid, timeout: 5)
                    }
                }
            }
            self?.finishStoppedProfiles(stoppedFolders)
        }
    }

    func stopAllThenQuit() {
        stopAll()
        Task {
            for _ in 0..<60 {
                if runningProfiles.isEmpty && stoppingProfiles.isEmpty {
                    NSApp.terminate(nil)
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            NSApp.terminate(nil)
        }
    }

    /// 发送 SIGTERM 并等待所有进程真正退出（用于 app 退出时调用）
    func stopAllAndWait() {
        pendingExternalURLs.removeAll()
        for (_, injector) in fingerprintInjectors { Task { await injector.disconnect() } }
        fingerprintInjectors.removeAll()
        debugPorts.removeAll()
        var running: [(Process, pid_t)] = []
        for (_, process) in processes {
            process.terminationHandler = nil
            if process.isRunning {
                running.append((process, process.processIdentifier))
            }
        }
        for (_, pid) in running {
            kill(pid, SIGTERM)
        }
        for _ in 0..<50 { // 50 * 0.1s = 5s
            var allDead = true
            for (_, pid) in running {
                if kill(pid, 0) == 0 { // 检查进程是否存在
                    allDead = false
                    break
                }
            }
            if allDead { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        for (_, pid) in running {
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
        }
        processes.removeAll()
        runningProfiles.removeAll()
        stoppingProfiles.removeAll()
    }

    // MARK: - 状态检测

    @discardableResult
    private func finishStoppedProfile(_ folder: String) -> Bool {
        let hadProcess = processes.removeValue(forKey: folder) != nil
        let wasRunning = runningProfiles.contains(folder)
        let wasStopping = stoppingProfiles.contains(folder)
        guard hadProcess || wasRunning || wasStopping else { return false }

        runningProfiles.remove(folder)
        stoppingProfiles.remove(folder)
        profileLastUsed[folder] = Date()

        scanProfileInfo()
        return true
    }

    private func finishStoppedProfiles(_ folders: [String]) {
        let now = Date()
        var changed = false
        for folder in folders {
            let hadProcess = processes.removeValue(forKey: folder) != nil
            let wasRunning = runningProfiles.contains(folder)
            let wasStopping = stoppingProfiles.contains(folder)
            guard hadProcess || wasRunning || wasStopping else { continue }
            runningProfiles.remove(folder)
            stoppingProfiles.remove(folder)
            profileLastUsed[folder] = now

            changed = true
        }
        if changed {
            scanProfileInfo()
        }
    }

    private func handleProcessTerminated(_ folder: String) {
        pendingExternalURLs.removeValue(forKey: folder)
        if let injector = fingerprintInjectors.removeValue(forKey: folder) {
            Task { await injector.disconnect() }
        }
        debugPorts.removeValue(forKey: folder)
        finishStoppedProfile(folder)
    }

    // MARK: - Profile 管理

    @discardableResult
    func addProfile() -> Profile {
        let folder = "p\(nextAvailableProfileNumber())"
        let profile = Profile(folder: folder, displayName: "")
        config.profiles.append(profile)
        let dir = AppPaths.profilesDir.appendingPathComponent(folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        saveConfig()
        scanProfileInfo()
        return profile
    }

    func deleteProfile(_ profile: Profile) {
        moveProfileToTrash(profile)
    }

    func moveProfileToTrash(_ profile: Profile) {
        guard !runningProfiles.contains(profile.folder),
              !startingProfiles.contains(profile.folder),
              !stoppingProfiles.contains(profile.folder) else { return }
        pendingExternalURLs.removeValue(forKey: profile.folder)
        let dir = AppPaths.profilesDir.appendingPathComponent(profile.folder)
        do {
            if FileManager.default.fileExists(atPath: dir.path) {
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: dir, resultingItemURL: &trashedURL)
            }
        } catch {
            profileErrors[profile.folder] = error.localizedDescription
            print("[BrowserIsolator] 删除环境 \(profile.folder) 失败: \(error)")
            return
        }
        config.profiles.removeAll { $0.folder == profile.folder }
        profileSizes.removeValue(forKey: profile.folder)
        profileLastUsed.removeValue(forKey: profile.folder)

        profileErrors.removeValue(forKey: profile.folder)
        saveConfig()
        scanProfileInfo()
    }

    func updateDisplayName(for profile: Profile, newName: String) {
        guard let idx = config.profiles.firstIndex(where: { $0.folder == profile.folder }) else { return }
        config.profiles[idx].displayName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        saveConfig()
    }

    func updateNote(for profile: Profile, newNote: String) {
        guard let idx = config.profiles.firstIndex(where: { $0.folder == profile.folder }) else { return }
        config.profiles[idx].note = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        saveConfig()
    }

    func updateFingerprintEnabled(for profile: Profile, isEnabled: Bool) {
        guard canChangeFingerprintMode(for: profile),
              let idx = config.profiles.firstIndex(where: { $0.folder == profile.folder }) else { return }
        config.profiles[idx].fingerprintEnabled = isEnabled
        saveConfig()
    }

    func canChangeFingerprintMode(for profile: Profile) -> Bool {
        !runningProfiles.contains(profile.folder)
            && !startingProfiles.contains(profile.folder)
            && !stoppingProfiles.contains(profile.folder)
    }

    func defaultOpenProfile() -> Profile? {
        let storedFolder = UserDefaults.standard.string(forKey: Self.defaultOpenProfileFolderKey) ?? ""
        if let profile = config.profiles.first(where: { $0.folder == storedFolder }) {
            return profile
        }
        return config.profiles.first
    }

    func clearProfileError(_ profile: Profile) {
        profileErrors.removeValue(forKey: profile.folder)
    }

    private func nextAvailableProfileNumber() -> Int {
        let usedNumbers = Set(config.profiles.compactMap {
            let number = Int($0.folder.dropFirst())
            return number.flatMap { $0 > 0 ? $0 : nil }
        })
        var candidate = 1
        while usedNumbers.contains(candidate) {
            candidate += 1
        }
        return candidate
    }

    private func saveConfig() {
        do {
            try configStore.save(config)
            configSaveAlert = nil
        } catch {
            let message = error.localizedDescription
            configSaveAlert = ConfigSaveAlert(message: message)
            print("[BrowserIsolator] 配置文件保存失败: \(error)")
        }
    }

    // MARK: - 检查更新

    func checkForUpdates() {
        Task {
            do {
                guard let url = URL(string: latestReleaseAPI) else { throw URLError(.badURL) }
                var request = URLRequest(url: url)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard httpResponse.statusCode == 200 else {
                    throw URLError(.init(rawValue: httpResponse.statusCode))
                }
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

    func openIssuesPage() {
        if let url = URL(string: issuesURL) {
            NSWorkspace.shared.open(url)
        }
    }

    func openExternalURLs(_ urls: [URL]) {
        let validURLs = urls.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        guard !validURLs.isEmpty else { return }
        guard chromiumReady else {
            externalLinkAlert = ExternalLinkAlert(kind: .link(validURLs[0]))
            return
        }
        guard let profile = defaultOpenProfile() else {
            print("[BrowserIsolator] 外部链接到达，但没有可用环境")
            externalLinkAlert = ExternalLinkAlert(kind: .noAvailableProfile(validURLs[0]))
            return
        }
        if startingProfiles.contains(profile.folder) {
            pendingExternalURLs[profile.folder, default: []].append(contentsOf: validURLs)
            return
        }
        startProfile(profile, urls: validURLs)
    }

    func setAsDefaultBrowser() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        for scheme in ["http", "https"] {
            let status = LSSetDefaultHandlerForURLScheme(scheme as CFString, bundleID as CFString)
            if status != noErr {
                print("[BrowserIsolator] 设置默认浏览器失败: scheme=\(scheme), status=\(status)")
            }
        }
    }

    func copyContactEmail() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contactEmail, forType: .string)
    }

    func copyExternalLink(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    // MARK: - 下载浏览器

    func downloadChromium() {
        // 防止并发下载
        if case .downloading = downloadState { return }
        if case .extracting = downloadState { return }
        if case .verifying = downloadState { return }
        if case .fetchingInfo = downloadState { return }

        downloadState = .fetchingInfo

        Task {
            do {
                // 1. 下载 dmg
                print("[BrowserIsolator] 下载 Chrome from \(chromeDownloadURL)")
                let tempDMG = FileManager.default.temporaryDirectory
                    .appendingPathComponent("chrome-\(UUID().uuidString).dmg")
                defer { try? FileManager.default.removeItem(at: tempDMG) }
                try await downloadFile(from: chromeDownloadURL, to: tempDMG)

                // 2. 挂载 dmg 并直接安装
                downloadState = .extracting
                try await mountAndInstallChrome(from: tempDMG)

                downloadState = .verifying
                try validateChromiumExecutable()
                chromiumReady = true
                downloadState = .idle
                print("[BrowserIsolator] Chrome 安装完成: \(chromiumExePath)")
            } catch {
                print("[BrowserIsolator] 下载失败: \(error)")
                downloadState = .failed(error.localizedDescription)
            }
        }
    }

    func reinstallChromium() {
        guard runningProfiles.isEmpty, stoppingProfiles.isEmpty, startingProfiles.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: AppPaths.chromiumDir, withIntermediateDirectories: true)
            chromiumReady = false
            downloadChromium()
        } catch {
            downloadState = .failed(error.localizedDescription)
        }
    }

    func useExistingChromiumIfAvailable() {
        guard isChromiumExecutableReady() else { return }
        chromiumReady = true
        downloadState = .idle
    }

    func openSupportFolder() {
        NSWorkspace.shared.open(AppPaths.supportDir)
    }

    func openProfilesFolder() {
        NSWorkspace.shared.open(AppPaths.profilesDir)
    }

    func openChromiumFolder() {
        NSWorkspace.shared.open(AppPaths.chromiumDir)
    }

    func copySupportPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AppPaths.supportDir.path, forType: .string)
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
                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    continuation.resume(throwing: BrowserError.downloadFailed("HTTP \(http.statusCode)"))
                    return
                }
                if let mimeType = response?.mimeType,
                   !mimeType.localizedCaseInsensitiveContains("diskimage"),
                   !mimeType.localizedCaseInsensitiveContains("octet-stream") {
                    continuation.resume(throwing: BrowserError.downloadFailed("返回内容不是 DMG（\(mimeType)）"))
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
            
            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-dr", "com.apple.quarantine", targetApp.path]
            try? xattrProcess.run()
            xattrProcess.waitUntilExit()

            try validateChromiumExecutable()
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

    private func isChromiumExecutableReady() -> Bool {
        (try? validateChromiumExecutable()) != nil
    }

    private func validateChromiumExecutable() throws {
        let path = chromiumExePath
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            throw BrowserError.chromiumNotReady("找不到 Google Chrome 可执行文件")
        }
        guard fm.isExecutableFile(atPath: path) else {
            throw BrowserError.chromiumNotReady("Google Chrome 可执行文件没有执行权限")
        }
    }

    private nonisolated static func waitForProcessExit(_ process: Process, pid: pid_t, timeout: TimeInterval) async {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                process.waitUntilExit()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }

            let exited = await group.next() ?? false
            group.cancelAll()
            if !exited, process.isRunning {
                kill(pid, SIGKILL)
            }
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
        profileScanGeneration &+= 1
        let generation = profileScanGeneration
        Task.detached(priority: .utility) { [weak self] in
            var sizes: [String: Int64] = [:]
            var lastUsed: [String: Date] = [:]

            for folder in folders {
                let isCurrentGeneration = await MainActor.run { [weak self] in
                    self?.profileScanGeneration == generation
                }
                guard isCurrentGeneration == true else { return }
                let dir = AppPaths.profilesDir.appendingPathComponent(folder)
                let dirPath = dir.path
                let fm = FileManager.default

                if let attrs = try? fm.attributesOfItem(atPath: dirPath),
                   let date = attrs[.modificationDate] as? Date {
                    lastUsed[folder] = date
                } else {
                    lastUsed[folder] = nil
                }

                // 直接重算目录大小，不依赖 modificationDate 做不可靠的深层变更缓存
                let size = Self.directorySize(at: dirPath)
                sizes[folder] = size
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.profileScanGeneration == generation else { return }
                for (folder, date) in self.profileLastUsed {
                    if let scanned = lastUsed[folder] {
                        lastUsed[folder] = max(scanned, date)
                    } else {
                        lastUsed[folder] = date
                    }
                }
                self.profileSizes = sizes
                self.profileLastUsed = lastUsed
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
