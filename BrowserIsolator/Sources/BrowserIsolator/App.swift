import SwiftUI

@main
struct BrowserIsolatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var manager = BrowserManager()

    var body: some Scene {
        WindowGroup {
            MainView(manager: manager)
                .frame(minWidth: 380, idealWidth: 420, minHeight: 320)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 440)

        MenuBarExtra("", systemImage: "macwindow.on.rectangle") {
            MenuBarView(manager: manager)
        }
        .menuBarExtraStyle(.menu)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        BrowserManager.shared?.stopAllAndWait()
    }
}

// MARK: - 主界面

struct MainView: View {
    @ObservedObject var manager: BrowserManager
    @State private var showRenameSheet: Bool = false
    @State private var renameTarget: Profile?
    @State private var renameText: String = ""
    @State private var showDeleteConfirm: Profile?

    /// 运行中的环境排在前面
    private var sortedProfiles: [Profile] {
        let running = manager.config.profiles.filter { manager.runningProfiles.contains($0.folder) }
        let stopped = manager.config.profiles.filter { !manager.runningProfiles.contains($0.folder) }
        return running + stopped
    }

    var body: some View {
        if !manager.chromiumReady {
            DownloadView(manager: manager)
        } else {
            profileList
        }
    }

    @ViewBuilder
    private var profileList: some View {
        List {
            if sortedProfiles.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("还没有环境")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("点击工具栏 + 添加一个")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            } else {
                ForEach(sortedProfiles) { profile in
                    ProfileRow(
                        profile: profile,
                        isRunning: manager.runningProfiles.contains(profile.folder),
                        isStarting: manager.startingProfiles.contains(profile.folder),
                        diskSize: manager.profileSizes[profile.folder],
                        lastUsed: manager.profileLastUsed[profile.folder],
                        onToggle: {
                            if manager.runningProfiles.contains(profile.folder) {
                                manager.stopProfile(profile)
                            } else {
                                manager.startProfile(profile)
                            }
                        }
                    )
                    .contextMenu {
                        Button("重命名") {
                            renameTarget = profile
                            renameText = profile.displayName
                            showRenameSheet = true
                        }
                        if !manager.runningProfiles.contains(profile.folder) {
                            Divider()
                            Button("删除", role: .destructive) {
                                showDeleteConfirm = profile
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("浏览器多开")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    manager.addProfile()
                } label: {
                    Label("添加环境", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    manager.stopAll()
                } label: {
                    Label("全部关闭", systemImage: "stop.fill")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(manager.runningProfiles.isEmpty)
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameSheet(name: $renameText) {
                if let target = renameTarget {
                    manager.updateDisplayName(for: target, newName: renameText)
                }
                renameTarget = nil
                showRenameSheet = false
            } onCancel: {
                renameTarget = nil
                showRenameSheet = false
            }
        }
        .alert("确认删除", isPresented: Binding(
            get: { showDeleteConfirm != nil },
            set: { if !$0 { showDeleteConfirm = nil } }
        )) {
            Button("取消", role: .cancel) { showDeleteConfirm = nil }
            Button("删除", role: .destructive) {
                if let p = showDeleteConfirm { manager.deleteProfile(p) }
                showDeleteConfirm = nil
            }
        } message: {
            if let p = showDeleteConfirm {
                Text("将删除「\(p.displayText)」的所有数据")
            }
        }
    }
}

// MARK: - Profile 行

struct ProfileRow: View {
    let profile: Profile
    let isRunning: Bool
    let isStarting: Bool
    let diskSize: Int64?
    let lastUsed: Date?
    let onToggle: () -> Void

    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .file
        return f
    }()

    private var sizeText: String? {
        guard let size = diskSize, size > 0 else { return nil }
        return Self.sizeFormatter.string(fromByteCount: size)
    }

    private var lastUsedText: String? {
        guard let date = lastUsed else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        let days = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 7 { return "\(days)天前" }
        if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            return "\(cal.component(.month, from: date))月\(cal.component(.day, from: date))日"
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isRunning ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayText)
                    .font(.system(size: 15, weight: isRunning ? .semibold : .regular))
                    .foregroundStyle(isRunning ? .primary : .secondary)

                HStack(spacing: 6) {
                    if let s = sizeText {
                        Text(s)
                    }
                    if sizeText != nil, lastUsedText != nil {
                        Text("·")
                    }
                    if let t = lastUsedText {
                        Text("最后使用 \(t)")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 16)

            if isStarting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20, height: 20)
            } else if isRunning {
                Button(role: .destructive, action: onToggle) {
                    Label("关闭", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            } else {
                Button(action: onToggle) {
                    Label("启动", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isRunning ? Color.green.opacity(0.06) : Color.clear)
        )
    }
}

// MARK: - 重命名弹窗

struct RenameSheet: View {
    @Binding var name: String
    @FocusState private var isFocused: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("重命名").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("自定义名称，方便识别")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("为此环境命名", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .focused($isFocused)
            }

            HStack(spacing: 12) {
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("确定", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 320)
        .onAppear { isFocused = true }
    }
}

// MARK: - 菜单栏视图

struct MenuBarView: View {
    @ObservedObject var manager: BrowserManager

    var body: some View {
        Group {
            if !manager.runningProfiles.isEmpty {
                ForEach(manager.config.profiles.filter { manager.runningProfiles.contains($0.folder) }) { profile in
                    HStack {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text(profile.displayText)
                        Spacer()
                        Button("关闭") { manager.stopProfile(profile) }
                    }
                }
                Button("全部关闭") { manager.stopAll() }
                Divider()
            }

            ForEach(manager.config.profiles.filter { !manager.runningProfiles.contains($0.folder) }) { profile in
                Button(profile.displayText) { manager.startProfile(profile) }
            }

            Divider()
            Button("打开管理面板") {
                NSApp.activate(ignoringOtherApps: true)
                if let main = NSApp.windows.first(where: { !($0 is NSPanel) }) {
                    main.makeKeyAndOrderFront(nil)
                }
            }
            Divider()
            Button("检查更新") { manager.checkForUpdates() }
            Button("退出") {
                if manager.runningProfiles.isEmpty {
                    NSApp.terminate(nil)
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    manager.showQuitConfirm = true
                }
            }
        }
        .alert(item: $manager.updateAlert) { alert in
            switch alert {
            case .upToDate:
                return Alert(
                    title: Text("检查更新"),
                    message: Text("当前已是最新版本"),
                    dismissButton: .default(Text("确定"))
                )
            case .updateAvailable(let latest):
                return Alert(
                    title: Text("发现新版本"),
                    message: Text("最新版本: \(latest)\n当前版本: \(manager.currentVersion)"),
                    primaryButton: .default(Text("前往下载"), action: { manager.openReleasesPage() }),
                    secondaryButton: .cancel(Text("稍后"))
                )
            case .checkFailed:
                return Alert(
                    title: Text("检查更新"),
                    message: Text("无法连接服务器，请检查网络后重试"),
                    dismissButton: .default(Text("确定"))
                )
            }
        }
        .alert("确认退出", isPresented: $manager.showQuitConfirm) {
            Button("取消", role: .cancel) {}
            Button("关闭并退出", role: .destructive) {
                NSApp.terminate(nil)
            }
        } message: {
            Text("还有 \(manager.runningProfiles.count) 个环境正在运行，退出将自动关闭所有环境。")
        }
    }
}

// MARK: - 下载视图

struct DownloadView: View {
    @ObservedObject var manager: BrowserManager

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "arrow.down.circle.dotted")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("首次使用，正在下载浏览器")
                .font(.system(size: 16, weight: .semibold))

            switch manager.downloadState {
            case .fetchingInfo:
                Text("准备中…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

            case .downloading(let progress):
                ProgressView(value: progress) {
                    Text("下载中…（约 237MB）")
                        .font(.system(size: 13))
                } currentValueLabel: {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)
                .frame(width: 260)

            case .extracting:
                ProgressView()
                    .controlSize(.small)
                Text("正在安装…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

            case .failed(let message):
                VStack(spacing: 10) {
                    Text("下载失败")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: 280)

                    Divider()
                        .frame(width: 200)

                    VStack(spacing: 6) {
                        Text("你也可以手动安装浏览器：")
                            .font(.system(size: 11, weight: .medium))
                        Text("1. 下载 Chrome：https://www.google.com/chrome/\n2. 双击 dmg，将「Google Chrome.app」\n   拖入下方目标文件夹")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: 280)
                        Button("打开目标文件夹") {
                            NSWorkspace.shared.open(AppPaths.chromiumDir)
                        }
                        .controlSize(.small)
                    }

                    HStack(spacing: 8) {
                        Button("重试下载") {
                            manager.downloadChromium()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

            case .idle:
                EmptyView()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
