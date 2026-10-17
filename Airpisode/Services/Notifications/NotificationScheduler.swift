import Foundation
import UserNotifications

protocol NotificationClientProtocol: Sendable {
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePending(withIdentifiers ids: [String])
}

struct SystemNotificationClient: NotificationClientProtocol {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }
    func removePending(withIdentifiers ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

struct NotificationScheduler {
    let client: NotificationClientProtocol

    static func preAlertID(titleID: String, key: String) -> String { "pre-\(titleID)-\(key)" }
    static func imminentID(titleID: String, key: String) -> String { "imminent-\(titleID)-\(key)" }

    /// Reschedules a title's alerts: cancels known IDs first, then re-adds (deterministic IDs → replace, never duplicate).
    func schedule(
        for title: Title,
        episodes: [Episode] = [],
        movieReleases: [MovieRelease] = [],
        prefs: NotificationPreferences,
        now: Date = .now
    ) async {
        guard prefs.permissionRequested else { return }

        for episode in episodes {
            // v1: date-only episode air dates (noon-UTC encoding) get no alerts — never invent a time.
            guard let airDate = episode.airDate, airDate > now, !Self.isDateOnlyEncoded(airDate) else { continue }
            let key = episode.id
            if let hours = prefs.preAlertHours {
                let fire = airDate.addingTimeInterval(-TimeInterval(hours * 3600))
                if fire > now {
                    await addAlert(
                        identifier: Self.preAlertID(titleID: title.id, key: key),
                        title: "\(title.name) — New Episode \(relativeDay(airDate, now: now))!",
                        body: episodeLabel(episode) + " — airs \(relativeDay(airDate, now: now).lowercased()) at \(Self.time(airDate))",
                        fireDate: fire
                    )
                }
            }
            if let minutes = prefs.imminentAlertMinutes {
                let fire = airDate.addingTimeInterval(-TimeInterval(minutes * 60))
                if fire > now {
                    await addAlert(
                        identifier: Self.imminentID(titleID: title.id, key: key),
                        title: "\(title.name) — Starting Soon!",
                        body: episodeLabel(episode) + " — airs at \(Self.time(airDate))",
                        fireDate: fire
                    )
                }
            }
        }

        for release in movieReleases {
            // Timed movie releases get a pre-alert only (no imminent).
            guard release.hasTime, let date = release.date, date > now, let hours = prefs.preAlertHours else { continue }
            let fire = date.addingTimeInterval(-TimeInterval(hours * 3600))
            guard fire > now else { continue }
            await addAlert(
                identifier: Self.preAlertID(titleID: title.id, key: release.id),
                title: "\(title.name) — \(release.kind.label) \(relativeDay(date, now: now))!",
                body: "Available \(relativeDay(date, now: now).lowercased()) at \(Self.time(date))",
                fireDate: fire
            )
        }
    }

    /// Debug helper: requests permission if needed, then fires a test notification after a delay.
    func scheduleTest(in seconds: TimeInterval = 120) async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }

        let content = UNMutableNotificationContent()
        content.title = "Airpisode test notification"
        content.body = "If you can see this, notifications are working."
        let request = UNNotificationRequest(
            identifier: "debug-test-\(Int.random(in: 0...1_000_000))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        do {
            try await client.add(request)
            content.title = "Airpisode test scheduled ✓"
            content.body = "Status: \(Self.statusName(status)). Fires in \(Int(seconds))s — even while the app is open."
            _ = try? await client.add(UNNotificationRequest(
                identifier: "debug-test-confirm",
                content: content,
                trigger: nil
            ))
        } catch {
            content.title = "Airpisode test failed"
            content.body = "Scheduling failed: \(error.localizedDescription). Authorization status: \(Self.statusName(status))."
            _ = try? await client.add(UNNotificationRequest(
                identifier: "debug-test-error",
                content: content,
                trigger: nil
            ))
        }
    }

    private static func statusName(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "not determined — click 'Enable Notifications' first"
        case .denied: return "denied — enable in System Settings → Notifications → Airpisode"
        case .authorized, .provisional: return "authorized"
        case .ephemeral: return "authorized (ephemeral)"
        @unknown default: return "unknown"
        }
    }

    func cancelAll(forTitle titleID: String, keys: [String]) {
        let ids = keys.flatMap {
            [Self.preAlertID(titleID: titleID, key: $0), Self.imminentID(titleID: titleID, key: $0)]
        }
        client.removePending(withIdentifiers: ids)
    }

    // MARK: - Helpers

    /// TMDB date-only values are encoded as exactly noon UTC (see TMDBMapper.parseDate).
    private static func isDateOnlyEncoded(_ date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return c.hour == 12 && c.minute == 0 && c.second == 0
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    private func relativeDay(_ date: Date, now: Date) -> String {
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: now), to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
        switch days {
        case ...0: return "Today"
        case 1: return "Tomorrow"
        default: return "in \(days) days"
        }
    }

    private func episodeLabel(_ episode: Episode) -> String {
        "S\(episode.seasonNumber)E\(episode.episodeNumber) · \"\(episode.name)\""
    }

    private func addAlert(identifier: String, title: String, body: String, fireDate: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
        try? await client.add(request)
    }
}
