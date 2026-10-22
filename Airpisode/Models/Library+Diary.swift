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
    static let diaryDetailDays = 7

    /// Start of the oldest day still shown in the diary. Keeps today plus the previous six
    /// calendar days.
    func diaryCutoff(now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(Self.diaryDetailDays - 1), to: today)
            ?? today
    }

    /// Recent diary detail, newest first. Legacy records without a timestamp sort last so the
    /// diary never invents a date the user did not provide. Dated records outside the rolling
    /// window are hidden even if pruning has not run yet.
    func diaryEntries(now: Date = .now, calendar: Calendar = .current) -> [DiaryEntry] {
        let cutoff = diaryCutoff(now: now, calendar: calendar)
        return watchLog.compactMap { record -> DiaryEntry? in
            if let watchedAt = record.watchedAt, watchedAt < cutoff { return nil }
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
        calendar: Calendar = .current,
        filter: DiaryFilter,
        search: String
    ) -> [DiaryEntry] {
        diaryEntries(now: now, calendar: calendar).filter {
            filter.matches($0) && $0.matches(search: search)
        }
    }

    /// Stats come from the compact daily history, so deleting older diary detail does not
    /// reduce lifetime, monthly, or streak numbers. Undated legacy records are retained and
    /// counted separately; they contribute to lifetime totals but never to a month or streak.
    func diaryStats(now: Date = .now, calendar: Calendar = .current) -> DiaryStats {
        let undatedEntries = diaryEntries(now: now, calendar: calendar).filter { $0.date == nil }
        let undatedEpisodes = undatedEntries.filter { $0.kind == .episode }.count
        let undatedMovies = undatedEntries.filter { $0.kind == .movie }.count

        let lifetimeEpisodes = watchDays.reduce(0) { $0 + $1.episodes } + undatedEpisodes
        let lifetimeMovies = watchDays.reduce(0) { $0 + $1.movies } + undatedMovies
        let episodesThisMonth = watchDays.reduce(0) { total, summary in
            guard calendar.isDate(summary.day, equalTo: now, toGranularity: .month) else {
                return total
            }
            return total + summary.episodes
        }
        let moviesThisMonth = watchDays.reduce(0) { total, summary in
            guard calendar.isDate(summary.day, equalTo: now, toGranularity: .month) else {
                return total
            }
            return total + summary.movies
        }

        let days = Set(
            watchDays
                .filter { $0.episodes + $0.movies > 0 }
                .map { calendar.startOfDay(for: $0.day) }
        )
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
            lifetimeEpisodes: lifetimeEpisodes,
            lifetimeMovies: lifetimeMovies,
            episodesThisMonth: episodesThisMonth,
            moviesThisMonth: moviesThisMonth,
            currentStreak: streak,
            undatedCount: undatedEntries.count
        )
    }

    // MARK: - Compact history

    /// Rebuilds `watchDays` and `undatedWatchCount` from the detailed log. Used by schema
    /// migration and tests; normal mutations update the summary incrementally.
    mutating func rebuildWatchSummary(calendar: Calendar = .current) {
        watchDays = []
        undatedWatchCount = 0
        for record in watchLog {
            noteWatch(record, calendar: calendar)
        }
    }

    /// Adds one watch record to the compact history.
    mutating func noteWatch(_ record: WatchRecord, calendar: Calendar = .current) {
        guard let watchedAt = record.watchedAt else {
            undatedWatchCount += 1
            return
        }
        addWatch(kind: record.kind, on: watchedAt, calendar: calendar)
    }

    /// Removes one watch record from the compact history. Call this before dropping the record
    /// from `watchLog`.
    mutating func forgetWatch(_ record: WatchRecord, calendar: Calendar = .current) {
        guard let watchedAt = record.watchedAt else {
            undatedWatchCount = max(0, undatedWatchCount - 1)
            return
        }
        let day = calendar.startOfDay(for: watchedAt)
        guard let index = watchDays.firstIndex(where: {
            calendar.isDate($0.day, inSameDayAs: day)
        }) else { return }
        switch record.kind {
        case .episode:
            watchDays[index].episodes = max(0, watchDays[index].episodes - 1)
        case .movie:
            watchDays[index].movies = max(0, watchDays[index].movies - 1)
        }
        if watchDays[index].episodes == 0 && watchDays[index].movies == 0 {
            watchDays.remove(at: index)
        }
    }

    /// One diary record per item. Re-marking refreshes the timestamp and moves the daily count
    /// rather than duplicating it.
    mutating func upsertWatchRecord(
        kind: WatchRecord.Kind,
        titleID: String,
        itemID: String,
        watchedAt: Date,
        calendar: Calendar = .current
    ) {
        let id = "\(kind.rawValue):\(itemID)"
        if let index = watchLog.firstIndex(where: { $0.id == id }) {
            forgetWatch(watchLog[index], calendar: calendar)
            watchLog[index].watchedAt = watchedAt
            noteWatch(watchLog[index], calendar: calendar)
        } else {
            let record = WatchRecord(
                kind: kind, titleID: titleID, itemID: itemID, watchedAt: watchedAt
            )
            watchLog.append(record)
            noteWatch(record, calendar: calendar)
        }
    }

    /// Removes matching detail records while decrementing their compact-history contribution.
    mutating func removeWatchRecords(
        calendar: Calendar = .current,
        where shouldRemove: (WatchRecord) -> Bool
    ) {
        var kept: [WatchRecord] = []
        for record in watchLog {
            if shouldRemove(record) {
                forgetWatch(record, calendar: calendar)
            } else {
                kept.append(record)
            }
        }
        watchLog = kept
    }

    /// Permanently drops dated detail outside the rolling window. Undated legacy records stay,
    /// and the compact summary is intentionally untouched so lifetime stats survive.
    @discardableResult
    mutating func pruneWatchLog(now: Date = .now, calendar: Calendar = .current) -> Int {
        let cutoff = diaryCutoff(now: now, calendar: calendar)
        let before = watchLog.count
        watchLog.removeAll { record in
            guard let watchedAt = record.watchedAt else { return false }
            return watchedAt < cutoff
        }
        return before - watchLog.count
    }

    private mutating func addWatch(
        kind: WatchRecord.Kind,
        on date: Date,
        calendar: Calendar
    ) {
        let day = calendar.startOfDay(for: date)
        if let index = watchDays.firstIndex(where: {
            calendar.isDate($0.day, inSameDayAs: day)
        }) {
            switch kind {
            case .episode: watchDays[index].episodes += 1
            case .movie: watchDays[index].movies += 1
            }
        } else {
            watchDays.append(WatchDaySummary(
                day: day,
                episodes: kind == .episode ? 1 : 0,
                movies: kind == .movie ? 1 : 0
            ))
        }
        watchDays.sort { $0.day < $1.day }
    }
}
