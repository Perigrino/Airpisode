import SwiftUI
import UserNotifications

// MARK: - Settings shell

/// Three tabs, each one grouped form that applies changes immediately.
struct SettingsView: View {
    @AppStorage("settingsTab") private var tabRaw = SettingsTab.general.rawValue

    private var tab: Binding<SettingsTab> {
        Binding(
            get: { SettingsTab(rawValue: tabRaw) ?? .general },
            set: { tabRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: tab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            NotificationSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(SettingsTab.notifications)

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 540, height: 620)
        .tint(Theme.accent)
        .modifier(ClearInitialFocus())
    }
}

/// Settings opens with nothing selected, so the window feels calm instead of showing a focus ring on the key field.
private struct ClearInitialFocus: ViewModifier {
    func body(content: Content) -> some View {
        content.onAppear {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }
}

private enum SettingsTab: String {
    case general, notifications, about
}

// MARK: - General

private struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState

    private var regionOptions: [(code: String, title: String)] {
        RegionCatalog.options(including: ConfigStore.defaultRegion)
    }

    var body: some View {
        Form {
            Section {
                APIKeyForm { Task { await appState.runFullRefresh() } }
                TMDBKeyHelp()
            } header: {
                Text("TMDB API Key")
            } footer: {
                Text("Airpisode reads show and movie metadata from TMDB using your own free key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Release region", selection: Binding(
                    get: { ConfigStore.defaultRegion },
                    set: { code in
                        ConfigStore.setDefaultRegion(code)
                        // Relabel stored releases and check for new ones right away.
                        Task { await appState.runFullRefresh() }
                    }
                )) {
                    ForEach(regionOptions, id: \.code) { option in
                        Text(option.title).tag(option.code)
                    }
                }
            } header: {
                Text("Region")
            } footer: {
                Text("Release dates and streaming availability follow this country.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Library folder") {
                    Button("Show in Finder", action: revealLibraryFolder)
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Your library stays on this Mac. Airpisode keeps a backup copy beside it and preserves any file it cannot read.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func revealLibraryFolder() {
        let folder = LibraryStore.defaultDirectory()
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}

// MARK: - Notifications

private struct NotificationSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var authorization: UNAuthorizationStatus = .notDetermined

    private var prefs: NotificationPreferences { appState.library.preferences }

    var body: some View {
        Form {
            Section {
                permissionRow
            } header: {
                Text("Permission")
            }

            Section {
                Picker("Pre-release alert", selection: Binding(
                    get: { prefs.preAlertHours ?? 0 },
                    set: { hours in
                        appState.updateNotificationPreferences {
                            $0.preAlertHours = hours == 0 ? nil : hours
                        }
                    }
                )) {
                    Text("Off").tag(0)
                    Text("1 hour before").tag(1)
                    Text("24 hours before").tag(24)
                    Text("48 hours before").tag(48)
                }

                Toggle("Alert 15 minutes before a known air time", isOn: Binding(
                    get: { prefs.imminentAlertMinutes != nil },
                    set: { on in
                        appState.updateNotificationPreferences {
                            $0.imminentAlertMinutes = on ? 15 : nil
                        }
                    }
                ))
                .controlSize(.mini)

                Toggle("Notify me when a release date changes", isOn: Binding(
                    get: { prefs.notifyScheduleChanges },
                    set: { on in appState.updateNotificationPreferences { $0.notifyScheduleChanges = on } }
                ))
                .controlSize(.mini)
            } header: {
                Text("Alerts")
            } footer: {
                Text("Airpisode looks up episode air times from TVmaze. Releases with a confirmed time get timed alerts; date-only releases are shown without a clock time. Use a show's context menu to override the lead time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Daily lineup summary", isOn: Binding(
                    get: { prefs.digestEnabled },
                    set: { on in appState.updateNotificationPreferences { $0.digestEnabled = on } }
                ))
                .controlSize(.mini)

                if prefs.digestEnabled {
                    Picker("Send at", selection: Binding(
                        get: { prefs.digestHour },
                        set: { hour in appState.updateNotificationPreferences { $0.digestHour = hour } }
                    )) {
                        ForEach(0..<24, id: \.self) { Text(Self.hourLabel($0)).tag($0) }
                    }
                }
            } header: {
                Text("Daily summary")
            }

            Section {
                Toggle("Quiet hours", isOn: Binding(
                    get: { prefs.quietHoursEnabled },
                    set: { on in appState.updateNotificationPreferences { $0.quietHoursEnabled = on } }
                ))
                .controlSize(.mini)

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
                }
            } header: {
                Text("Quiet hours")
            } footer: {
                Text("Alerts that would arrive inside this window wait until it closes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Send Test Alert") {
                    Task { await appState.sendTestAlert() }
                }
                .help("Sends a notification now so you can check how alerts look")
            }
        }
        .formStyle(.grouped)
        .task {
            authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    private var permissionRow: some View {
        LabeledContent("Notifications") {
            HStack(spacing: Theme.Space.s) {
                Text(statusText)
                    .foregroundStyle(authorization == .denied ? Color.orange : .secondary)
                if authorization == .denied {
                    Button("Open Settings…") { openNotificationSettings() }
                        .controlSize(.small)
                }
            }
        }
        .controlSize(.mini)
    }

    private var statusText: String {
        if !prefs.permissionRequested { return "Not requested yet" }
        switch authorization {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Not allowed"
        default: return "Not requested yet"
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
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

// MARK: - About

private struct AboutSettingsView: View {
    @EnvironmentObject private var updater: SparkleUpdater
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: Theme.Space.l) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Airpisode")
                            .font(.headline)
                        Text("Never miss what's next.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Version \(version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Theme.Space.xs)
            }

            Section("Data sources") {
                LabeledContent("Metadata") {
                    Image("tmdb-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 16)
                        .accessibilityLabel("TMDB")
                }
                LabeledContent("Air times", value: "TVmaze")
                LabeledContent("Streaming offers", value: "JustWatch")
            }

            Section("Updates") {
                switch updater.status {
                case .configured:
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                    Text("New versions are checked daily and signed updates install in place, with release notes shown before installing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .unconfigured(let reason):
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("In-app updates are off in this build. Add a feed URL and public key to enable them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
