import SwiftUI
import UserNotifications

enum SidebarSection: String, Hashable {
    case dashboard, shows, movies, discover
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

    var body: some View {
        NavigationView {
            List(selection: $appState.selectedSection) {
                link(.dashboard, "Upcoming", "calendar")
                link(.shows, "My Shows", "tv")
                link(.movies, "My Movies", "film")
                link(.discover, "Discover", "magnifyingglass")
            }
            .listStyle(.sidebar)
            .frame(minWidth: 190)
            DashboardView()
        }
        .task { await appState.loadLibrary() }
        .sheet(isPresented: $needsKey) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to Airpisode")
                    .font(.title2).bold()
                APIKeyForm {
                    needsKey = false
                    Task { await appState.runFullRefresh() }
                }
            }
            .padding(24)
            .frame(width: 420)
        }
    }

    private func link(_ section: SidebarSection, _ title: String, _ icon: String) -> some View {
        NavigationLink(tag: section, selection: $appState.selectedSection) {
            destination(for: section)
        } label: {
            Label(title, systemImage: icon)
        }
    }

    @ViewBuilder
    private func destination(for section: SidebarSection) -> some View {
        switch section {
        case .dashboard: DashboardView()
        case .shows: MyShowsView()
        case .movies: MyMoviesView()
        case .discover: DiscoverView()
        }
    }
}
