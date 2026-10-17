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
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
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
        .frame(minWidth: 720, minHeight: 520)
        .task { await appState.loadLibrary() }
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
