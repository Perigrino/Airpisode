import Foundation

enum DiaryFilter: String, CaseIterable, Identifiable {
    case all, episodes, movies

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .episodes: return "Episodes"
        case .movies: return "Movies"
        }
    }

    func matches(_ entry: DiaryEntry) -> Bool {
        switch self {
        case .all: return true
        case .episodes: return entry.kind == .episode
        case .movies: return entry.kind == .movie
        }
    }
}

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

    func matches(search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [title.name, label, episode?.name ?? ""]
            .contains { $0.localizedStandardContains(query) }
    }
}

struct DiaryStats: Equatable {
    let lifetimeEpisodes: Int
    let lifetimeMovies: Int
    let episodesThisMonth: Int
    let moviesThisMonth: Int
    let currentStreak: Int
    let undatedCount: Int

    var monthTotal: Int { episodesThisMonth + moviesThisMonth }
    var lifetimeTotal: Int { lifetimeEpisodes + lifetimeMovies }
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

    /// Search and type filtering happen after the diary join, so legacy undated watchers are
    /// just as searchable as newly timestamped ones.
    func diaryEntries(
        now: Date = .now,
        filter: DiaryFilter,
        search: String
    ) -> [DiaryEntry] {
        diaryEntries(now: now).filter {
            filter.matches($0) && $0.matches(search: search)
        }
    }

    /// Counts only diary entries that still resolve to a title. Month and streak numbers use
    /// dated records exclusively; legacy records contribute only to lifetime and undated totals.
    func diaryStats(now: Date = .now, calendar: Calendar = .current) -> DiaryStats {
        let entries = diaryEntries(now: now)
        let episodes = entries.filter { $0.kind == .episode }
        let movies = entries.filter { $0.kind == .movie }
        let dated = entries.compactMap(\.date)

        let episodesThisMonth = episodes.filter {
            guard let date = $0.date else { return false }
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        }.count
        let moviesThisMonth = movies.filter {
            guard let date = $0.date else { return false }
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        }.count

        let days = Set(dated.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)
        var cursor = days.contains(today)
            ? today
            : calendar.date(byAdding: .day, value: -1, to: today)
        var streak = 0
        while let day = cursor, days.contains(day) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: day)
        }

        return DiaryStats(
            lifetimeEpisodes: episodes.count,
            lifetimeMovies: movies.count,
            episodesThisMonth: episodesThisMonth,
            moviesThisMonth: moviesThisMonth,
            currentStreak: streak,
            undatedCount: entries.filter { $0.date == nil }.count
        )
    }
}
