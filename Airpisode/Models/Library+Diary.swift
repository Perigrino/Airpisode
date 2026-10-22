import Foundation

/// A watch-log record joined to the title and episode/release it refers to. Records whose
/// title or episode is no longer loaded are skipped rather than shown as blank rows.
struct DiaryEntry: Identifiable {
    let record: WatchRecord
    let title: Title
    let episode: Episode?
    let release: MovieRelease?

    var id: String { record.id }
    var date: Date? { record.watchedAt }
    var kind: WatchRecord.Kind { record.kind }

    var label: String {
        switch record.kind {
        case .episode:
            guard let episode else { return "" }
            return "S\(episode.seasonNumber)E\(episode.episodeNumber) · \(episode.name)"
        case .movie:
            guard let release else { return "Movie" }
            return "\(release.kind.label) · \(release.region)"
        }
    }
}

extension Library {
    /// Everything marked watched, newest first. Legacy records without a timestamp sort last
    /// so the diary never invents a date the user did not provide.
    func diaryEntries(now: Date = .now) -> [DiaryEntry] {
        watchLog.compactMap { record -> DiaryEntry? in
            guard let title = titles[record.titleID] else { return nil }
            switch record.kind {
            case .episode:
                guard let episode = (episodes[record.titleID] ?? [])
                    .first(where: { $0.id == record.itemID })
                else { return nil }
                return DiaryEntry(record: record, title: title, episode: episode, release: nil)
            case .movie:
                let releases = (movieReleases[record.titleID] ?? []).filter { $0.date != nil }
                let release = releases
                    .filter { ($0.date ?? .distantFuture) <= now }
                    .min { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
                    ?? releases.min { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
                return DiaryEntry(record: record, title: title, episode: nil, release: release)
            }
        }
        .sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (left?, right?):
                if left != right { return left > right }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            if lhs.title.name != rhs.title.name { return lhs.title.name < rhs.title.name }
            return lhs.label < rhs.label
        }
    }
}
