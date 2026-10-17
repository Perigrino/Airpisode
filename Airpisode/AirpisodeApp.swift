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
            RootView().environmentObject(appState)
        }
        Settings { SettingsView().environmentObject(appState) }
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

    var body: some View {
        NavigationView {
            List(selection: $appState.selectedSection) {
                NavigationLink(tag: SidebarSection.dashboard, selection: $appState.selectedSection) {
                    DashboardView()
                } label: {
                    Text("Dashboard")
                }
                NavigationLink(tag: SidebarSection.shows, selection: $appState.selectedSection) {
                    MyShowsView()
                } label: {
                    Text("My Shows")
                }
                NavigationLink(tag: SidebarSection.movies, selection: $appState.selectedSection) {
                    MyMoviesView()
                } label: {
                    Text("My Movies")
                }
                NavigationLink(tag: SidebarSection.discover, selection: $appState.selectedSection) {
                    DiscoverView()
                } label: {
                    Text("Discover")
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
            DashboardView()
        }
        .task { await appState.loadLibrary() }
    }
}
