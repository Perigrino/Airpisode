import SwiftUI

enum SidebarSection: String, Hashable {
    case dashboard, shows, movies, discover
}

@main
struct AirpisodeApp: App {
    @StateObject private var appState = AppState()
    var body: some Scene {
        WindowGroup("Airpisode") {
            RootView().environmentObject(appState)
        }
        Settings { SettingsView().environmentObject(appState) }
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
