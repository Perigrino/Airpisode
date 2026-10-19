import Foundation

/// Search, sort, and status filters for the My Shows / My Movies lists.
/// Pure functions over the library (pattern: Library+Upcoming, Library+History) so the
/// behaviour is unit-testable without any view involvement.
extension Library {
    enum LibrarySort: String, CaseIterable, Identifiable {
        case name, recentlyAdded, nextUp

        var id: String { rawValue }

        var label: String {
            switch self {
            case .name: return "Name"
            case .recentlyAdded: return "Recently added"
            case .nextUp: return "Next air date"
            }
        }
    }

    enum ShowFilter: String, CaseIterable, Identifiable {
        case all, airingSoon, notCaughtUp, ended

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All"
            case .airingSoon: return "Airing soon"
            case .notCaughtUp: return "Not caught up"
            case .ended: return "Ended"
            }
        }
    }

    enum MovieFilter: String, CaseIterable, Identifiable {
        case all, comingUp, released, watched

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All"
            case .comingUp: return "Coming up"
            case .released: return "Released"
            case .watched: return "Watched"
            }
        }
    }

    /// Tracked shows that survive the search + filter, ordered by `sort`.
    ///
    /// - Airing soon: an episode is on the horizon (fetched, or the cross-show nextAiring
    ///   premiere). Not caught up: something aired while tracking and is still unwatched
    ///   (reuses the To Watch page's definition). Ended: TMDB says Ended/Canceled AND
    ///   nothing is upcoming, so an "ended" show with a surpise return is still Airing soon.
    func queryShows(
        searchText: String,
        filter: ShowFilter,
        sort: LibrarySort,
        now: Date = .now
    ) -> [Title] {
        let behindIDs = Set(releasedUnwatchedEpisodes(now: now).map { $0.title.id })
        return query(mediaType: .tv, searchText: searchText, sort: sort, now: now) { title, entry in
            switch filter {
            case .all:
                return true
            case .airingSoon:
                return hasFutureAiring(title: title, titleID: entry.id, now: now)
            case .notCaughtUp:
                return behindIDs.contains(entry.id)
            case .ended:
                let ended = title.tvStatus == "Ended" || title.tvStatus == "Canceled"
                return ended && !hasFutureAiring(title: title, titleID: entry.id, now: now)
            }
        }
    }

    /// Tracked movies that survive the search + filter, ordered by `sort`.
    ///
    /// - Coming up: a future release or future firstAirDate. Released: has a past release
    ///   while still unwatched (mirrors the To Watch page). Watched: explicitly marked.
    func queryMovies(
        searchText: String,
        filter: MovieFilter,
        sort: LibrarySort,
        now: Date = .now
    ) -> [Title] {
        let releasedIDs = Set(releasedUnwatchedMovies(now: now).map { $0.title.id })
        return query(mediaType: .movie, searchText: searchText, sort: sort, now: now) { title, entry in
            switch filter {
            case .all:
                return true
            case .comingUp:
                return hasFutureRelease(title: title, titleID: entry.id, now: now)
            case .released:
                return releasedIDs.contains(entry.id)
            case .watched:
                return watchedMovies.contains(entry.id)
            }
        }
    }

    // MARK: - Core

    private func query(
        mediaType: MediaType,
        searchText: String,
        sort: LibrarySort,
        now: Date,
        matches filter: (Title, WatchlistEntry) -> Bool
    ) -> [Title] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [(title: Title, entry: WatchlistEntry)] = []
        for entry in entries where entry.mediaType == mediaType {
            guard let title = titles[entry.id] else { continue }
            if !needle.isEmpty, !title.name.localizedCaseInsensitiveContains(needle) { continue }
            if filter(title, entry) { results.append((title, entry)) }
        }
        switch sort {
        case .name:
            return results.map(\.title).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .recentlyAdded:
            return results.sorted { $0.entry.addedAt > $1.entry.addedAt }.map(\.title)
        case .nextUp:
            return results
                .map { (title: $0.title, date: nextDate(for: $0.title, titleID: $0.entry.id, now: now)) }
                .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
                .map(\.title)
        }
    }

    // MARK: - Predicates

    private func hasFutureAiring(title: Title, titleID: String, now: Date) -> Bool {
        if nextEpisode(forTitle: titleID, now: now) != nil { return true }
        return title.nextAiring.flatMap { $0.airDate }.map { $0 >= now } == true
    }

    private func hasFutureRelease(title: Title, titleID: String, now: Date) -> Bool {
        if (movieReleases[titleID] ?? []).contains(where: { ($0.date ?? .distantPast) >= now }) { return true }
        return title.firstAirDate.map { $0 >= now } == true
    }

    /// The soonest thing that could happen for this title — the "Next air date" sort key.
    /// nil when TMDB lists nothing in the future, and nils sort last.
    private func nextDate(for title: Title, titleID: String, now: Date) -> Date? {
        if title.mediaType == .tv {
            if let episode = nextEpisode(forTitle: titleID, now: now) { return episode.airDate }
            if let date = title.nextAiring?.airDate, date >= now { return date }
            return nil
        }
        if let release = (movieReleases[titleID] ?? [])
            .filter({ ($0.date ?? .distantPast) >= now })
            .min(by: { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }) {
            return release.date
        }
        if let date = title.firstAirDate, date >= now { return date }
        return nil
    }

    // MARK: - Row controls

    func isMuted(_ titleID: String) -> Bool {
        entries.first { $0.id == titleID }?.alertsMuted ?? false
    }

    func isPinned(_ titleID: String) -> Bool {
        entries.first { $0.id == titleID }?.pinnedAt != nil
    }

    /// Pin is display-only ordering: pinned rows rise to the top while every other row keeps
    /// whichever sort the list is showing.
    func orderedWithPinnedFirst(_ titles: [Title]) -> [Title] {
        titles.filter { isPinned($0.id) } + titles.filter { !isPinned($0.id) }
    }
}
