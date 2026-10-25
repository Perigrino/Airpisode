import Foundation

/// One local alert before it becomes a `UNNotificationRequest`. Planning is pure so the
/// scheduling budget, per-show overrides, and digest can be tested without UserNotifications.
struct PlannedAlert: Identifiable, Equatable {
    let id: String
    var fireDate: Date
    let title: String
    let subtitle: String?
    var body: String
    let category: String
    let posterPath: String?
    let userInfo: [String: String]
    /// A near-immediate reminder created because the normal lead-time moment passed while the
    /// app was closed or relaunching. Uses an interval trigger so it cannot miss the minute.
    var isCatchUp = false
    /// Banners from one show share a thread so the tray collapses them into one stack.
    var threadID: String? = nil
    /// Imminent alerts may break through Focus; summaries stay quiet.
    var isUrgent = false
    /// Deliveries this alert supersedes, removed from the tray when it is posted.
    var retiresIDs: [String] = []
    /// The real release moment, kept so a quiet-hours deferral can restate the copy honestly.
    var airDate: Date? = nil
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

    /// `catchUpWindow` is non-zero only on a wake/launch pass. Such a pass may speak for an
    /// episode whose lead time slipped by while the process was asleep or closed — both just
    /// before and just after the start. Routine reconciles pass zero, so a banner the user
    /// already dismissed is never resurrected a minute later.
    static func plan(
        library: Library,
        now: Date = .now,
        calendar: Calendar = .current,
        catchUpWindow: TimeInterval = 0
    ) -> [PlannedAlert] {
        guard library.preferences.permissionRequested else { return [] }

        // A release already listed in an upcoming digest does not need its own 24-hour
        // warning: the digest arrives within the same day and says the same thing.
        let digestCovered = digestCoveredReleases(library: library, now: now, calendar: calendar)

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
                          let airDate = airMoment(episode)
                    else { continue }
                    // Future episodes are planned normally. A recently started one only
                    // qualifies during a wake/launch catch-up pass.
                    let justStarted = catchUpWindow > 0
                        && airDate <= now
                        && now.timeIntervalSince(airDate) <= catchUpWindow
                    guard airDate > now || justStarted else { continue }
                    let key = episode.id
                    let episodeLabel = "S\(episode.seasonNumber)E\(episode.episodeNumber)"
                    let cleanName = sanitized(episode.name, limit: 80)
                    if let hours, !digestCovered.contains("\(title.id)|\(episode.id)") {
                        appendPreAlert(
                            to: &alerts, id: "pre-\(title.id)-\(key)",
                            hours: hours, airDate: airDate, now: now,
                            title: title.name,
                            subtitle: "\(episodeLabel) · \(cleanName)",
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
                                title: title.name,
                                subtitle: "\(episodeLabel) · \(cleanName)",
                                body: "Starts in \(minutes) minutes",
                                category: NotificationScheduler.episodeCategory,
                                posterPath: title.posterPath,
                                userInfo: ["titleID": title.id, "key": key, "kind": "episode"]
                            )
                        } else if catchUpWindow > 0, remaining > 5 {
                            // Relaunching inside the lead window must not silently drop the
                            // reminder. Fire shortly after the app is ready instead.
                            let minutesLeft = max(1, Int(ceil(remaining / 60)))
                            let body = remaining < 60
                                ? "Starting now"
                                : "Starts in \(minutesLeft) minutes"
                            alerts.append(PlannedAlert(
                                id: "imminent-\(title.id)-\(key)",
                                fireDate: now.addingTimeInterval(5),
                                title: title.name,
                                subtitle: "\(episodeLabel) · \(cleanName)",
                                body: body,
                                category: NotificationScheduler.episodeCategory,
                                posterPath: title.posterPath,
                                userInfo: ["titleID": title.id, "key": key, "kind": "episode"],
                                isCatchUp: true,
                                threadID: title.id, isUrgent: true,
                                retiresIDs: ["pre-\(title.id)-\(key)"],
                                airDate: airDate
                            ))
                        } else if catchUpWindow > 0, remaining <= 0 {
                            // The start slipped by while the app was asleep or closed. Speak once
                            // on the next wake/launch, inside a short window, so a missed
                            // premiere does not vanish silently.
                            let elapsed = now.timeIntervalSince(airDate)
                            guard elapsed <= catchUpWindow else { continue }
                            let body = elapsed < 3_600
                                ? "Started \(max(1, Int(elapsed / 60))) minutes ago"
                                : "Aired at \(time(airDate, calendar: calendar))"
                            alerts.append(PlannedAlert(
                                id: "imminent-\(title.id)-\(key)",
                                fireDate: now.addingTimeInterval(5),
                                title: title.name,
                                subtitle: "\(episodeLabel) · \(cleanName)",
                                body: body,
                                category: NotificationScheduler.episodeCategory,
                                posterPath: title.posterPath,
                                userInfo: ["titleID": title.id, "key": key, "kind": "episode"],
                                isCatchUp: true,
                                threadID: title.id, isUrgent: true,
                                retiresIDs: ["pre-\(title.id)-\(key)"],
                                airDate: airDate
                            ))
                        }
                    }
                }
            case .movie:
                guard !library.watchedMovies.contains(entry.id) else { continue }
                for release in library.movieReleases[entry.id] ?? [] {
                    guard release.hasTime, let date = release.date, date > now, let hours,
                          !digestCovered.contains("\(title.id)|\(release.id)")
                    else { continue }
                    appendPreAlert(
                        to: &alerts, id: "pre-\(title.id)-\(release.id)",
                        hours: hours, airDate: date, now: now,
                        title: title.name,
                        subtitle: release.kind.label,
                        body: "Available \(relativeDay(date, now: now, calendar: calendar).lowercased()) at \(time(date, calendar: calendar))",
                        category: NotificationScheduler.movieCategory,
                        posterPath: title.posterPath,
                        userInfo: ["titleID": title.id, "key": release.id, "kind": "movie"]
                    )
                }
            }
        }

        alerts += digestAlerts(library: library, now: now, calendar: calendar)
        // Nothing lands in the middle of the night: a 3 AM banner waits for the quiet window
        // to close, and its copy is restated so it is still true when it finally arrives.
        let deferred = alerts.map {
            deferPastQuietHours(
                $0, prefs: library.preferences, calendar: calendar
            )
        }
        return sortAndCap(deferred)
    }

    static func sortAndCap(_ alerts: [PlannedAlert]) -> [PlannedAlert] {
        Array(alerts.sorted {
            if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
            return $0.id < $1.id
        }.prefix(maxPending))
    }

    // MARK: - Digest

    /// One summary per day for the next week, covering the 24 hours that follow it. The
    /// title names the real span, and lines that cross midnight say so.
    private static func digestAlerts(
        library: Library,
        now: Date,
        calendar: Calendar
    ) -> [PlannedAlert] {
        var alerts: [PlannedAlert] = []
        for window in digestWindows(library: library, now: now, calendar: calendar) {
            let releases = digestReleases(
                library: library, from: window.fire, to: window.end, calendar: calendar
            )
            guard !releases.isEmpty else { continue }

            let shown = releases.prefix(3).map { release -> String in
                let crossesMidnight = !calendar.isDate(release.date, inSameDayAs: window.fire)
                let clock = release.hasTime ? time(release.date, calendar: calendar) : nil
                return [release.title, release.label, crossesMidnight ? "Tomorrow" : nil, clock]
                    .compactMap { $0 }
                    .joined(separator: " · ")
            }.joined(separator: "\n")
            let extra = releases.count > 3 ? "\n+\(releases.count - 3) more" : ""
            let id = digestPrefix + dayKey(window.fire, calendar: calendar)
            alerts.append(PlannedAlert(
                id: id,
                fireDate: window.fire,
                title: "Next 24 hours",
                subtitle: nil,
                body: shown + extra,
                category: digestCategory,
                // The soonest show's art fronts the lineup; one poster per banner.
                posterPath: releases.compactMap(\.posterPath).first,
                userInfo: ["kind": "digest"],
                threadID: "digest"
            ))
        }
        return alerts
    }

    private struct DigestWindow {
        let fire: Date
        let end: Date
    }

    private static func digestWindows(
        library: Library,
        now: Date,
        calendar: Calendar
    ) -> [DigestWindow] {
        guard library.preferences.digestEnabled else { return [] }
        var windows: [DigestWindow] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fire = calendar.date(
                    bySettingHour: library.preferences.digestHour, minute: 0, second: 0,
                    of: day, matchingPolicy: .nextTime
                  ),
                  fire > now
            else { continue }
            windows.append(DigestWindow(fire: fire, end: fire.addingTimeInterval(86_400)))
        }
        return windows
    }

    /// Releases a digest already announces. Their standalone 24-hour warning would repeat
    /// the same fact within the same day, so the planner drops it.
    private static func digestCoveredReleases(
        library: Library,
        now: Date,
        calendar: Calendar
    ) -> Set<String> {
        var covered: Set<String> = []
        for window in digestWindows(library: library, now: now, calendar: calendar) {
            let releases = digestReleases(
                library: library, from: window.fire, to: window.end, calendar: calendar
            )
            for release in releases {
                covered.insert("\(release.titleID)|\(release.key)")
            }
        }
        return covered
    }

    private struct DigestRelease {
        let titleID: String
        /// Identifies the episode or movie release for de-duplication against pre-alerts.
        let key: String
        let title: String
        let label: String
        let date: Date
        /// Release data is honest about the clock: TV entries always carry an exact
        /// air moment, movies only when the provider supplied one.
        let hasTime: Bool
        let posterPath: String?
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
                        titleID: title.id,
                        key: episode.id,
                        title: title.name,
                        label: "S\(episode.seasonNumber)E\(episode.episodeNumber)",
                        date: date,
                        hasTime: true,
                        posterPath: title.posterPath
                    ))
                }
            case .movie:
                for release in library.movieReleases[entry.id] ?? [] {
                    guard let date = release.date, date >= start, date < end else { continue }
                    releases.append(DigestRelease(
                        titleID: title.id,
                        key: release.id,
                        title: title.name,
                        label: release.kind.label,
                        date: date,
                        hasTime: release.hasTime,
                        posterPath: title.posterPath
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
            category: category, posterPath: posterPath, userInfo: userInfo,
            threadID: userInfo["titleID"], airDate: airDate
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
        // The imminent reminder supersedes the earlier warning for the same episode.
        let thread = userInfo["titleID"]
        let retired = thread.flatMap { t in userInfo["key"].map { "pre-\(t)-\($0)" } }
        alerts.append(PlannedAlert(
            id: id, fireDate: fire, title: title, subtitle: subtitle, body: body,
            category: category, posterPath: posterPath, userInfo: userInfo,
            threadID: thread, isUrgent: true,
            retiresIDs: retired.map { [$0] } ?? [], airDate: airDate
        ))
    }

    /// Exact TVmaze time wins. A TMDB date-only value is only usable when it is not the
    /// noon-UTC sentinel; otherwise there is no honest clock time to schedule.
    private static func airMoment(_ episode: Episode) -> Date? {
        if let timestamp = episode.airTimestamp { return timestamp }
        guard let date = episode.airDate, !NotificationScheduler.isDateOnlyEncoded(date) else { return nil }
        return date
    }

    /// The quiet window that contains `date`, or nil when the date is outside it. A window
    /// may cross midnight (23 → 7), so the boundaries are anchored to the right day.
    static func quietWindow(
        containing date: Date,
        prefs: NotificationPreferences,
        calendar: Calendar
    ) -> DateInterval? {
        guard prefs.quietHoursEnabled else { return nil }
        let start = prefs.quietHoursStart
        let end = prefs.quietHoursEnd
        guard start != end, (0..<24).contains(start), (0..<24).contains(end) else { return nil }
        let hour = calendar.component(.hour, from: date)
        func boundary(_ dayOffset: Int, _ hour: Int) -> Date? {
            guard let day = calendar.date(
                byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: date)
            ) else { return nil }
            return calendar.date(
                bySettingHour: hour, minute: 0, second: 0, of: day, matchingPolicy: .nextTime
            )
        }
        if start < end {
            guard hour >= start, hour < end,
                  let from = boundary(0, start), let to = boundary(0, end) else { return nil }
            return DateInterval(start: from, end: to)
        }
        if hour >= start, let from = boundary(0, start), let to = boundary(1, end) {
            return DateInterval(start: from, end: to)
        }
        if hour < end, let from = boundary(-1, start), let to = boundary(0, end) {
            return DateInterval(start: from, end: to)
        }
        return nil
    }

    /// Holds an alert until the quiet window closes. Copy that would be false by then is
    /// restated, so a 3 AM reminder does not claim the episode is still upcoming at 7 AM.
    static func deferPastQuietHours(
        _ alert: PlannedAlert,
        prefs: NotificationPreferences,
        calendar: Calendar
    ) -> PlannedAlert {
        guard let window = quietWindow(containing: alert.fireDate, prefs: prefs, calendar: calendar) else {
            return alert
        }
        var out = alert
        out.fireDate = window.end
        // A held reminder is scheduled as a plain calendar alert, not a one-shot interval.
        out.isCatchUp = false
        if let air = alert.airDate, alert.isUrgent {
            let remaining = air.timeIntervalSince(window.end)
            if remaining <= 0 {
                out.body = "Aired at \(time(air, calendar: calendar))"
            } else if remaining < 3_600 {
                out.body = "Starts in \(max(1, Int((remaining / 60).rounded()))) minutes"
            } else {
                out.body = "Starts at \(time(air, calendar: calendar))"
            }
        }
        return out
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

    /// Formats using the system's 12/24-hour preference so banner bodies agree with the
    /// clock macOS prints beside them.
    static func time(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "j:mm", options: 0, locale: .current
        ) ?? "HH:mm"
        return formatter.string(from: date)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        dayKeyFormatter.timeZone = calendar.timeZone
        return dayKeyFormatter.string(from: date)
    }

    /// Notification strings come from provider data; trim the edges, collapse squashed
    /// whitespace runs, and keep banners readable.
    static func sanitized(_ value: String, limit: Int) -> String {
        let clean = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > limit else { return clean }
        return String(clean.prefix(limit - 1)) + "…"
    }
}
