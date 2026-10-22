import Foundation
import UserNotifications

struct NotificationDiagnosticRow: Identifiable {
    enum Severity {
        case info, warning
    }

    let id: String
    let severity: Severity
    let title: String
    let detail: String
}

struct NotificationDiagnosticsReport {
    let authorization: UNAuthorizationStatus
    let permissionRequested: Bool
    let pending: [PendingAlert]
    let rows: [NotificationDiagnosticRow]

    var scheduledCount: Int { pending.filter { NotificationScheduler.isManagedID($0.id) }.count }
}

/// Explains why an alert did or did not get scheduled. Pure over the library snapshot plus
/// the two facts only the system knows: authorization and pending requests.
enum NotificationDiagnostics {
    static func report(
        library: Library,
        authorization: UNAuthorizationStatus,
        pending: [PendingAlert],
        now: Date = .now
    ) -> NotificationDiagnosticsReport {
        var rows: [NotificationDiagnosticRow] = []
        let prefs = library.preferences

        switch authorization {
        case .denied:
            rows.append(.init(
                id: "permission",
                severity: .warning,
                title: "Notifications are denied",
                detail: "Enable Airpisode in System Settings → Notifications. Alerts cannot appear until then."
            ))
        case .notDetermined:
            rows.append(.init(
                id: "permission",
                severity: .warning,
                title: "Notification permission has not been granted",
                detail: "Use Enable Notifications above, then send a test alert."
            ))
        case .authorized, .provisional, .ephemeral:
            rows.append(.init(
                id: "permission",
                severity: .info,
                title: "Notification permission is granted",
                detail: "The system will deliver alerts scheduled below."
            ))
        @unknown default:
            rows.append(.init(
                id: "permission",
                severity: .warning,
                title: "Notification permission state is unknown",
                detail: "Open System Settings → Notifications → Airpisode to check."
            ))
        }

        if !prefs.permissionRequested {
            rows.append(.init(
                id: "requested",
                severity: .warning,
                title: "Airpisode has not requested permission",
                detail: "Turn on notifications once; scheduling is skipped until then."
            ))
        }

        let managed = pending.filter { NotificationScheduler.isManagedID($0.id) }
        if managed.count > NotificationPlanner.maxPending {
            rows.append(.init(
                id: "cap",
                severity: .warning,
                title: "Too many pending alerts",
                detail: "\(managed.count) are queued. macOS keeps only the soonest 64 and discards the rest; Airpisode caps its plan at \(NotificationPlanner.maxPending)."
            ))
        } else if managed.isEmpty && prefs.permissionRequested {
            rows.append(.init(
                id: "empty",
                severity: .warning,
                title: "No alerts are scheduled",
                detail: "Either nothing is upcoming, the titles are muted, or their releases only have a date and no air time yet."
            ))
        } else {
            rows.append(.init(
                id: "pending",
                severity: .info,
                title: "\(managed.count) alert\(managed.count == 1 ? "" : "s") scheduled",
                detail: "The soonest appears below. Airpisode keeps the plan below the system's 64-request limit."
            ))
        }

        let muted = library.entries.filter { library.isMuted($0.id) }.compactMap { library.titles[$0.id]?.name }
        if !muted.isEmpty {
            rows.append(.init(
                id: "muted",
                severity: .info,
                title: "\(muted.count) muted title\(muted.count == 1 ? "" : "s")",
                detail: muted.prefix(3).joined(separator: ", ")
            ))
        }

        let dateOnly = dateOnlyTitles(library: library, now: now)
        if !dateOnly.isEmpty {
            rows.append(.init(
                id: "date-only",
                severity: .info,
                title: "\(dateOnly.count) show\(dateOnly.count == 1 ? " has" : "s have") no exact air time yet",
                detail: "\(dateOnly.prefix(3).joined(separator: ", ")). TVmaze has not returned a broadcast time, so only date-based summaries can be scheduled."
            ))
        }

        let noUpcoming = library.entries.filter { entry in
            guard entry.isTrackingEnabled, let title = library.titles[entry.id] else { return false }
            switch entry.mediaType {
            case .tv:
                return !(library.episodes[entry.id] ?? []).contains {
                    ($0.airTimestamp ?? $0.airDate ?? .distantPast) > now
                } && !(title.nextAiring?.airDate.map { $0 > now } ?? false)
            case .movie:
                return !(library.movieReleases[entry.id] ?? []).contains { ($0.date ?? .distantPast) > now }
            }
        }.compactMap { library.titles[$0.id]?.name }
        if !noUpcoming.isEmpty {
            rows.append(.init(
                id: "none-upcoming",
                severity: .info,
                title: "\(noUpcoming.count) tracked title\(noUpcoming.count == 1 ? "" : "s") have nothing upcoming",
                detail: noUpcoming.prefix(3).joined(separator: ", ")
            ))
        }

        return NotificationDiagnosticsReport(
            authorization: authorization,
            permissionRequested: prefs.permissionRequested,
            pending: pending.sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) },
            rows: rows
        )
    }

    private static func dateOnlyTitles(library: Library, now: Date) -> [String] {
        library.entries.compactMap { entry in
            guard entry.mediaType == .tv,
                  entry.isTrackingEnabled,
                  let title = library.titles[entry.id]
            else { return nil }
            let future = (library.episodes[entry.id] ?? []).filter {
                ($0.airTimestamp ?? $0.airDate ?? .distantPast) > now
            }
            guard !future.isEmpty else { return nil }
            let allDateOnly = future.allSatisfy {
                $0.airTimestamp == nil && ($0.airDate.map(NotificationScheduler.isDateOnlyEncoded) ?? true)
            }
            return allDateOnly ? title.name : nil
        }
    }
}
