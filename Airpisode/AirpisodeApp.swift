import SwiftUI

@main
struct AirpisodeApp: App {
    @StateObject private var appState = AppState()
    var body: some Scene {
        WindowGroup("Airpisode") {
            RootView().environmentObject(appState)
        }
        Settings { SettingsView() }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationView {
            List {
                NavigationLink("Dashboard") { DashboardView() }
                NavigationLink("My Shows") { MyShowsView() }
                NavigationLink("My Movies") { MyMoviesView() }
                NavigationLink("Discover") { DiscoverView() }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
            DashboardView()
        }
        .task { await appState.loadLibrary() }
    }
}
