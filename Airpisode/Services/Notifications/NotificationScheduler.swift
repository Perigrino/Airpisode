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

    /// Requests permission if it has never been asked, then returns the current status.
    private func ensureAuthorized() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        return status
    }

    /// Debug helper: requests permission if needed, then fires a test notification after a delay.
    func scheduleTest(in seconds: TimeInterval = 120) async {
        let status = await ensureAuthorized()

        let content = UNMutableNotificationContent()
        content.title = "Airpisode test notification"
        content.body = "If you can see this, notifications are working."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "debug-test-\(Int.random(in: 0...1_000_000))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        do {
            try await client.add(request)
            await postImmediate(
                id: "debug-test-confirm",
                title: "Airpisode test scheduled ✓",
                body: "Status: \(Self.statusName(status)). Fires in \(Int(seconds))s — even while the app is open."
            )
        } catch {
            await postImmediate(
                id: "debug-test-error",
                title: "Airpisode test failed",
                body: "Scheduling failed: \(error.localizedDescription). Status: \(Self.statusName(status))."
            )
        }
    }

    /// Debug helper: fires a realistic "out now" alert built from a real tracked title.
    /// Lets you see exactly what a genuine release notification looks like.
    func scheduleReleaseSample(library: Library, in seconds: TimeInterval = 10) async {
        let status = await ensureAuthorized()
        guard let sample = Self.releaseSample(from: library) else {
            await postImmediate(
                id: "debug-release-empty",
                title: "No release to sample yet",
                body: "Track a show or movie with a known air/release date, then try again. Status: \(Self.statusName(status))."
            )
            return
        }

        let content = UNMutableNotificationContent()
        content.title = sample.title
        content.body = sample.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "debug-release-\(Int.random(in: 0...1_000_000))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        do {
            try await client.add(request)
            await postImmediate(
                id: "debug-release-confirm",
                title: "Sample release alert scheduled ✓",
                body: "Fires in \(Int(seconds))s from your tracked data. Status: \(Self.statusName(status))."
            )
        } catch {
            await postImmediate(
                id: "debug-release-error",
                title: "Sample release alert failed",
                body: "\(error.localizedDescription). Status: \(Self.statusName(status))."
            )
        }
    }

    private func postImmediate(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        _ = try? await client.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
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

    // MARK: - Release sample (debug)

    struct ReleaseSample: Equatable {
        let title: String
        let body: String
    }

    /// Builds a realistic "out now" alert from real tracked data: the latest aired episode,
    /// else the soonest upcoming episode, else a movie release.
    static func releaseSample(from library: Library) -> ReleaseSample? {
        var episodes: [(Title, Episode)] = []
        for entry in library.entries where entry.mediaType == .tv {
            guard let title = library.titles[entry.id] else { continue }
            for episode in library.episodes[entry.id] ?? [] where episode.airDate != nil {
                episodes.append((title, episode))
            }
        }
        let aired = episodes.filter { ($0.1.airDate ?? .distantFuture) <= .now }
        let match: (Title, Episode)?
        if aired.isEmpty {
            match = episodes.min { ($0.1.airDate ?? .distantFuture) < ($1.1.airDate ?? .distantFuture) }
        } else {
            match = aired.max { ($0.1.airDate ?? .distantPast) < ($1.1.airDate ?? .distantPast) }
        }
        if let (title, episode) = match {
            let date = episode.airDate.map { dayFormatter.string(from: $0) } ?? "recently"
            let released = (episode.airDate ?? .now) <= .now
            return ReleaseSample(
                title: "\(title.name) — New Episode \(released ? "Out Now" : "Incoming")!",
                body: "S\(episode.seasonNumber)E\(episode.episodeNumber) · \"\(episode.name)\" "
                    + (released ? "just aired" : "premieres") + " · \(date)"
            )
        }
        for entry in library.entries where entry.mediaType == .movie {
            guard let title = library.titles[entry.id] else { continue }
            let releases = (library.movieReleases[entry.id] ?? []).filter { $0.date != nil }
            guard let release = releases.min(by: { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }),
                  let date = release.date else { continue }
            let released = date <= .now
            return ReleaseSample(
                title: "\(title.name) — \(release.kind.label) \(released ? "Out Now" : "Releasing Soon")!",
                body: "\(release.region) · " + (released ? "available" : "releases") + " \(dayFormatter.string(from: date))"
            )
        }
        return nil
    }

    /// One-line preview of the sample, for the Settings debug screen.
    static func releaseSamplePreview(library: Library) -> String? {
        guard let sample = releaseSample(from: library) else { return nil }
        return "\(sample.title) — \(sample.body)"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}
