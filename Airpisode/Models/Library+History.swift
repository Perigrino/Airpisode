import Foundation

/// An episode that has already aired but hasn't been marked watched.
///
/// These are the items that used to vanish: once an episode's air date passed it left the
/// Upcoming list and appeared nowhere else.
struct ReleasedEpisode: Identifiable {
    let title: Title
    let episode: Episode
    var id: String { episode.id }
    var date: Date? { episode.airMoment }
    var label: String { "S\(episode.seasonNumber)E\(episode.episodeNumber) · \(episode.name)" }
}

/// A movie that has already been released but hasn't been marked watched.
struct ReleasedMovie: Identifiable {
    let title: Title
    let release: MovieRelease
    var id: String { title.id }
    var date: Date? { release.date }
    var label: String { "\(release.kind.label) · \(release.region)" }
}

extension Library {
    /// Episodes that have aired since the show was added and haven't been marked watched,
    /// newest first. The `addedAt` cutoff keeps a long-running show's whole back catalogue
    /// from flooding the list — History is about what's come out while you've been tracking it.
    func releasedUnwatchedEpisodes(now: Date = .now) -> [ReleasedEpisode] {
        entries
            .filter { $0.isTrackingEnabled && $0.mediaType == .tv }
            .flatMap { entry -> [ReleasedEpisode] in
                guard let title = titles[entry.id] else { return [] }
                return (episodes[entry.id] ?? [])
                    .filter { episode in
                        // `airDate` alone is TMDB's date-only noon-UTC sentinel, so an
                        // episode that aired at 03:59 would stay hidden until noon. The
                        // exact TVmaze time (when known) is what listeners experienced.
                        guard let airDate = episode.airMoment, airDate <= now else { return false }
                        guard airDate >= entry.addedAt else { return false }
                        return !watchedEpisodes.contains(episode.id)
                    }
                    .map { ReleasedEpisode(title: title, episode: $0) }
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Released, unwatched movies across the whole watchlist, newest release first.
    func releasedUnwatchedMovies(now: Date = .now) -> [ReleasedMovie] {
        entries
            .filter { $0.isTrackingEnabled && $0.mediaType == .movie }
            .compactMap { entry -> ReleasedMovie? in
                guard let title = titles[entry.id], !watchedMovies.contains(entry.id) else { return nil }
                guard let release = (movieReleases[entry.id] ?? [])
                    .filter({ ($0.date ?? .distantFuture) <= now })
                    .min(by: { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) })
                else { return nil }
                return ReleasedMovie(title: title, release: release)
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    func isWatched(_ episode: Episode) -> Bool { watchedEpisodes.contains(episode.id) }
    func isWatchedMovie(_ titleID: String) -> Bool { watchedMovies.contains(titleID) }

    /// Earlier builds wrote episode IDs into `watchedShows`, which is otherwise title-level.
    /// Moves any such IDs into `watchedEpisodes` and reports whether anything changed.
    @discardableResult
    mutating func migrateLegacyWatchedState() -> Bool {
        let legacy = watchedShows.filter { $0.contains("-s") }
        guard !legacy.isEmpty else { return false }
        watchedEpisodes.formUnion(legacy)
        watchedShows.subtract(legacy)
        return true
    }
}
