import SwiftUI

@main
struct BrowserIsolatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var manager = BrowserManager()
    @StateObject private var localization = Localization()

    var body: some Scene {
        WindowGroup {
            MainView(manager: manager, l10n: localization)
                .frame(minWidth: 680, idealWidth: 760, minHeight: 420)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 760, height: 520)

        MenuBarExtra("", systemImage: manager.runningProfiles.isEmpty ? "macwindow.on.rectangle" : "macwindow.badge.plus") {
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
    @State private var deleteConfirmText: String = ""
    @State private var selectedProfileID: String?
    @State private var showSettings: Bool = false
    @AppStorage("ShowAdvancedDetails") private var showAdvancedDetails: Bool = false

    /// 运行中的环境排在前面
    private var sortedProfiles: [Profile] {
        let running = manager.config.profiles
            .filter { manager.runningProfiles.contains($0.folder) || manager.stoppingProfiles.contains($0.folder) }
        let stopped = manager.config.profiles
            .filter { !manager.runningProfiles.contains($0.folder) && !manager.stoppingProfiles.contains($0.folder) }
            .sorted { (manager.profileLastUsed[$0.folder] ?? .distantPast) > (manager.profileLastUsed[$1.folder] ?? .distantPast) }
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
        HSplitView {
            List {
                if sortedProfiles.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 44))
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
                            isSelected: selectedProfileID == profile.folder,
                            isRunning: manager.runningProfiles.contains(profile.folder),
                            isStarting: manager.startingProfiles.contains(profile.folder),
                            isStopping: manager.stoppingProfiles.contains(profile.folder),
                            diskSize: manager.profileSizes[profile.folder],
                            lastUsed: manager.profileLastUsed[profile.folder],
                            hasError: manager.profileErrors[profile.folder] != nil,
                            l10n: l10n,
                            onToggle: {
                                if manager.runningProfiles.contains(profile.folder) {
                                    manager.stopProfile(profile)
                                } else {
                                    manager.startProfile(profile)
                                }
                            }
                        )
                        .tag(profile.folder)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedProfileID = profile.folder
                        }
                        .onTapGesture(count: 2) {
                            selectedProfileID = profile.folder
                            if !manager.runningProfiles.contains(profile.folder),
                               !manager.startingProfiles.contains(profile.folder),
                               !manager.stoppingProfiles.contains(profile.folder) {
                                manager.startProfile(profile)
                            }
                        }
                        .contextMenu {
                            Button(l10n.t("context.rename")) {
                                renameTarget = profile
                                renameText = profile.displayName
                                showRenameSheet = true
                            }
                            if !manager.runningProfiles.contains(profile.folder),
                               !manager.stoppingProfiles.contains(profile.folder) {
                                Divider()
                                Button(l10n.t("context.delete"), role: .destructive) {
                                    showDeleteConfirm = profile
                                    deleteConfirmText = ""
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .frame(minWidth: 340, idealWidth: 360)

            ProfileInspectorView(
                profile: selectedProfile,
                manager: manager,
                l10n: l10n,
                showAdvancedDetails: showAdvancedDetails,
                onRename: { profile in
                    renameTarget = profile
                    renameText = profile.displayName
                    showRenameSheet = true
                },
                onDelete: { profile in
                    showDeleteConfirm = profile
                    deleteConfirmText = ""
                }
            )
            .frame(minWidth: 300, idealWidth: 340)
        }
        .navigationTitle(l10n.t("app.name"))
        .onAppear { ensureSelection() }
        .onChange(of: manager.config.profiles.map(\.folder)) { _ in ensureSelection() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let profile = manager.addProfile()
                    selectedProfileID = profile.folder
                    renameTarget = profile
                    renameText = ""
                    showRenameSheet = true
                } label: {
                    Label(l10n.t("toolbar.add"), systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Label(l10n.t("settings.title"), systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                }
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
        .sheet(isPresented: $showSettings) {
            SettingsView(
                manager: manager,
                l10n: l10n,
                showAdvancedDetails: $showAdvancedDetails
            )
        }
        .alert(l10n.t("delete.title"), isPresented: Binding(
            get: { showDeleteConfirm != nil },
            set: {
                if !$0 {
                    showDeleteConfirm = nil
                    deleteConfirmText = ""
                }
            }
        )) {
            TextField(l10n.t("delete.confirm_placeholder"), text: $deleteConfirmText)
            Button(l10n.t("common.cancel"), role: .cancel) {
                showDeleteConfirm = nil
                deleteConfirmText = ""
            }
            Button(l10n.t("common.delete"), role: .destructive) {
                if let p = showDeleteConfirm,
                   deleteConfirmText == profileTitle(p, l10n: l10n) {
                    manager.moveProfileToTrash(p)
                }
                showDeleteConfirm = nil
                deleteConfirmText = ""
            }
            .disabled(showDeleteConfirm.map { deleteConfirmText != profileTitle($0, l10n: l10n) } ?? true)
        } message: {
            if let p = showDeleteConfirm {
                Text(l10n.format(
                    "delete.message",
                    profileTitle(p, l10n: l10n),
                    ProfileRow.sizeFormatter.string(fromByteCount: manager.profileSizes[p.folder] ?? 0)
                ))
            }
        }
    }

    private var selectedProfile: Profile? {
        guard let selectedProfileID else { return sortedProfiles.first }
        return manager.config.profiles.first { $0.folder == selectedProfileID } ?? sortedProfiles.first
    }

    private func ensureSelection() {
        guard !sortedProfiles.isEmpty else {
            selectedProfileID = nil
            return
        }
        if selectedProfileID == nil || !sortedProfiles.contains(where: { $0.folder == selectedProfileID }) {
            selectedProfileID = sortedProfiles.first?.folder
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

@MainActor
private func formatLastUsed(_ date: Date?, l10n: Localization) -> String? {
    guard let date else { return nil }
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

// MARK: - Profile 行

struct ProfileRow: View {
    let profile: Profile
    let isSelected: Bool
    let isRunning: Bool
    let isStarting: Bool
    let isStopping: Bool
    let diskSize: Int64?
    let lastUsed: Date?
    let hasError: Bool
    @ObservedObject var l10n: Localization
    let onToggle: () -> Void

    static let sizeFormatter: ByteCountFormatter = {
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
        formatLastUsed(lastUsed, l10n: l10n)
    }

    private var statusText: String {
        if isStarting { return l10n.t("status.starting") }
        if isStopping { return l10n.t("status.stopping") }
        if isRunning { return l10n.t("status.running") }
        return l10n.t("status.stopped")
    }

    private var statusColor: Color {
        if isStarting { return .orange }
        if isStopping { return .orange }
        if isRunning { return .green }
        return .secondary
    }

    private var selectionTint: Color {
        Color(nsColor: .controlAccentColor)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(profileTitle(profile, l10n: l10n))
                        .font(.system(size: 14, weight: isRunning ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if hasError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }

                FlowMetaRow {
                    Text(statusText)
                        .foregroundStyle(statusColor)
                    if let t = lastUsedText {
                        MetaItem(systemImage: "clock", text: t)
                    }
                    if let s = sizeText {
                        MetaItem(systemImage: "internaldrive", text: s)
                    }
                }
            }

            Spacer(minLength: 10)

            if isStarting || isStopping {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20, height: 20)
            } else if isRunning {
                Button(role: .destructive, action: onToggle) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(l10n.t("common.close"))
            } else {
                Button(action: onToggle) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help(l10n.t("common.start"))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? selectionTint.opacity(0.11) : Color.clear)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(0.35)
                    }
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? selectionTint.opacity(0.65) : Color.clear, lineWidth: 1.2)
        }
    }
}

// MARK: - Inspector

struct ProfileInspectorView: View {
    let profile: Profile?
    @ObservedObject var manager: BrowserManager
    @ObservedObject var l10n: Localization
    let showAdvancedDetails: Bool
    let onRename: (Profile) -> Void
    let onDelete: (Profile) -> Void

    var body: some View {
        Group {
            if let profile {
                inspector(for: profile)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text(l10n.t("inspector.empty_title"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(l10n.t("inspector.empty_subtitle"))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func inspector(for profile: Profile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(profileTitle(profile, l10n: l10n))
                                .font(.system(size: 20, weight: .semibold))
                                .lineLimit(2)
                            Label(statusText(for: profile), systemImage: "circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(statusColor(for: profile))
                        }
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        primaryAction(for: profile)
                        Button(l10n.t("context.rename")) { onRename(profile) }
                    }
                }

                if let error = manager.profileErrors[profile.folder] {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(l10n.t("inspector.error"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 13, weight: .semibold))
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack {
                            Button(l10n.t("inspector.retry")) { manager.startProfile(profile) }
                                .disabled(isRunning(profile) || isStopping(profile))
                            Button(l10n.t("inspector.clear_error")) { manager.clearProfileError(profile) }
                        }
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                InspectorSection(title: l10n.t("inspector.basic")) {
                    DetailLine(label: l10n.t("inspector.last_used"), value: lastUsedText(for: profile) ?? "-")
                    DetailLine(label: l10n.t("details.folder"), value: profile.folder)
                    DetailLine(label: l10n.t("details.profile_path"), value: profilePath(profile).path)
                    if let size = manager.profileSizes[profile.folder] {
                        DetailLine(label: l10n.t("settings.data"), value: ProfileRow.sizeFormatter.string(fromByteCount: size))
                    }
                    if let debugPort = manager.debugPort(for: profile) {
                        DetailLine(label: l10n.t("details.port"), value: "\(debugPort)")
                    }
                }

                if showAdvancedDetails {
                    InspectorSection(title: l10n.t("inspector.advanced")) {
                        let values = fingerprintValues(for: profile)
                        DetailLine(label: l10n.t("details.cpu"), value: "\(values.cores)")
                        DetailLine(label: l10n.t("details.memory"), value: "\(values.memory) GB")
                        DetailLine(label: l10n.t("settings.chrome_version"), value: manager.chromeVersionText ?? l10n.t("settings.unknown"))
                        DetailLine(label: l10n.t("settings.open_chrome_folder"), value: manager.chromiumExePath)
                    }
                }

                InspectorSection(title: l10n.t("inspector.actions")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button(l10n.t("inspector.open_profile_folder")) {
                                NSWorkspace.shared.open(profilePath(profile))
                            }
                            Button(l10n.t("inspector.copy_profile_path")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(profilePath(profile).path, forType: .string)
                            }
                        }
                        Button(role: .destructive) {
                            onDelete(profile)
                        } label: {
                            Label(l10n.t("common.delete"), systemImage: "trash")
                        }
                        .disabled(isRunning(profile) || isStopping(profile))
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func primaryAction(for profile: Profile) -> some View {
        if isStarting(profile) || isStopping(profile) {
            ProgressView().controlSize(.small)
        } else if isRunning(profile) {
            Button(role: .destructive) {
                manager.stopProfile(profile)
            } label: {
                Label(l10n.t("common.close"), systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
        } else {
            Button {
                manager.startProfile(profile)
            } label: {
                Label(l10n.t("common.start"), systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func isRunning(_ profile: Profile) -> Bool {
        manager.runningProfiles.contains(profile.folder)
    }

    private func isStarting(_ profile: Profile) -> Bool {
        manager.startingProfiles.contains(profile.folder)
    }

    private func isStopping(_ profile: Profile) -> Bool {
        manager.stoppingProfiles.contains(profile.folder)
    }

    private func statusText(for profile: Profile) -> String {
        if isStarting(profile) { return l10n.t("status.starting") }
        if isStopping(profile) { return l10n.t("status.stopping") }
        if isRunning(profile) { return l10n.t("status.running") }
        return l10n.t("status.stopped")
    }

    private func statusColor(for profile: Profile) -> Color {
        if isStarting(profile) || isStopping(profile) { return .orange }
        if isRunning(profile) { return .green }
        return .secondary
    }

    private func lastUsedText(for profile: Profile) -> String? {
        formatLastUsed(manager.profileLastUsed[profile.folder], l10n: l10n)
    }

    private func profilePath(_ profile: Profile) -> URL {
        AppPaths.profilesDir.appendingPathComponent(profile.folder)
    }

    private func fingerprintValues(for profile: Profile) -> (cores: Int, memory: Int) {
        let cores = [4, 6, 8, 10]
        let memory = [4, 8, 16]
        let num = max(profile.instanceNumber, 1)
        return (cores[(num - 1) % cores.count], memory[(num - 1) % memory.count])
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
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

struct DetailLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .frame(width: 86, alignment: .leading)
                .foregroundStyle(.tertiary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
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

    private var runningProfiles: [Profile] {
        manager.config.profiles.filter { manager.runningProfiles.contains($0.folder) }
    }

    private var stoppedProfiles: [Profile] {
        manager.config.profiles
            .filter { !manager.runningProfiles.contains($0.folder) && !manager.stoppingProfiles.contains($0.folder) }
            .sorted { (manager.profileLastUsed[$0.folder] ?? .distantPast) > (manager.profileLastUsed[$1.folder] ?? .distantPast) }
    }

    var body: some View {
        Group {
            if !runningProfiles.isEmpty {
                ForEach(runningProfiles) { profile in
                    Button {
                        manager.stopProfile(profile)
                    } label: {
                        Label(profileTitle(profile, l10n: l10n), systemImage: "stop.fill")
                    }
                }
                Button(l10n.t("toolbar.stop_all")) { manager.stopAll() }
                Button(l10n.t("menu.close_all_quit")) {
                    manager.stopAllThenQuit()
                }
                Divider()
            }

            ForEach(stoppedProfiles) { profile in
                Button {
                    manager.startProfile(profile)
                } label: {
                    Label(profileTitle(profile, l10n: l10n), systemImage: "play.fill")
                }
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

// MARK: - 设置

struct SettingsView: View {
    @ObservedObject var manager: BrowserManager
    @ObservedObject var l10n: Localization
    @Binding var showAdvancedDetails: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showContact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(l10n.t("settings.title"))
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            GroupBox(l10n.t("settings.browser")) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsLine(label: l10n.t("settings.chrome_status"), value: manager.chromiumReady ? l10n.t("settings.ready") : l10n.t("settings.not_installed"))
                    SettingsLine(label: l10n.t("settings.chrome_version"), value: manager.chromeVersionText ?? l10n.t("settings.unknown"))
                    HStack {
                        Button(l10n.t("settings.open_chrome_folder")) { manager.openChromiumFolder() }
                        Button(l10n.t("settings.redownload_chrome")) { manager.reinstallChromium() }
                            .disabled(!manager.runningProfiles.isEmpty || !manager.stoppingProfiles.isEmpty)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(l10n.t("settings.data")) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsLine(label: l10n.t("settings.data_path"), value: AppPaths.supportDir.path)
                    HStack {
                        Button(l10n.t("settings.open_data_folder")) { manager.openSupportFolder() }
                        Button(l10n.t("settings.open_profiles_folder")) { manager.openProfilesFolder() }
                        Button(l10n.t("settings.copy_path")) { manager.copySupportPath() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(l10n.t("settings.preferences")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(l10n.t("language"))
                        Spacer()
                        LanguageMenu(l10n: l10n)
                    }
                    Toggle(l10n.t("settings.show_advanced"), isOn: $showAdvancedDetails)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(l10n.t("settings.help_updates")) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsLine(label: l10n.t("settings.app_version"), value: manager.currentVersion)

                    HStack(spacing: 8) {
                        Button {
                            manager.checkForUpdates()
                        } label: {
                            Label(l10n.t("menu.check_updates"), systemImage: "arrow.down.circle")
                        }

                        Button {
                            manager.openReleasesPage()
                        } label: {
                            Label(l10n.t("settings.view_releases"), systemImage: "arrow.up.right.square")
                        }

                        Button {
                            showContact = true
                        } label: {
                            Label(l10n.t("settings.contact"), systemImage: "envelope")
                        }
                    }
                    .labelStyle(.titleAndIcon)

                    Text(l10n.t("settings.help_hint"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(22)
        .frame(width: 520)
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
        .alert(l10n.t("settings.contact_title"), isPresented: $showContact) {
            Button(l10n.t("settings.open_issues")) {
                manager.openIssuesPage()
            }
            Button(l10n.t("settings.copy_email")) {
                manager.copyContactEmail()
            }
            Button(l10n.t("common.confirm"), role: .cancel) {}
        } message: {
            Text(l10n.t("settings.contact_body"))
        }
    }
}

struct SettingsLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
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

            case .verifying:
                ProgressView()
                    .controlSize(.small)
                Text(l10n.t("download.verifying"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

            case .failed(let message):
                VStack(spacing: 12) {
                    Text(l10n.t("download.failed"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .frame(maxWidth: 320)

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
                        Button(l10n.t("download.copy_error")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message, forType: .string)
                        }
                        .controlSize(.small)
                        if manager.existingChromiumAvailable {
                            Button(l10n.t("download.use_existing")) {
                                manager.useExistingChromiumIfAvailable()
                            }
                            .controlSize(.small)
                        }
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
