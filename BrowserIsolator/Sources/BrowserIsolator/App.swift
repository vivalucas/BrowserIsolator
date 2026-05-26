import SwiftUI
import Sparkle

private let deleteConfirmationKeyword = "Delete"

@main
struct BrowserIsolatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var manager = BrowserManager()
    @StateObject private var localization = Localization()
    @StateObject private var updater = SparkleUpdater()
    @AppStorage("AppAppearance") private var appAppearance: String = AppAppearance.system.rawValue

    private var preferredColorScheme: ColorScheme? {
        AppAppearance(rawValue: appAppearance)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            MainView(manager: manager, l10n: localization, updater: updater)
                .frame(minWidth: 680, idealWidth: 760, minHeight: 420)
                .background(WindowFrameAutosaveView(name: "BrowserIsolator.mainWindow"))
                .preferredColorScheme(preferredColorScheme)
                .onAppear {
                    applyAppAppearance(AppAppearance(rawValue: appAppearance) ?? .system)
                }
                .onChange(of: appAppearance) { newValue in
                    applyAppAppearance(AppAppearance(rawValue: newValue) ?? .system)
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 760, height: 520)

        MenuBarExtra("", systemImage: manager.runningProfiles.isEmpty ? "macwindow.on.rectangle" : "macwindow.badge.plus") {
            MenuBarView(manager: manager, l10n: localization, updater: updater)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct WindowFrameAutosaveView: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            view.window?.setFrameAutosaveName(name)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.setFrameAutosaveName(name)
        }
    }
}

@MainActor
final class SparkleUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    override init() {
        super.init()
        _ = controller
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        closeHostWindowsForUpdateRelaunch()
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        closeHostWindowsForUpdateRelaunch()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            installHandler()
        }
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        closeHostWindowsForUpdateRelaunch()
    }

    private func closeHostWindowsForUpdateRelaunch() {
        for window in NSApp.windows where !isSparkleWindow(window) && !(window is NSPanel) {
            if let sheet = window.attachedSheet, !isSparkleWindow(sheet) {
                window.endSheet(sheet)
                sheet.close()
            }
            window.close()
        }
    }

    private func isSparkleWindow(_ window: NSWindow) -> Bool {
        let className = NSStringFromClass(type(of: window))
        return className.contains("SU") || className.contains("SPU") || className.contains("Sparkle")
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let browserIsolatorSettingsWindow = NSUserInterfaceItemIdentifier("BrowserIsolator.settingsWindow")
}

@MainActor
private func isBrowserIsolatorMainWindow(_ window: NSWindow) -> Bool {
    !(window is NSPanel) && window.identifier != .browserIsolatorSettingsWindow
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        schedulePendingOpenURLFlush(attemptsRemaining: 20)
        showMainWindowIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !NSApp.windows.contains(where: { isBrowserIsolatorMainWindow($0) && $0.isVisible }) else { return }
        showMainWindowIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindowIfNeeded()
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            if let manager = BrowserManager.shared {
                manager.openExternalURLs(urls)
            } else {
                pendingOpenURLs.append(contentsOf: urls)
                schedulePendingOpenURLFlush(attemptsRemaining: 20)
            }
        }
    }

    @MainActor
    private func flushPendingOpenURLs() {
        guard !pendingOpenURLs.isEmpty,
              let manager = BrowserManager.shared else { return }
        manager.openExternalURLs(pendingOpenURLs)
        pendingOpenURLs.removeAll()
    }

    private func showMainWindowIfNeeded() {
        Task { @MainActor in
            for attempt in 0..<30 {
                try? await Task.sleep(nanoseconds: attempt == 0 ? 200_000_000 : 100_000_000)
                if let main = NSApp.windows.first(where: isBrowserIsolatorMainWindow) {
                    NSApp.activate(ignoringOtherApps: true)
                    main.orderFrontRegardless()
                    main.makeKeyAndOrderFront(nil)
                    return
                }
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func schedulePendingOpenURLFlush(attemptsRemaining: Int) {
        Task { @MainActor in
            if BrowserManager.shared != nil {
                self.flushPendingOpenURLs()
                return
            }

            guard attemptsRemaining > 0 else { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.schedulePendingOpenURLFlush(attemptsRemaining: attemptsRemaining - 1)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        BrowserManager.shared?.stopAllAndWait()
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearanceName: NSAppearance.Name? {
        switch self {
        case .system: return nil
        case .light: return .aqua
        case .dark: return .darkAqua
        }
    }
}

@MainActor
private func applyAppAppearance(_ appearance: AppAppearance) {
    let nsAppearance = appearance.nsAppearanceName.flatMap(NSAppearance.init(named:))
    NSApp.appearance = nsAppearance
    for window in NSApp.windows {
        window.appearance = nsAppearance
        window.contentView?.appearance = nsAppearance
    }
}

// MARK: - 主界面

struct MainView: View {
    @ObservedObject var manager: BrowserManager
    @ObservedObject var l10n: Localization
    @ObservedObject var updater: SparkleUpdater
    @State private var showRenameSheet: Bool = false
    @State private var renameTarget: Profile?
    @State private var renameText: String = ""
    @State private var showNoteSheet: Bool = false
    @State private var noteTarget: Profile?
    @State private var noteText: String = ""
    @State private var showDeleteConfirm: Profile?
    @State private var deleteConfirmText: String = ""
    @State private var selectedProfileID: String?
    @State private var settingsWindowController: NSWindowController?
    @AppStorage("MainSidebarWidth") private var mainSidebarWidth: Double = 360
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
        Group {
            if !manager.chromiumReady {
                DownloadView(manager: manager, l10n: l10n)
            } else {
                profileList
            }
        }
        .alert(item: $manager.configLoadAlert) { alert in
            Alert(
                title: Text(l10n.t("config_load.title")),
                message: Text(alert.backupPath.map { l10n.format("config_load.message_with_backup", $0) } ?? l10n.t("config_load.message")),
                dismissButton: .default(Text(l10n.t("common.confirm")))
            )
        }
        .alert(item: $manager.configSaveAlert) { alert in
            Alert(
                title: Text(l10n.t("config_save.title")),
                message: Text(alert.message),
                dismissButton: .default(Text(l10n.t("common.confirm")))
            )
        }
        .externalLinkAlert(manager: manager, l10n: l10n)
    }

    @ViewBuilder
    private var profileList: some View {
        HSplitView {
            ScrollView {
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
                    .frame(minHeight: 360)
                } else {
                    LazyVStack(spacing: 6) {
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
                                    selectedProfileID = profile.folder
                                    if manager.runningProfiles.contains(profile.folder) {
                                        manager.stopProfile(profile)
                                    } else {
                                        manager.startProfile(profile)
                                    }
                                },
                                onSelect: {
                                    selectedProfileID = profile.folder
                                },
                                onDoubleClick: {
                                    selectedProfileID = profile.folder
                                    if !manager.runningProfiles.contains(profile.folder),
                                       !manager.startingProfiles.contains(profile.folder),
                                       !manager.stoppingProfiles.contains(profile.folder) {
                                        manager.startProfile(profile)
                                    }
                                }
                            )
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button(l10n.t("context.rename")) {
                                    renameTarget = profile
                                    renameText = profile.displayName
                                    showRenameSheet = true
                                }
                                if !manager.runningProfiles.contains(profile.folder),
                                   !manager.startingProfiles.contains(profile.folder),
                                   !manager.stoppingProfiles.contains(profile.folder) {
                                    Button(l10n.t("context.note")) {
                                        noteTarget = profile
                                        noteText = profile.note
                                        showNoteSheet = true
                                    }
                                }
                                if !manager.runningProfiles.contains(profile.folder),
                                   !manager.startingProfiles.contains(profile.folder),
                                   !manager.stoppingProfiles.contains(profile.folder) {
                                    Divider()
                                    Button(l10n.t("context.delete"), role: .destructive) {
                                        showDeleteConfirm = profile
                                        deleteConfirmText = ""
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
            }
            .frame(minWidth: 340, idealWidth: CGFloat(mainSidebarWidth))
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: MainSidebarWidthPreferenceKey.self, value: proxy.size.width)
                }
            }

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
                onNote: { profile in
                    noteTarget = profile
                    noteText = profile.note
                    showNoteSheet = true
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
        .onPreferenceChange(MainSidebarWidthPreferenceKey.self) { width in
            let clampedWidth = Double(min(max(width, 340), 560))
            if abs(mainSidebarWidth - clampedWidth) > 1 {
                mainSidebarWidth = clampedWidth
            }
        }
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
                .buttonStyle(.bordered)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    openSettingsWindow()
                } label: {
                    Label(l10n.t("settings.title"), systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
            }

            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    manager.stopAll()
                } label: {
                    ToolbarSemanticLabel(
                        title: l10n.t("toolbar.stop_all"),
                        systemImage: "stop.fill",
                        kind: .destructive
                    )
                }
                .disabled(manager.runningProfiles.isEmpty && manager.stoppingProfiles.isEmpty)
                .buttonStyle(ToolbarSemanticButtonStyle(kind: .destructive))
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
        .sheet(isPresented: $showNoteSheet) {
            ProfileTextSheet(
                title: l10n.t("context.note"),
                hint: l10n.t("note.hint"),
                placeholder: l10n.t("note.placeholder"),
                maxLength: 120,
                text: $noteText,
                l10n: l10n,
                onConfirm: {
                    if let target = noteTarget {
                        manager.updateNote(for: target, newNote: noteText)
                    }
                    noteTarget = nil
                    showNoteSheet = false
                },
                onCancel: {
                    noteTarget = nil
                    showNoteSheet = false
                }
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
                   deleteConfirmText.trimmingCharacters(in: .whitespacesAndNewlines) == deleteConfirmationKeyword {
                    manager.moveProfileToTrash(p)
                }
                showDeleteConfirm = nil
                deleteConfirmText = ""
            }
            .disabled(
                deleteConfirmText.trimmingCharacters(in: .whitespacesAndNewlines) != deleteConfirmationKeyword
            )
        } message: {
            if let p = showDeleteConfirm {
                Text(l10n.format(
                    "delete.message",
                    profileTitle(p, l10n: l10n),
                    ProfileRow.sizeFormatter.string(fromByteCount: manager.profileSizes[p.folder] ?? 0),
                    deleteConfirmationKeyword
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

    private func openSettingsWindow() {
        if let window = settingsWindowController?.window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 690),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let rootView = SettingsView(
            manager: manager,
            l10n: l10n,
            updater: updater,
            showAdvancedDetails: $showAdvancedDetails,
            onClose: { [weak window] in
                window?.close()
            }
        )
        window.contentView = NSHostingView(rootView: rootView)
        window.identifier = .browserIsolatorSettingsWindow
        window.title = l10n.t("settings.title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        applyAppAppearance(AppAppearance(rawValue: UserDefaults.standard.string(forKey: "AppAppearance") ?? "") ?? .system)
        window.appearance = NSApp.appearance
        window.contentView?.appearance = NSApp.appearance
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct ToolbarSemanticLabel: View {
    let title: String
    let systemImage: String
    let kind: ToolbarSemanticButtonStyle.Kind
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(iconColor)
            Text(title)
                .foregroundStyle(textColor)
        }
    }

    private var iconColor: Color {
        guard isEnabled else { return disabledColor }
        switch kind {
        case .primary:
            return Color(nsColor: .systemTeal)
        case .destructive:
            return Color(nsColor: .systemRed)
        }
    }

    private var textColor: Color {
        isEnabled ? Color.primary : disabledColor
    }

    private var disabledColor: Color {
        Color(nsColor: .disabledControlTextColor)
    }
}

private struct MainSidebarWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 360

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ToolbarSemanticButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case destructive
    }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled
    private let cornerRadius: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minHeight: 28)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var enabledColor: Color {
        switch kind {
        case .primary:
            return Color(nsColor: .systemTeal)
        case .destructive:
            return Color(nsColor: .systemRed)
        }
    }

    private var disabledColor: Color {
        Color(nsColor: .disabledControlTextColor)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else {
            return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(isPressed ? 0.72 : 0.46)
    }

    private var borderColor: Color {
        guard isEnabled else {
            return disabledColor.opacity(0.18)
        }
        return enabledColor.opacity(0.82)
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
    let onSelect: () -> Void
    let onDoubleClick: () -> Void

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
                .fill(isSelected ? selectionTint.opacity(0.13) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? selectionTint.opacity(0.28) : Color.clear, lineWidth: 1)
        }
        .background {
            RowClickCatcher(onSingleClick: onSelect, onDoubleClick: onDoubleClick)
        }
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}

private struct RowClickCatcher: NSViewRepresentable {
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> ClickCatcherView {
        let view = ClickCatcherView()
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: ClickCatcherView, context: Context) {
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
    }
}

private final class ClickCatcherView: NSView {
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        switch event.clickCount {
        case 1:
            onSingleClick?()
        case 2:
            onDoubleClick?()
        default:
            onSingleClick?()
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
    let onNote: (Profile) -> Void
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
                        Button(l10n.t("context.note")) { onNote(profile) }
                    }

                    if !profile.note.isEmpty {
                        Text(profile.note)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
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
                    DetailLine(label: l10n.t("details.run_mode"), value: runModeText(for: profile))
                    DetailLine(label: l10n.t("details.folder"), value: profile.folder)
                    DetailLine(label: l10n.t("details.profile_path"), value: profilePath(profile).path)
                    if let size = manager.profileSizes[profile.folder] {
                        DetailLine(label: l10n.t("settings.data"), value: ProfileRow.sizeFormatter.string(fromByteCount: size))
                    }
                }

                if showAdvancedDetails {
                    InspectorSection(title: l10n.t("inspector.advanced")) {
                        if profile.fingerprintEnabled {
                            let values = fingerprintValues(for: profile)
                            DetailLine(label: l10n.t("details.cpu"), value: "\(values.cores)")
                            DetailLine(label: l10n.t("details.memory"), value: "\(values.memory) GB")
                        }
                        if let debugPort = manager.debugPort(for: profile) {
                            DetailLine(label: l10n.t("details.port"), value: "\(debugPort)")
                        }
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
                        .disabled(isRunning(profile) || isStarting(profile) || isStopping(profile))
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

    private func runModeText(for profile: Profile) -> String {
        profile.fingerprintEnabled ? l10n.t("settings.variation_mode") : l10n.t("settings.basic_mode")
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

struct ProfileTextSheet: View {
    let title: String
    let hint: String
    let placeholder: String
    let maxLength: Int?
    @Binding var text: String
    @ObservedObject var l10n: Localization
    @FocusState private var isFocused: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(title).font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .focused($isFocused)
                    .onChange(of: text) { newValue in
                        guard let maxLength, newValue.count > maxLength else { return }
                        text = String(newValue.prefix(maxLength))
                    }
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
        .onAppear {
            isFocused = true
            if let maxLength, text.count > maxLength {
                text = String(text.prefix(maxLength))
            }
        }
    }
}

// MARK: - 菜单栏视图

struct MenuBarView: View {
    @ObservedObject var manager: BrowserManager
    @ObservedObject var l10n: Localization
    @ObservedObject var updater: SparkleUpdater

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
            Button(l10n.t("toolbar.stop_all")) { manager.stopAll() }
                .disabled(manager.runningProfiles.isEmpty && manager.stoppingProfiles.isEmpty)

            Divider()
            Button(l10n.t("menu.open_panel")) {
                NSApp.activate(ignoringOtherApps: true)
                if let main = NSApp.windows.first(where: isBrowserIsolatorMainWindow) {
                    main.makeKeyAndOrderFront(nil)
                }
            }
            Divider()
            LanguageMenu(l10n: l10n)
            Divider()
            Button(l10n.t("menu.check_updates")) { updater.checkForUpdates() }
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
        .externalLinkAlert(manager: manager, l10n: l10n)
    }
}

private extension View {
    func externalLinkAlert(manager: BrowserManager, l10n: Localization) -> some View {
        alert(item: Binding(
            get: { manager.externalLinkAlert },
            set: { manager.externalLinkAlert = $0 }
        )) { alert in
            switch alert.kind {
            case .link(let url):
                return Alert(
                    title: Text(l10n.t("external_link.title")),
                    message: Text(l10n.format("external_link.message", url.absoluteString)),
                    primaryButton: .default(Text(l10n.t("external_link.copy"))) {
                        manager.copyExternalLink(url)
                    },
                    secondaryButton: .cancel(Text(l10n.t("common.confirm")))
                )
            case .noAvailableProfile(let url):
                let message = url.map { l10n.format("external_link.no_profile_message", $0.absoluteString) } ?? l10n.t("external_link.no_profile_message")
                return Alert(
                    title: Text(l10n.t("external_link.title")),
                    message: Text(message),
                    primaryButton: .default(Text(l10n.t("menu.open_panel"))) {
                        NSApp.activate(ignoringOtherApps: true)
                        if let main = NSApp.windows.first(where: isBrowserIsolatorMainWindow) {
                            main.orderFrontRegardless()
                            main.makeKeyAndOrderFront(nil)
                        }
                    },
                    secondaryButton: url.map { copyURL in
                        .default(Text(l10n.t("external_link.copy"))) {
                            manager.copyExternalLink(copyURL)
                        }
                    } ?? .cancel(Text(l10n.t("common.confirm")))
                )
            }
        }
    }
}

// MARK: - 设置

struct SettingsView: View {
    @ObservedObject var manager: BrowserManager
    @ObservedObject var l10n: Localization
    @ObservedObject var updater: SparkleUpdater
    @Binding var showAdvancedDetails: Bool
    let onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("AppAppearance") private var appAppearance: String = AppAppearance.system.rawValue
    @AppStorage("DefaultOpenProfileFolder") private var defaultOpenProfileFolder: String = ""
    @State private var showFingerprintManager = false

    private var fingerprintEnabledCount: Int {
        manager.config.profiles.filter(\.fingerprintEnabled).count
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsSection(title: l10n.t("settings.browser"), systemImage: "globe") {
                        SettingsLine(label: l10n.t("settings.chrome_status"), value: manager.chromiumReady ? l10n.t("settings.ready") : l10n.t("settings.not_installed"))
                        SettingsDivider()
                        SettingsLine(label: l10n.t("settings.chrome_version"), value: manager.chromeVersionText ?? l10n.t("settings.unknown"))
                        SettingsDivider()
                        SettingsButtonRow {
                            Button(l10n.t("settings.open_chrome_folder")) { manager.openChromiumFolder() }
                            Button(l10n.t("settings.redownload_chrome")) { manager.reinstallChromium() }
                                .disabled(!manager.runningProfiles.isEmpty || !manager.stoppingProfiles.isEmpty || !manager.startingProfiles.isEmpty)
                        }
                    }

                    SettingsSection(title: l10n.t("settings.data"), systemImage: "folder") {
                        SettingsLine(label: l10n.t("settings.data_path"), value: AppPaths.supportDir.path)
                        SettingsDivider()
                        SettingsButtonRow {
                            Button(l10n.t("settings.open_data_folder")) { manager.openSupportFolder() }
                            Button(l10n.t("settings.open_profiles_folder")) { manager.openProfilesFolder() }
                            Button(l10n.t("settings.copy_path")) { manager.copySupportPath() }
                        }
                    }

                    SettingsSection(title: l10n.t("settings.external_links"), systemImage: "link") {
                        SettingsControlRow(label: l10n.t("settings.open_to")) {
                            if manager.config.profiles.isEmpty {
                                Text(l10n.t("settings.unknown"))
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("", selection: $defaultOpenProfileFolder) {
                                    ForEach(manager.config.profiles) { profile in
                                        Text(profileTitle(profile, l10n: l10n)).tag(profile.folder)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 230, alignment: .leading)
                            }
                        }
                        SettingsDivider()
                        SettingsButtonRow {
                            Button {
                                manager.setAsDefaultBrowser()
                            } label: {
                                Label(l10n.t("settings.set_default_browser"), systemImage: "safari")
                            }
                                .buttonStyle(.borderedProminent)
                                .disabled(manager.config.profiles.isEmpty)
                        }
                    }

                    SettingsSection(title: l10n.t("settings.fingerprint_mode"), systemImage: "cpu") {
                        Text(l10n.t("settings.fingerprint_hint"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 7)
                        Divider()
                        SettingsLine(
                            label: l10n.t("settings.fingerprint_profiles"),
                            value: l10n.format("settings.fingerprint_summary", fingerprintEnabledCount, manager.config.profiles.count)
                        )
                        SettingsDivider()
                        SettingsButtonRow {
                            Button {
                                showFingerprintManager = true
                            } label: {
                                Label(l10n.t("settings.fingerprint_manage"), systemImage: "slider.horizontal.3")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    SettingsSection(title: l10n.t("settings.preferences"), systemImage: "slider.horizontal.3") {
                        SettingsControlRow(label: l10n.t("language")) {
                            LanguageMenu(l10n: l10n)
                        }
                        SettingsDivider()

                        SettingsControlRow(label: l10n.t("settings.appearance")) {
                            Picker("", selection: $appAppearance) {
                                ForEach(AppAppearance.allCases) { appearance in
                                    Text(appearanceTitle(appearance)).tag(appearance.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 230)
                        }
                        SettingsDivider()

                        SettingsToggleRow(label: l10n.t("settings.show_advanced"), isOn: $showAdvancedDetails)
                    }

                    SettingsSection(title: l10n.t("settings.about_support"), systemImage: "questionmark.circle") {
                        SettingsLine(label: l10n.t("settings.app_version"), value: manager.currentVersion)
                        SettingsDivider()
                        SettingsButtonRow {
                            Button {
                                updater.checkForUpdates()
                            } label: {
                                Label(l10n.t("menu.check_updates"), systemImage: "arrow.down.circle")
                            }

                            Button {
                                manager.openReleasesPage()
                            } label: {
                                Label(l10n.t("settings.view_releases"), systemImage: "arrow.up.right.square")
                            }
                        }
                        .labelStyle(.titleAndIcon)
                        SettingsDivider()

                        SettingsLine(label: l10n.t("settings.author"), value: "Lucas")
                        SettingsDivider()
                        SettingsLine(label: l10n.t("settings.email"), value: manager.contactEmail)
                        SettingsButtonRow {
                            Button {
                                manager.copyContactEmail()
                            } label: {
                                Label(l10n.t("settings.copy_email"), systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                        SettingsDivider()

                        SettingsControlRow(label: l10n.t("settings.feedback_group")) {
                            Button {
                                manager.openIssuesPage()
                            } label: {
                                Label(l10n.t("settings.open_issues"), systemImage: "bubble.left.and.bubble.right")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 22)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 620, height: 690)
        .preferredColorScheme(AppAppearance(rawValue: appAppearance)?.colorScheme)
        .onAppear {
            applyAppAppearance(AppAppearance(rawValue: appAppearance) ?? .system)
        }
        .onChange(of: appAppearance) { newValue in
            applyAppAppearance(AppAppearance(rawValue: newValue) ?? .system)
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
        .onAppear(perform: normalizeDefaultOpenProfileFolder)
        .onChange(of: manager.config.profiles.map(\.folder)) { _ in
            normalizeDefaultOpenProfileFolder()
        }
        .sheet(isPresented: $showFingerprintManager) {
            FingerprintModeManagerView(manager: manager, l10n: l10n)
                .preferredColorScheme(AppAppearance(rawValue: appAppearance)?.colorScheme)
        }
    }

    private func normalizeDefaultOpenProfileFolder() {
        guard !manager.config.profiles.isEmpty else {
            if !defaultOpenProfileFolder.isEmpty {
                defaultOpenProfileFolder = ""
            }
            return
        }
        if manager.config.profiles.contains(where: { $0.folder == defaultOpenProfileFolder }) {
            return
        }
        defaultOpenProfileFolder = manager.config.profiles.first?.folder ?? ""
    }

    private var settingsHeader: some View {
        ZStack {
            Text(l10n.t("settings.title"))
                .font(.system(size: 14, weight: .semibold))
            HStack {
                settingsCloseButton
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var settingsCloseButton: some View {
        Button {
            if let onClose {
                onClose()
            } else {
                dismiss()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 13, height: 13)
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.black.opacity(0.58))
            }
            .frame(width: 22, height: 22)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(l10n.t("common.close"))
    }

    private func appearanceTitle(_ appearance: AppAppearance) -> String {
        switch appearance {
        case .system: return l10n.t("settings.appearance_system")
        case .light: return l10n.t("settings.appearance_light")
        case .dark: return l10n.t("settings.appearance_dark")
        }
    }
}

struct FingerprintModeManagerView: View {
    @ObservedObject var manager: BrowserManager
    @ObservedObject var l10n: Localization
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showEditableOnly = false

    private var searchedProfiles: [Profile] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return manager.config.profiles }
        return manager.config.profiles.filter {
            profileTitle($0, l10n: l10n).localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var filteredProfiles: [Profile] {
        searchedProfiles.filter { profile in
            !showEditableOnly || manager.canChangeFingerprintMode(for: profile)
        }
    }

    private var emptyMessage: String {
        if manager.config.profiles.isEmpty {
            return l10n.t("settings.fingerprint_empty_profiles")
        }
        if showEditableOnly && searchedProfiles.isEmpty == false && filteredProfiles.isEmpty {
            return l10n.t("settings.fingerprint_no_editable")
        }
        return l10n.t("settings.fingerprint_no_results")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(l10n.t("settings.fingerprint_manage_title"))
                    .font(.system(size: 16, weight: .semibold))

                Text(l10n.t("settings.fingerprint_manage_description"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(l10n.t("settings.fingerprint_search_placeholder"), text: $searchText)
                        .textFieldStyle(.plain)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }

                Toggle(isOn: $showEditableOnly) {
                    Text(l10n.t("settings.fingerprint_editable_only"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                if filteredProfiles.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                        Text(emptyMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(filteredProfiles.enumerated()), id: \.element.folder) { index, profile in
                            FingerprintModeRow(profile: profile, manager: manager, l10n: l10n)
                                .padding(.horizontal, 14)
                            if index < filteredProfiles.count - 1 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                        }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.46))
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    }
                    .padding(22)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button(l10n.t("common.close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(width: 560, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct FingerprintModeRow: View {
    let profile: Profile
    @ObservedObject var manager: BrowserManager
    @ObservedObject var l10n: Localization

    private var isLocked: Bool {
        !manager.canChangeFingerprintMode(for: profile)
    }

    private var fingerprintBinding: Binding<Bool> {
        Binding(
            get: {
                manager.config.profiles.first(where: { $0.folder == profile.folder })?.fingerprintEnabled ?? false
            },
            set: { newValue in
                manager.updateFingerprintEnabled(for: profile, isEnabled: newValue)
            }
        )
    }

    private var currentModeText: String {
        fingerprintBinding.wrappedValue ? l10n.t("settings.variation_mode") : l10n.t("settings.basic_mode")
    }

    private var stateText: String {
        if manager.startingProfiles.contains(profile.folder) {
            return l10n.t("settings.fingerprint_locked_starting")
        }
        if manager.runningProfiles.contains(profile.folder) {
            return l10n.t("settings.fingerprint_locked_running")
        }
        if manager.stoppingProfiles.contains(profile.folder) {
            return l10n.t("settings.fingerprint_locked_stopping")
        }
        return l10n.format("settings.fingerprint_editable_status", currentModeText)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profileTitle(profile, l10n: l10n))
                    .foregroundStyle(.primary)
                Text(stateText)
                    .font(.system(size: 11))
                    .foregroundStyle(isLocked ? .secondary : .tertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: fingerprintBinding)
                .labelsHidden()
                .disabled(isLocked)
        }
        .font(.system(size: 12))
        .frame(minHeight: 42)
        .help(l10n.t("settings.fingerprint_hint"))
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Label {
                Text(title)
            } icon: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 22, height: 22)
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 22, height: 22)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 118, alignment: .leading)
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.46))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
    }
}

struct SettingsControlRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)
            Spacer(minLength: 12)
            content
        }
        .font(.system(size: 12))
        .frame(minHeight: 32)
    }
}

struct SettingsToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .frame(minHeight: 32)
    }
}

struct SettingsButtonRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .controlSize(.small)
        .frame(minHeight: 32, alignment: .leading)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 118)
    }
}

struct SettingsLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .frame(minHeight: 32)
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
