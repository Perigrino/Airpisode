import SwiftUI
import UserNotifications

/// The app's top-level destinations, shown as items in the bottom dock.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, shows, movies, discover

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: return "Upcoming"
        case .shows: return "My Shows"
        case .movies: return "My Movies"
        case .discover: return "Discover"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "calendar"
        case .shows: return "tv"
        case .movies: return "film"
        case .discover: return "magnifyingglass"
        }
    }
}

/// The app's one permitted window size: a portrait column whose window and content are the
/// same width, so there are never grey margins beside the page.
enum WindowMetrics {
    static let width: CGFloat = 720
    static let height: CGFloat = 1180
}

@main
struct AirpisodeApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup("Airpisode") {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: WindowMetrics.width, height: WindowMetrics.height)
        .windowResizability(.contentSize)
        Settings {
            SettingsView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}

/// Set as UNUserNotificationCenter delegate so banners show even while the app is frontmost.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // An "always"-style system scroller reserves a gutter on the page's right edge, which both
        // shifted the content column off-centre and put a scroll line up at first paint. This app
        // therefore always scrollers overlay-style; the window sweep and the live-scroll observer
        // keep even that flash from drawing.
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
    }

    /// Closing the window only hides it: the process keeps running in the background so the
    /// hourly refresh and the alert scheduler stay alive overnight, and clicking the dock icon
    /// brings the window back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock clicks while the main window is merely hidden bring it back up.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows visible: Bool) -> Bool {
        if visible { return true }
        return BackgroundCloseIntercept.bringMainWindowBackIfNeeded() ? false : true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// Pins the main window to one fixed portrait size. SwiftUI's `windowResizability` and a content
/// `maxWidth` only express a *minimum* — an AppKit window can still be dragged past them, which
/// is what put grey margins on either side of the page. The window is therefore made
/// non-resizable and re-pinned every time it attaches, so a stale saved frame cannot widen it.
private final class PortraitWindow: NSView {
    private static var liveScrollSweep: (any NSObjectProtocol)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        Self.pin(window)
        // Sweep at attach too: the first page can already carry a scroller before viewWillDraw.
        Self.hideScrollbars(in: window?.contentView)
        Self.observeLiveScrollingIfNeeded()
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        // Re-swept on every layout pass: SwiftUI creates a fresh NSScrollView per page, and a
        // fresh page could briefly resurrect a scroller.
        Self.hideScrollbars(in: window?.contentView)
    }

    /// SwiftUI can re-enable a scroll view's scroller while a scroll is in flight, which draws a
    /// thumb for about a second. Sweeping again on the live-scroll notification keeps the thumb
    /// from ever getting a frame to draw.
    private static func observeLiveScrollingIfNeeded() {
        guard liveScrollSweep == nil else { return }
        liveScrollSweep = NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let scroll = note.object as? NSScrollView else { return }
            scroll.verticalScroller?.alphaValue = 0
            scroll.horizontalScroller?.alphaValue = 0
        }
    }

    /// Every NSScrollView gets its scrollers removed outright — scrolling itself is untouched.
    static func hideScrollbars(in view: NSView?) {
        guard let view else { return }
        if let scroll = view as? NSScrollView {
            scroll.verticalScroller?.alphaValue = 0
            scroll.horizontalScroller?.alphaValue = 0
            scroll.verticalScroller?.isHidden = true
            scroll.horizontalScroller?.isHidden = true
            scroll.hasVerticalScroller = false
            scroll.hasHorizontalScroller = false
            scroll.autohidesScrollers = true
        }
        view.subviews.forEach { hideScrollbars(in: $0) }
    }

    static func pin(_ window: NSWindow?) {
        guard let window else { return }
        let size = NSSize(width: WindowMetrics.width, height: WindowMetrics.height)
        window.styleMask.remove(.resizable)
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.minSize = size
        window.maxSize = size
        window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true)
        BackgroundCloseIntercept.install(on: window)
    }
}

/// Sits between SwiftUI and the window so a red-button or Cmd+W close only HIDES the window:
/// SwiftUI terminates the process when its last WindowGroup window actually closes, which
/// would take the background refresh and the alert scheduler with it. The original delegate is
/// preserved and everything it implements stays forwarded to it.
final class BackgroundCloseIntercept: NSObject, NSWindowDelegate {
    static private(set) var mainWindow: NSWindow?

    static private var proxies: [ObjectIdentifier: BackgroundCloseIntercept] = [:]

    static func install(on window: NSWindow?) {
        guard let window, !(window.delegate is BackgroundCloseIntercept) else { return }
        let proxy = BackgroundCloseIntercept(original: window.delegate)
        window.delegate = proxy
        proxies[ObjectIdentifier(window)] = proxy
        mainWindow = window
    }

    static func bringMainWindowBackIfNeeded() -> Bool {
        guard let main = mainWindow, !main.isVisible else { return false }
        main.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private let original: NSWindowDelegate?

    init(original: NSWindowDelegate?) {
        self.original = original
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide, never destroy: the window must keep existing for the app to run in the
        // background; a dock click later brings it back (see the AppDelegate's reopen hook).
        sender.orderOut(nil)
        return false
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        (original?.responds(to: aSelector) ?? false) ? original : nil
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = PortraitWindow()
        // The view can attach after this returns, and window-frame restoration can run after
        // that; re-pin and sweep again after the first page has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { PortraitWindow.pin(view.window) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            PortraitWindow.hideScrollbars(in: view.window?.contentView)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // SwiftUI re-creates scroll views when a page changes, so sweep on updates too.
        PortraitWindow.hideScrollbars(in: nsView.window?.contentView)
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var needsKey = !Secrets.hasKey
    @State private var dockVisible = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) { dockLayer }
                    // Reveal the dock only when the pointer reaches the bottom edge, so it never
                    // covers content you are reading or clicking.
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            let bottom = geo.size.height
                            if !dockVisible, point.y > bottom - 100 {
                                dockVisible = true
                            } else if dockVisible, point.y < bottom - 150 {
                                dockVisible = false
                            }
                        case .ended:
                            if dockVisible { dockVisible = false }
                        }
                    }
            }
        }
        // Fixed in both axes: an unbounded content height was what let the window be dragged
        // shorter, while AppKit alone could only see the width limit.
        .frame(width: WindowMetrics.width, height: WindowMetrics.height)
        .background(WindowConfigurator())
        .task {
            await appState.loadLibrary()
            // Keeps alerts fresh even after the window is closed (hourly passes).
            appState.startBackgroundRefresh()
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
    }

    /// Floating dock plus a small handle that hints where it lives while it is parked.
    private var dockLayer: some View {
        VStack(spacing: 8) {
            DockBar(selection: $appState.selectedSection)
                .opacity(dockVisible ? 1 : 0)
                .offset(y: dockVisible ? 0 : 36)
                .allowsHitTesting(dockVisible)
            Capsule()
                .fill(.white.opacity(dockVisible ? 0 : 0.22))
                .frame(width: 46, height: 5)
        }
        .padding(.bottom, 10)
        .animation(Motion.smooth, value: dockVisible)
    }

    @ViewBuilder
    private var content: some View {
        switch appState.selectedSection ?? .dashboard {
        case .dashboard: DashboardView()
        case .shows: MyShowsView()
        case .movies: MyMoviesView()
        case .discover: DiscoverView()
        }
    }
}
