import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var permissionDenied = false

    private var prefs: NotificationPreferences { appState.library.preferences }

    private var regionOptions: [(code: String, title: String)] {
        RegionCatalog.options(including: ConfigStore.defaultRegion)
    }

    var body: some View {
        Form {
            Section("TMDB API Key") {
                APIKeyForm { Task { await appState.runFullRefresh() } }
                TMDBKeyHelp()
            }

            Section("Region") {
                Picker("Release region", selection: Binding(
                    get: { ConfigStore.defaultRegion },
                    set: { code in
                        ConfigStore.setDefaultRegion(code)
                        // Relabel stored releases and re-check for new ones right away.
                        Task { await appState.runFullRefresh() }
                    }
                )) {
                    ForEach(regionOptions, id: \.code) { option in
                        Text(option.title).tag(option.code)
                    }
                }

                Text("Release dates and streaming availability follow this country.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                if prefs.permissionRequested && permissionDenied {
                    Label("Notifications are denied. Enable them in System Settings → Notifications → Airpisode.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Button(prefs.permissionRequested ? "Re-request Notification Permission" : "Enable Notifications") {
                    Task {
                        let center = UNUserNotificationCenter.current()
                        _ = try? await center.requestAuthorization(options: [.alert, .sound])
                        let settings = await center.notificationSettings()
                        appState.updateNotificationPreferences { $0.permissionRequested = true }
                        permissionDenied = settings.authorizationStatus == .denied
                    }
                }

                Picker("Pre-release alert", selection: Binding(
                    get: { prefs.preAlertHours ?? 0 },
                    set: { hours in appState.updateNotificationPreferences { $0.preAlertHours = hours == 0 ? nil : hours } }
                )) {
                    Text("Off").tag(0)
                    Text("1 hour before").tag(1)
                    Text("24 hours before").tag(24)
                    Text("48 hours before").tag(48)
                }

                Toggle("Alert 15 minutes before (timed releases)", isOn: Binding(
                    get: { prefs.imminentAlertMinutes != nil },
                    set: { on in appState.updateNotificationPreferences { $0.imminentAlertMinutes = on ? 15 : nil } }
                ))

                Text("Date-only releases (most TV episodes) never get time-based alerts — Airpisode won't invent a release time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                HStack(spacing: 10) {
                    Image("tmdb-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 20)
                    Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            permissionDenied = prefs.permissionRequested && settings.authorizationStatus == .denied
        }
    }
}
