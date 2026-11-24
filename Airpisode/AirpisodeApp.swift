import SwiftUI
import UserNotifications

/// The app's top-level destinations, shown as sidebar items.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, shows, movies, diary, discover

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: return "To Watch"
        case .shows: return "Shows"
        case .movies: return "Movies"
        case .diary: return "Diary"
        case .discover: return "Discover"
        }
    }

    var title: String {
        switch self {
        case .dashboard: return "To Watch"
        case .shows: return "Shows"
        case .movies: return "Movies"
        case .diary: return "Diary"
        case .discover: return "Discover"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "checklist"
        case .shows: return "tv"
        case .movies: return "film"
        case .diary: return "clock.arrow.circlepath"
        case .discover: return "magnifyingglass"
        }
    }
}

@main
struct AirpisodeApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var updater = SparkleUpdater()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Airpisode", id: "main") {
            RootView()
                .environmentObject(appState)
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()

            CommandGroup(after: .newItem) {
                Button("Find Something to Track…") {
                    appState.selectedSection = .discover
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Refresh Releases") {
                    Task { await appState.runFullRefresh(force: true) }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.isRefreshing)
            }

            CommandMenu("Go") {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.label) {
                        appState.selectedSection = section
                    }
                    .keyboardShortcut(
                        KeyEquivalent(Character(String(index + 1))),
                        modifiers: .command
                    )
                }
            }

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(!updater.canCheckForUpdates)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(updater)
        }

        MenuBarExtra {
            MenuBarWatchList()
                .environmentObject(appState)
        } label: {
            Image(systemName: "bell")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Forwards notification action taps from the UN delegate to AppState. AppDelegate must own
/// the single UNUserNotificationCenter delegate, so the app state installs itself here
/// instead of becoming a second delegate.
protocol NotificationActionHandling: AnyObject {
    @MainActor
    func handleNotificationAction(identifier: String, titleID: String, kind: String, key: String?)
}

/// Set as UNUserNotificationCenter delegate so banners show even while the app is frontmost.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Action handlers install themselves from `AppState.init`; a weak static pairs with the
    /// singleton UN delegate slot above.
    static weak var actionHandler: NotificationActionHandling?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // Banner buttons (Mark watched / Mute) never appear unless the categories are
        // registered once at launch, before any alert schedules.
        NotificationScheduler.registerAlertCategories()
    }

    /// Closing the window keeps the process (and its hourly refresh and alert scheduler)
    /// alive. Clicking the Dock icon brings a window back through the standard reopen path.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Closing the window keeps refreshes and alerts running. Clicking the Dock icon (or
    /// choosing Open Airpisode from the menu bar) brings the same window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A closed window is kept alive (see MainWindowKeeper), so bring it back when the
        // Dock icon or a notification activates the app.
        Self.showMainWindow()
    }

    @MainActor
    @discardableResult
    static func showMainWindow() -> Bool {
        let window = MainWindowKeeper.mainWindow ?? NSApp.windows.first(where: {
            // The library window is a normal-level AppKitWindow; status-bar windows are not.
            $0.level == .normal && !($0 is NSPanel) && $0.canBecomeKey
        })
        guard let window else { return false }
        // Reopening must never leave two copy windows on screen.
        for other in NSApp.windows where other !== window && other.level == .normal && !(other is NSPanel) && other.isVisible {
            other.orderOut(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        // SwiftUI's WindowGroup may add a replacement window just after reopen; keep
        // exactly one library window on screen and out of the Window menu.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            for other in NSApp.windows
            where other !== window && other.level == .normal && !(other is NSPanel) {
                other.isExcludedFromWindowsMenu = true
                other.orderOut(nil)
            }
        }
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// The one delegate slot also receives button taps on banners. An ordinary banner tap is
    /// left alone (the system opens the window); Mark watched / Mute forward to AppState.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard response.actionIdentifier != UNNotificationDefaultActionIdentifier else { return }
        let info = response.notification.request.content.userInfo
        // The delegate call is synchronous but AppState is main-actor isolated; hop over.
        let identifier = response.actionIdentifier
        let titleID = info["titleID"] as? String ?? ""
        let kind = info["kind"] as? String ?? ""
        let key = info["key"] as? String
        let handler = Self.actionHandler
        Task { @MainActor in
            handler?.handleNotificationAction(identifier: identifier, titleID: titleID, kind: kind, key: key)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var needsKey = !Secrets.hasKey
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $appState.selectedSection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 212, max: 280)
        } detail: {
            detail
                .navigationTitle(currentSection.title)
                .navigationSubtitle(currentSubtitle)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.accentFill)
        .frame(
            minWidth: 880, idealWidth: 1120, maxWidth: .infinity,
            minHeight: 620, idealHeight: 760, maxHeight: .infinity
        )
        .task {
            await appState.loadLibrary()
            // Keeps alerts fresh even after the window is closed (hourly passes).
            appState.startBackgroundRefresh()
            // Minute-level reconcile: alerts are re-planned as their lead windows open, so a
            // banner never waits for a manual refresh.
            appState.startAlertReconciler()
            // Launch is the one time a full pass is expected without pressing Refresh.
            if Secrets.hasKey {
                await appState.refreshOnLaunch()
            }
        }
        .sheet(isPresented: $needsKey) {
            WelcomeView(
                onDone: {
                    needsKey = false
                    Task { await appState.runFullRefresh() }
                },
                onSkip: { needsKey = false }
            )
        }
        .background(WindowKeeperInstaller())
    }

    private var currentSection: AppSection {
        appState.selectedSection ?? .dashboard
    }

    private var currentSubtitle: String {
        switch currentSection {
        case .dashboard:
            return "Everything airing soon and waiting for you"
        case .shows:
            let count = appState.library.entries.filter { $0.mediaType == .tv }.count
            return count == 1 ? "1 tracked show" : "\(count) tracked shows"
        case .movies:
            let count = appState.library.entries.filter { $0.mediaType == .movie }.count
            return count == 1 ? "1 tracked movie" : "\(count) tracked movies"
        case .diary:
            return "What you have watched"
        case .discover:
            return "Search TMDB and add something new"
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch currentSection {
        case .dashboard: DashboardView()
        case .shows: MyShowsView()
        case .movies: MyMoviesView()
        case .diary: DiaryView()
        case .discover: DiscoverView()
        }
    }
}

/// Airpisode is a menu-bar app that also has one library window. Closing that window hides
/// it instead of destroying it, so the Dock icon, the menu-bar popover, and a notification
/// tap can all bring back the same window with its scroll position and expanded row intact.
/// Without this, SwiftUI's WindowGroup leaves a running app windowless and refuses to
/// recreate the window on reopen.
@MainActor
final class MainWindowKeeper: NSObject, NSWindowDelegate {
    static let shared = MainWindowKeeper()
    /// The window the app should restore on reopen. Weak so a closed scene can go away.
    static weak var mainWindow: NSWindow?
    private weak var originalDelegate: NSWindowDelegate?

    func attach(to window: NSWindow) {
        guard window.delegate !== self else { return }
        originalDelegate = window.delegate
        window.delegate = self
        Self.mainWindow = window
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (originalDelegate?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if originalDelegate?.responds(to: selector) == true {
            return originalDelegate
        }
        return super.forwardingTarget(for: selector)
    }
}

private struct WindowKeeperInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                MainWindowKeeper.shared.attach(to: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
