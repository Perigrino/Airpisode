import Foundation

/// Turns release-engine diffs into the small, deduplicated set worth showing the user.
///
/// The first refresh after a title is added sees every episode as "new", so only titles that
/// had a previous successful refresh are eligible. Future releases beyond a month are ignored:
/// a date six months out is useful in the library, but not as a "what changed" notification.
enum ScheduleChangeRecorder {
    static let horizon: TimeInterval = 30 * 86_400
    static let maxRecords = 50

    static func records(
        from changes: [ReleaseChange],
        library: Library,
        previouslyRefreshed: Set<String>,
        now: Date = .now
    ) -> [ScheduleChangeRecord] {
        var records: [ScheduleChangeRecord] = []
        for change in changes {
            let titleID: String
            let key: String
            let kind: ScheduleChangeRecord.Kind
            let date: Date?

            switch change {
            case let .newRelease(id, releaseKey, releaseDate, _):
                titleID = id
                key = releaseKey
                kind = .newRelease
                date = releaseDate
            case let .dateChanged(id, releaseKey, _, newDate, _):
                titleID = id
                key = releaseKey
                kind = .dateChanged
                date = newDate
            case .releasePassed:
                continue
            }

            guard previouslyRefreshed.contains(titleID),
                  let title = library.titles[titleID],
                  let date,
                  date > now,
                  date <= now.addingTimeInterval(horizon)
            else { continue }

            let label = label(for: key, titleID: titleID, mediaType: title.mediaType, library: library)
            records.append(ScheduleChangeRecord(
                id: "\(titleID)|\(key)|\(kind.rawValue)|\(Int(date.timeIntervalSince1970))",
                titleID: titleID,
                key: key,
                titleName: title.name,
                label: label,
                kind: kind,
                oldDate: oldDate(for: change),
                newDate: date,
                detectedAt: now,
                posterPath: title.posterPath
            ))
        }
        return records
    }

    /// Existing records win; new ones are prepended, newest first, and the list is capped.
    static func merge(
        _ newRecords: [ScheduleChangeRecord],
        into existing: [ScheduleChangeRecord]
    ) -> [ScheduleChangeRecord] {
        guard !newRecords.isEmpty else { return existing }
        var seen = Set(existing.map(\.id))
        var merged = existing
        for record in newRecords where seen.insert(record.id).inserted {
            merged.insert(record, at: 0)
        }
        return Array(merged.prefix(maxRecords))
    }

    private static func oldDate(for change: ReleaseChange) -> Date? {
        if case let .dateChanged(_, _, old, _, _) = change { return old }
        return nil
    }

    private static func label(
        for key: String,
        titleID: String,
        mediaType: MediaType,
        library: Library
    ) -> String {
        switch mediaType {
        case .tv:
            if let episode = (library.episodes[titleID] ?? []).first(where: { $0.id == key }) {
                return "S\(episode.seasonNumber)E\(episode.episodeNumber)"
            }
        case .movie:
            if let release = (library.movieReleases[titleID] ?? []).first(where: { $0.id == key }) {
                return release.kind.label
            }
        }
        return "release"
    }
}
