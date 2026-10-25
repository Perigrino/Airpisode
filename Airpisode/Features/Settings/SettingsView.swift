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
                Picker("Pre-release alert", selection: Binding(
                    get: { prefs.preAlertHours ?? 0 },
                    set: { hours in appState.updateNotificationPreferences { $0.preAlertHours = hours == 0 ? nil : hours } }
                )) {
                    Text("Off").tag(0)
                    Text("1 hour before").tag(1)
                    Text("24 hours before").tag(24)
                    Text("48 hours before").tag(48)
                }

                Toggle("Alert 15 minutes before (known air times)", isOn: Binding(
                    get: { prefs.imminentAlertMinutes != nil },
                    set: { on in appState.updateNotificationPreferences { $0.imminentAlertMinutes = on ? 15 : nil } }
                ))

                Toggle("Daily 9 AM lineup summary", isOn: Binding(
                    get: { prefs.digestEnabled },
                    set: { on in appState.updateNotificationPreferences { $0.digestEnabled = on } }
                ))

                Toggle("Notify me when a release date changes", isOn: Binding(
                    get: { prefs.notifyScheduleChanges },
                    set: { on in appState.updateNotificationPreferences { $0.notifyScheduleChanges = on } }
                ))

                Toggle("Quiet hours", isOn: Binding(
                    get: { prefs.quietHoursEnabled },
                    set: { on in appState.updateNotificationPreferences { $0.quietHoursEnabled = on } }
                ))
                if prefs.quietHoursEnabled {
                    Picker("From", selection: Binding(
                        get: { prefs.quietHoursStart },
                        set: { hour in appState.updateNotificationPreferences { $0.quietHoursStart = hour } }
                    )) {
                        ForEach(0..<24, id: \.self) { Text(Self.hourLabel($0)).tag($0) }
                    }
                    Picker("Until", selection: Binding(
                        get: { prefs.quietHoursEnd },
                        set: { hour in appState.updateNotificationPreferences { $0.quietHoursEnd = hour } }
                    )) {
                        ForEach(0..<24, id: \.self) { Text(Self.hourLabel($0)).tag($0) }
                    }
                    Text("Alerts that would arrive inside this window wait until it closes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Airpisode looks up episode air times from TVmaze. Releases with a confirmed time get timed alerts; date-only releases are shown without a clock time and get no time-based alert. Use a show's context menu to override the global lead time.")
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
                    Text("Episode air times from TVmaze.")
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

    private static func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "j", options: 0, locale: .current
        ) ?? "HH"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
}
