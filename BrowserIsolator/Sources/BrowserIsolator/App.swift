import SwiftUI

@main
struct BrowserIsolatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var manager = BrowserManager()
    @StateObject private var localization = Localization()

    var body: some Scene {
        WindowGroup {
            MainView(manager: manager, l10n: localization)
                .frame(minWidth: 420, idealWidth: 460, minHeight: 340)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 460)

        MenuBarExtra("", systemImage: "macwindow.on.rectangle") {
            MenuBarView(manager: manager, l10n: localization)
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
    @ObservedObject var l10n: Localization
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
            DownloadView(manager: manager, l10n: l10n)
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
                    Text(l10n.t("empty.title"))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(l10n.t("empty.subtitle"))
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
                        debugPort: manager.debugPort(for: profile),
                        diskSize: manager.profileSizes[profile.folder],
                        lastUsed: manager.profileLastUsed[profile.folder],
                        l10n: l10n,
                        onToggle: {
                            if manager.runningProfiles.contains(profile.folder) {
                                manager.stopProfile(profile)
                            } else {
                                manager.startProfile(profile)
                            }
                        }
                    )
                    .contextMenu {
                        Button(l10n.t("context.rename")) {
                            renameTarget = profile
                            renameText = profile.displayName
                            showRenameSheet = true
                        }
                        if !manager.runningProfiles.contains(profile.folder) {
                            Divider()
                            Button(l10n.t("context.delete"), role: .destructive) {
                                showDeleteConfirm = profile
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(l10n.t("app.name"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    manager.addProfile()
                } label: {
                    Label(l10n.t("toolbar.add"), systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                LanguageMenu(l10n: l10n)
            }

            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    manager.stopAll()
                } label: {
                    Label(l10n.t("toolbar.stop_all"), systemImage: "stop.fill")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(manager.runningProfiles.isEmpty)
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameSheet(name: $renameText, l10n: l10n) {
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
        .alert(l10n.t("delete.title"), isPresented: Binding(
            get: { showDeleteConfirm != nil },
            set: { if !$0 { showDeleteConfirm = nil } }
        )) {
            Button(l10n.t("common.cancel"), role: .cancel) { showDeleteConfirm = nil }
            Button(l10n.t("common.delete"), role: .destructive) {
                if let p = showDeleteConfirm { manager.deleteProfile(p) }
                showDeleteConfirm = nil
            }
        } message: {
            if let p = showDeleteConfirm {
                Text(l10n.format("delete.message", profileTitle(p, l10n: l10n)))
            }
        }
    }
}

@MainActor
private func profileTitle(_ profile: Profile, l10n: Localization) -> String {
    if profile.displayName.isEmpty {
        return l10n.format("profile.default_name", profile.instanceNumber)
    }
    return l10n.format("profile.display_name", profile.instanceNumber, profile.displayName)
}

// MARK: - Profile 行

struct ProfileRow: View {
    let profile: Profile
    let isRunning: Bool
    let isStarting: Bool
    let debugPort: Int?
    let diskSize: Int64?
    let lastUsed: Date?
    @ObservedObject var l10n: Localization
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
        if cal.isDateInToday(date) { return l10n.t("date.today") }
        if cal.isDateInYesterday(date) { return l10n.t("date.yesterday") }
        let days = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 7 { return l10n.format("date.days_ago", days) }
        if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            return l10n.format("date.month_day", cal.component(.month, from: date), cal.component(.day, from: date))
        }
        let df = DateFormatter()
        df.locale = l10n.locale
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    private var statusText: String {
        if isStarting { return l10n.t("status.starting") }
        if isRunning { return l10n.t("status.running") }
        return l10n.t("status.stopped")
    }

    private var statusColor: Color {
        if isStarting { return .orange }
        if isRunning { return .green }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Rectangle()
                    .fill(statusColor.opacity(isRunning || isStarting ? 0.26 : 0.12))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(profileTitle(profile, l10n: l10n))
                        .font(.system(size: 15, weight: isRunning ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusColor)
                }

                FlowMetaRow {
                    MetaItem(systemImage: "folder", text: profile.folder)

                    if let debugPort {
                        MetaItem(systemImage: "network", text: l10n.format("meta.port", debugPort))
                    }

                    if let s = sizeText {
                        MetaItem(systemImage: "internaldrive", text: s)
                    }

                    if let t = lastUsedText {
                        MetaItem(systemImage: "clock", text: t)
                    }
                }
            }

            Spacer(minLength: 16)

            if isStarting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20, height: 20)
            } else if isRunning {
                Button(role: .destructive, action: onToggle) {
                    Label(l10n.t("common.close"), systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            } else {
                Button(action: onToggle) {
                    Label(l10n.t("common.start"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isRunning ? Color.green.opacity(0.22) : Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }
}

struct FlowMetaRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

struct MetaItem: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(text)
                .monospacedDigit()
        }
    }
}

struct LanguageMenu: View {
    @ObservedObject var l10n: Localization

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    l10n.language = language
                } label: {
                    if language == l10n.language {
                        Label(language.nativeName, systemImage: "checkmark")
                    } else {
                        Text(language.nativeName)
                    }
                }
            }
        } label: {
            Label(l10n.t("language"), systemImage: "globe")
                .labelStyle(.titleAndIcon)
        }
    }
}

// MARK: - 重命名弹窗

struct RenameSheet: View {
    @Binding var name: String
    @ObservedObject var l10n: Localization
    @FocusState private var isFocused: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(l10n.t("rename.title")).font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("rename.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(l10n.t("rename.placeholder"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .focused($isFocused)
            }

            HStack(spacing: 12) {
                Button(l10n.t("common.cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(l10n.t("common.confirm"), action: onConfirm)
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
    @ObservedObject var l10n: Localization

    var body: some View {
        Group {
            if !manager.runningProfiles.isEmpty {
                ForEach(manager.config.profiles.filter { manager.runningProfiles.contains($0.folder) }) { profile in
                    HStack {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text(profileTitle(profile, l10n: l10n))
                        Spacer()
                        Button(l10n.t("common.close")) { manager.stopProfile(profile) }
                    }
                }
                Button(l10n.t("toolbar.stop_all")) { manager.stopAll() }
                Divider()
            }

            ForEach(manager.config.profiles.filter { !manager.runningProfiles.contains($0.folder) }) { profile in
                Button(profileTitle(profile, l10n: l10n)) { manager.startProfile(profile) }
            }

            Divider()
            Button(l10n.t("menu.open_panel")) {
                NSApp.activate(ignoringOtherApps: true)
                if let main = NSApp.windows.first(where: { !($0 is NSPanel) }) {
                    main.makeKeyAndOrderFront(nil)
                }
            }
            Divider()
            LanguageMenu(l10n: l10n)
            Divider()
            Button(l10n.t("menu.check_updates")) { manager.checkForUpdates() }
            Button(l10n.t("menu.quit")) {
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
                    title: Text(l10n.t("update.title")),
                    message: Text(l10n.t("update.up_to_date")),
                    dismissButton: .default(Text(l10n.t("common.confirm")))
                )
            case .updateAvailable(let latest):
                return Alert(
                    title: Text(l10n.t("update.available_title")),
                    message: Text(l10n.format("update.available_message", latest, manager.currentVersion)),
                    primaryButton: .default(Text(l10n.t("update.download")), action: { manager.openReleasesPage() }),
                    secondaryButton: .cancel(Text(l10n.t("common.later")))
                )
            case .checkFailed:
                return Alert(
                    title: Text(l10n.t("update.title")),
                    message: Text(l10n.t("update.failed")),
                    dismissButton: .default(Text(l10n.t("common.confirm")))
                )
            }
        }
        .alert(l10n.t("quit.title"), isPresented: $manager.showQuitConfirm) {
            Button(l10n.t("common.cancel"), role: .cancel) {}
            Button(l10n.t("quit.confirm"), role: .destructive) {
                NSApp.terminate(nil)
            }
        } message: {
            Text(l10n.format("quit.message", manager.runningProfiles.count))
        }
    }
}

// MARK: - 下载视图

struct DownloadView: View {
    @ObservedObject var manager: BrowserManager
    @ObservedObject var l10n: Localization

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "arrow.down.circle.dotted")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(l10n.t("download.title"))
                .font(.system(size: 16, weight: .semibold))

            switch manager.downloadState {
            case .fetchingInfo:
                Text(l10n.t("download.preparing"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

            case .downloading(let progress):
                ProgressView(value: progress) {
                    Text(l10n.t("download.progress"))
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
                Text(l10n.t("download.installing"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

            case .failed(let message):
                VStack(spacing: 10) {
                    Text(l10n.t("download.failed"))
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
                        Text(l10n.t("download.manual_title"))
                            .font(.system(size: 11, weight: .medium))
                        Text(l10n.t("download.manual_steps"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: 280)
                        Button(l10n.t("download.open_folder")) {
                            NSWorkspace.shared.open(AppPaths.chromiumDir)
                        }
                        .controlSize(.small)
                    }

                    HStack(spacing: 8) {
                        Button(l10n.t("download.retry")) {
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
