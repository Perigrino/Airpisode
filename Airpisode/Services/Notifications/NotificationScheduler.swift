import Foundation
import UserNotifications

/// A pending request as the UI can understand it, without leaking UN types into views.
struct PendingAlert: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date?
}

protocol NotificationClientProtocol: Sendable {
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePending(withIdentifiers ids: [String])
    func authorizationStatus() async -> UNAuthorizationStatus
    func pendingAlerts() async -> [PendingAlert]
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

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings {
                continuation.resume(returning: $0.authorizationStatus)
            }
        }
    }

    func pendingAlerts() async -> [PendingAlert] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.compactMap { request in
                    let trigger = request.trigger
                    let fireDate: Date?
                    if let calendar = trigger as? UNCalendarNotificationTrigger {
                        fireDate = Calendar.current.date(from: calendar.dateComponents)
                    } else if let interval = trigger as? UNTimeIntervalNotificationTrigger {
                        fireDate = Date().addingTimeInterval(interval.timeInterval)
                    } else {
                        fireDate = nil
                    }
                    return PendingAlert(
                        id: request.identifier,
                        title: request.content.title,
                        body: request.content.body,
                        fireDate: fireDate
                    )
                })
            }
        }
    }
}

struct NotificationScheduler {
    let client: NotificationClientProtocol

    static let preAlertIDPrefix = "pre-"
    static let imminentIDPrefix = "imminent-"
    static let testIDPrefix = "test-"

    static func preAlertID(titleID: String, key: String) -> String { "\(preAlertIDPrefix)\(titleID)-\(key)" }
    static func imminentID(titleID: String, key: String) -> String { "\(imminentIDPrefix)\(titleID)-\(key)" }

    /// Reconciles the whole library at once. The previous implementation cancelled and
    /// re-added per title, so it could never see the global pending count; that let a long
    /// season push the soonest alerts past the system's 64-request cap.
    func apply(library: Library, now: Date = .now, calendar: Calendar = .current) async {
        await apply(plan: NotificationPlanner.plan(library: library, now: now, calendar: calendar))
    }

    func apply(plan: [PlannedAlert]) async {
        let pending = await client.pendingAlerts()
        let desired = Set(plan.map(\.id))
        let stale = pending.map(\.id).filter { Self.isManagedID($0) && !desired.contains($0) }
        if !stale.isEmpty {
            client.removePending(withIdentifiers: stale)
        }
        for alert in plan {
            await addAlert(alert)
        }
    }

    /// Kept for focused scheduler tests and any caller that only has one title in hand.
    /// Production uses the library-wide `apply(library:)` above.
    func schedule(
        for title: Title,
        episodes: [Episode] = [],
        movieReleases: [MovieRelease] = [],
        prefs: NotificationPreferences,
        now: Date = .now
    ) async {
        var library = Library()
        library.preferences = prefs
        library.titles[title.id] = title
        library.entries = [
            WatchlistEntry(
                tmdbID: title.tmdbID, mediaType: title.mediaType,
                addedAt: now, isTrackingEnabled: true
            )
        ]
        if !episodes.isEmpty { library.episodes[title.id] = episodes }
        if !movieReleases.isEmpty { library.movieReleases[title.id] = movieReleases }
        await apply(plan: NotificationPlanner.plan(library: library, now: now))
    }

    func cancelAll(forTitle titleID: String, keys: [String]) {
        let ids = keys.flatMap {
            [Self.preAlertID(titleID: titleID, key: $0), Self.imminentID(titleID: titleID, key: $0)]
        }
        client.removePending(withIdentifiers: ids)
    }

    // MARK: - One-off alerts

    func sendTestAlert(posterPath: String? = nil, now: Date = .now) async {
        let content = UNMutableNotificationContent()
        content.title = "Airpisode test alert"
        content.body = "If this looks right, release alerts will too."
        if let posterPath {
            await attachPoster(path: posterPath, to: content)
        }
        let request = UNNotificationRequest(
            identifier: Self.testIDPrefix + String(Int(now.timeIntervalSince1970)),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        )
        try? await client.add(request)
    }

    /// One batched banner for a refresh that found moved or newly announced releases.
    /// Individual banners would be noisy; the To Watch card carries the details.
    func notifyScheduleChanges(_ records: [ScheduleChangeRecord], now: Date = .now) async {
        guard let first = records.first else { return }
        let content = UNMutableNotificationContent()
        content.title = records.count == 1 ? "Release date changed" : "\(records.count) release changes"
        content.body = records.prefix(2).map { record in
            if let newDate = record.newDate {
                return "\(record.titleName) \(record.label) → \(Self.dateText(newDate))"
            }
            return "\(record.titleName) \(record.label)"
        }.joined(separator: "\n")
        content.body = NotificationPlanner.sanitized(content.body, limit: 300)
        if records.count == 1, let posterPath = first.posterPath {
            await attachPoster(path: posterPath, to: content)
        }
        let request = UNNotificationRequest(
            identifier: "changes-\(Int(first.detectedAt.timeIntervalSince1970))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await client.add(request)
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

    static func isManagedID(_ id: String) -> Bool {
        id.hasPrefix(preAlertIDPrefix)
            || id.hasPrefix(imminentIDPrefix)
            || id.hasPrefix(NotificationPlanner.digestPrefix)
    }

    /// TMDB date-only values are encoded as exactly noon UTC (see TMDBMapper.parseDate).
    static func isDateOnlyEncoded(_ date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return c.hour == 12 && c.minute == 0 && c.second == 0
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static func dateText(_ date: Date) -> String { dateFormatter.string(from: date) }

    private func addAlert(_ alert: PlannedAlert) async {
        let content = UNMutableNotificationContent()
        content.title = NotificationPlanner.sanitized(alert.title, limit: 120)
        content.subtitle = NotificationPlanner.sanitized(alert.subtitle ?? "", limit: 80)
        content.body = NotificationPlanner.sanitized(alert.body, limit: 300)
        content.categoryIdentifier = alert.category
        content.userInfo = alert.userInfo
        if let posterPath = alert.posterPath {
            await attachPoster(path: posterPath, to: content)
        }
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: alert.fireDate
        )
        let request = UNNotificationRequest(
            identifier: alert.id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
        try? await client.add(request)
    }

    /// Downloads once into the temp directory and reuses the file for later schedules.
    /// A missing poster is cosmetic: the alert still goes out without it.
    private func attachPoster(path: String, to content: UNMutableNotificationContent) async {
        guard let file = await posterFile(for: path),
              let attachment = try? UNNotificationAttachment(
                identifier: "poster", url: file, options: nil
              )
        else { return }
        content.attachments = [attachment]
    }

    private func posterFile(for path: String) async -> URL? {
        let name = path.split(separator: "/").last.map(String.init) ?? "poster.jpg"
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirpisodePoster-\(name)")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let remote = URL(string: "https://image.tmdb.org/t/p/w500\(path)") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: remote)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty
            else { return nil }
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }
}
