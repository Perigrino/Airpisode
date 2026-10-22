import Foundation

/// One local alert before it becomes a `UNNotificationRequest`. Planning is pure so the
/// scheduling budget, per-show overrides, and digest can be tested without UserNotifications.
struct PlannedAlert: Identifiable, Equatable {
    let id: String
    let fireDate: Date
    let title: String
    let subtitle: String?
    let body: String
    let category: String
    let posterPath: String?
    let userInfo: [String: String]
    /// A near-immediate reminder created because the normal lead-time moment passed while the
    /// app was closed or relaunching. Uses an interval trigger so it cannot miss the minute.
    var isCatchUp = false
}

/// Builds the complete alert set for the library. The scheduler applies this plan as a
/// reconciliation: anything managed but absent from the plan is removed.
///
/// macOS keeps only the soonest 64 pending local notifications and silently discards the
/// rest, so the plan is capped below that. Without the cap a long season can quietly evict
/// the very alerts a user is waiting for.
enum NotificationPlanner {
    static let maxPending = 60
    static let digestCategory = "digestAlert"
    static let digestPrefix = "digest-"

    static func plan(
        library: Library,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [PlannedAlert] {
        guard library.preferences.permissionRequested else { return [] }

        var alerts: [PlannedAlert] = []
        for entry in library.entries where entry.isTrackingEnabled {
            guard let title = library.titles[entry.id], !library.isMuted(entry.id) else { continue }
            let override = entry.preAlertOverride ?? .inherit
            // Off suppresses the pre-release warning only; the 15-minute alert is a separate
            // choice and still fires for a timed release.
            let hours = override.hours(global: library.preferences.preAlertHours)

            switch entry.mediaType {
            case .tv:
                for episode in library.episodes[entry.id] ?? [] {
                    guard !library.watchedEpisodes.contains(episode.id),
                          let airDate = airMoment(episode),
                          airDate > now
                    else { continue }
                    let key = episode.id
                    let episodeLabel = "S\(episode.seasonNumber)E\(episode.episodeNumber)"
                    let cleanName = sanitized(episode.name, limit: 80)
                    if let hours {
                        appendPreAlert(
                            to: &alerts, id: "pre-\(title.id)-\(key)",
                            hours: hours, airDate: airDate, now: now,
                            title: "\(title.name) · \(episodeLabel)",
                            subtitle: cleanName,
                            body: "Airs \(relativeDay(airDate, now: now, calendar: calendar).lowercased()) at \(time(airDate, calendar: calendar))",
                            category: NotificationScheduler.episodeCategory,
                            posterPath: title.posterPath,
                            userInfo: ["titleID": title.id, "key": key, "kind": "episode"]
                        )
                    }
                    if let minutes = library.preferences.imminentAlertMinutes {
                        let normalFire = airDate.addingTimeInterval(-TimeInterval(minutes * 60))
                        let remaining = airDate.timeIntervalSince(now)
                        if normalFire > now {
                            appendPreAlert(
                                to: &alerts, id: "imminent-\(title.id)-\(key)",
                                minutes: minutes, airDate: airDate, now: now,
                                title: "\(title.name) · \(episodeLabel)",
                                subtitle: cleanName,
                                body: "Starts in \(minutes) minutes · \(time(airDate, calendar: calendar))",
                                category: NotificationScheduler.episodeCategory,
                                posterPath: title.posterPath,
                                userInfo: ["titleID": title.id, "key": key, "kind": "episode"]
                            )
                        } else if remaining > 5 {
                            // Relaunching inside the lead window must not silently drop the
                            // reminder. Fire shortly after the app is ready instead.
                            let minutesLeft = max(1, Int(ceil(remaining / 60)))
                            let body = remaining < 60
                                ? "Starting now · \(time(airDate, calendar: calendar))"
                                : "Starts in \(minutesLeft) minutes · \(time(airDate, calendar: calendar))"
                            alerts.append(PlannedAlert(
                                id: "imminent-\(title.id)-\(key)",
                                fireDate: now.addingTimeInterval(5),
                                title: "\(title.name) · \(episodeLabel)",
                                subtitle: cleanName,
                                body: body,
                                category: NotificationScheduler.episodeCategory,
                                posterPath: title.posterPath,
                                userInfo: ["titleID": title.id, "key": key, "kind": "episode"],
                                isCatchUp: true
                            ))
                        }
                    }
                }
            case .movie:
                guard !library.watchedMovies.contains(entry.id) else { continue }
                for release in library.movieReleases[entry.id] ?? [] {
                    guard release.hasTime, let date = release.date, date > now, let hours else { continue }
                    appendPreAlert(
                        to: &alerts, id: "pre-\(title.id)-\(release.id)",
                        hours: hours, airDate: date, now: now,
                        title: "\(title.name) · \(release.kind.label)",
                        subtitle: nil,
                        body: "Available \(relativeDay(date, now: now, calendar: calendar).lowercased()) at \(time(date, calendar: calendar))",
                        category: NotificationScheduler.movieCategory,
                        posterPath: title.posterPath,
                        userInfo: ["titleID": title.id, "key": release.id, "kind": "movie"]
                    )
                }
            }
        }

        alerts += digestAlerts(library: library, now: now, calendar: calendar)
        return sortAndCap(alerts)
    }

    static func sortAndCap(_ alerts: [PlannedAlert]) -> [PlannedAlert] {
        Array(alerts.sorted {
            if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
            return $0.id < $1.id
        }.prefix(maxPending))
    }

    // MARK: - Digest

    /// One morning summary per day for the next week, listing what airs in the following
    /// 24 hours. It supplements pre-release alerts rather than replacing them: a daily
    /// recap must never swallow a 24h warning that falls outside its window.
    private static func digestAlerts(
        library: Library,
        now: Date,
        calendar: Calendar
    ) -> [PlannedAlert] {
        guard library.preferences.digestEnabled else { return [] }
        var alerts: [PlannedAlert] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fire = calendar.date(
                    bySettingHour: library.preferences.digestHour, minute: 0, second: 0,
                    of: day, matchingPolicy: .nextTime
                  ),
                  fire > now
            else { continue }
            let end = fire.addingTimeInterval(86_400)
            let releases = digestReleases(library: library, from: fire, to: end, calendar: calendar)
            guard !releases.isEmpty else { continue }

            let shown = releases.prefix(3).map { "\($0.title) · \($0.label)" }.joined(separator: "\n")
            let extra = releases.count > 3 ? "\n+\(releases.count - 3) more" : ""
            let id = digestPrefix + dayKey(fire, calendar: calendar)
            alerts.append(PlannedAlert(
                id: id,
                fireDate: fire,
                title: digestTitle(fire, now: now, calendar: calendar),
                subtitle: nil,
                body: shown + extra,
                category: digestCategory,
                posterPath: nil,
                userInfo: ["kind": "digest"]
            ))
        }
        return alerts
    }

    private struct DigestRelease {
        let title: String
        let label: String
        let date: Date
    }

    private static func digestReleases(
        library: Library,
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> [DigestRelease] {
        var releases: [DigestRelease] = []
        for entry in library.entries where entry.isTrackingEnabled {
            guard let title = library.titles[entry.id], !library.isMuted(entry.id) else { continue }
            if entry.preAlertOverride == .off { continue }
            switch entry.mediaType {
            case .tv:
                for episode in library.episodes[entry.id] ?? [] {
                    guard !library.watchedEpisodes.contains(episode.id),
                          let date = airMoment(episode),
                          date >= start, date < end
                    else { continue }
                    releases.append(DigestRelease(
                        title: title.name,
                        label: "S\(episode.seasonNumber)E\(episode.episodeNumber)",
                        date: date
                    ))
                }
            case .movie:
                for release in library.movieReleases[entry.id] ?? [] {
                    guard let date = release.date, date >= start, date < end else { continue }
                    releases.append(DigestRelease(
                        title: title.name,
                        label: release.kind.label,
                        date: date
                    ))
                }
            }
        }
        return releases.sorted { $0.date < $1.date }
    }

    // MARK: - Helpers

    private static func appendPreAlert(
        to alerts: inout [PlannedAlert],
        id: String,
        hours: Int,
        airDate: Date,
        now: Date,
        title: String,
        subtitle: String?,
        body: String,
        category: String,
        posterPath: String?,
        userInfo: [String: String]
    ) {
        let fire = airDate.addingTimeInterval(-TimeInterval(hours * 3600))
        guard fire > now else { return }
        alerts.append(PlannedAlert(
            id: id, fireDate: fire, title: title, subtitle: subtitle, body: body,
            category: category, posterPath: posterPath, userInfo: userInfo
        ))
    }

    private static func appendPreAlert(
        to alerts: inout [PlannedAlert],
        id: String,
        minutes: Int,
        airDate: Date,
        now: Date,
        title: String,
        subtitle: String?,
        body: String,
        category: String,
        posterPath: String?,
        userInfo: [String: String]
    ) {
        let fire = airDate.addingTimeInterval(-TimeInterval(minutes * 60))
        guard fire > now else { return }
        alerts.append(PlannedAlert(
            id: id, fireDate: fire, title: title, subtitle: subtitle, body: body,
            category: category, posterPath: posterPath, userInfo: userInfo
        ))
    }

    /// Exact TVmaze time wins. A TMDB date-only value is only usable when it is not the
    /// noon-UTC sentinel; otherwise there is no honest clock time to schedule.
    private static func airMoment(_ episode: Episode) -> Date? {
        if let timestamp = episode.airTimestamp { return timestamp }
        guard let date = episode.airDate, !NotificationScheduler.isDateOnlyEncoded(date) else { return nil }
        return date
    }

    private static func digestTitle(_ fire: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(fire, inSameDayAs: now) { return "Today's lineup" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(fire, inSameDayAs: tomorrow) {
            return "Tomorrow's lineup"
        }
        return "\(fire.formatted(.dateTime.weekday(.wide))) lineup"
    }

    private static func relativeDay(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
        ).day ?? 0
        switch days {
        case ...0: return "Today"
        case 1: return "Tomorrow"
        default: return "in \(days) days"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static func time(_ date: Date, calendar: Calendar) -> String {
        timeFormatter.timeZone = calendar.timeZone
        return timeFormatter.string(from: date)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        dayKeyFormatter.timeZone = calendar.timeZone
        return dayKeyFormatter.string(from: date)
    }

    /// Notification strings come from provider data; trim the edges and keep banners readable.
    static func sanitized(_ value: String, limit: Int) -> String {
        let clean = value
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > limit else { return clean }
        return String(clean.prefix(limit - 1)) + "…"
    }
}
