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
            // Prefer TVmaze's exact air instant. TMDB alone is date-only for TV, and a
            // date-only value must never be turned into an invented clock time.
            let airDate: Date
            if let timestamp = episode.airTimestamp {
                airDate = timestamp
            } else if let date = episode.airDate, !Self.isDateOnlyEncoded(date) {
                airDate = date
            } else {
                continue
            }
            guard airDate > now else { continue }
            let key = episode.id
            if let hours = prefs.preAlertHours {
                let fire = airDate.addingTimeInterval(-TimeInterval(hours * 3600))
                if fire > now {
                    await addAlert(
                        identifier: Self.preAlertID(titleID: title.id, key: key),
                        title: "\(title.name) — New Episode \(relativeDay(airDate, now: now))!",
                        body: episodeLabel(episode) + " — airs \(relativeDay(airDate, now: now).lowercased()) at \(Self.time(airDate))",
                        fireDate: fire,
                        category: Self.episodeCategory,
                        userInfo: ["titleID": title.id, "key": episode.id, "kind": "episode"]
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
                        fireDate: fire,
                        category: Self.episodeCategory,
                        userInfo: ["titleID": title.id, "key": episode.id, "kind": "episode"]
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
                fireDate: fire,
                category: Self.movieCategory,
                userInfo: ["titleID": title.id, "key": release.id, "kind": "movie"]
            )
        }
    }

    func cancelAll(forTitle titleID: String, keys: [String]) {
        let ids = keys.flatMap {
            [Self.preAlertID(titleID: titleID, key: $0), Self.imminentID(titleID: titleID, key: $0)]
        }
        client.removePending(withIdentifiers: ids)
    }

    // MARK: - Banner actions

    static let markWatchedAction = "markWatched"
    static let muteTitleAction = "muteTitle"
    static let episodeCategory = "episodeAlert"
    static let movieCategory = "movieAlert"

    /// The banner's buttons: registered once at launch or the actions never appear. Actions
    /// run in the background; the ordinary banner tap still opens the window.
    static func registerAlertCategories() {
        let mark = UNNotificationAction(identifier: markWatchedAction, title: "Mark watched", options: [])
        let muteEpisode = UNNotificationAction(
            identifier: muteTitleAction, title: "Mute this show", options: [.destructive]
        )
        let muteMovie = UNNotificationAction(
            identifier: muteTitleAction, title: "Mute this movie", options: [.destructive]
        )
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: episodeCategory, actions: [mark, muteEpisode], intentIdentifiers: []),
            UNNotificationCategory(identifier: movieCategory, actions: [mark, muteMovie], intentIdentifiers: []),
        ])
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

    private func addAlert(
        identifier: String, title: String, body: String, fireDate: Date,
        category: String, userInfo: [String: String]
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.userInfo = userInfo
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
        try? await client.add(request)
    }
}
