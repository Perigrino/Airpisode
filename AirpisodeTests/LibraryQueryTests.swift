import XCTest
@testable import Airpisode

final class LibraryQueryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)  // fixed "today"
    private let day: TimeInterval = 86_400

    private func makeLibrary() -> Library {
        // Astra: currently airing — an aired-but-unwatched episode (after it was added)
        // plus a future one, so it lands in Airing soon AND Not caught up.
        var library = Library()
        library.titles["tv-1"] = Title(
            tmdbID: 1, mediaType: .tv, name: "Astra", overview: "", posterPath: nil,
            firstAirDate: nil, tvStatus: "Returning Series", seasons: [], lastRefreshed: nil
        )
        library.titles["tv-2"] = Title(
            tmdbID: 2, mediaType: .tv, name: "Boreal", overview: "", posterPath: nil,
            firstAirDate: nil, tvStatus: "Ended", seasons: [], lastRefreshed: nil
        )
        library.titles["movie-3"] = Title(
            tmdbID: 3, mediaType: .movie, name: "Cinema", overview: "", posterPath: nil,
            firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil
        )
        library.titles["movie-4"] = Title(
            tmdbID: 4, mediaType: .movie, name: "Drift", overview: "", posterPath: nil,
            firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil
        )
        library.titles["movie-5"] = Title(
            tmdbID: 5, mediaType: .movie, name: "Echo", overview: "", posterPath: nil,
            firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil
        )

        library.entries = [
            WatchlistEntry(tmdbID: 1, mediaType: .tv, addedAt: now - 12 * day, isTrackingEnabled: true),
            WatchlistEntry(tmdbID: 2, mediaType: .tv, addedAt: now - 3 * day, isTrackingEnabled: true),
            WatchlistEntry(tmdbID: 3, mediaType: .movie, addedAt: now - 5 * day, isTrackingEnabled: true),
            WatchlistEntry(tmdbID: 4, mediaType: .movie, addedAt: now - 1 * day, isTrackingEnabled: true),
            WatchlistEntry(tmdbID: 5, mediaType: .movie, addedAt: now - 2 * day, isTrackingEnabled: true),
        ]

        let airedStale = Episode(tmdbID: 1, seasonNumber: 1, episodeNumber: 1, name: "Pilot",
                                 overview: nil, airDate: now - 10 * day, stillPath: nil)
        let upcoming = Episode(tmdbID: 1, seasonNumber: 1, episodeNumber: 2, name: "Next",
                               overview: nil, airDate: now + 7 * day, stillPath: nil)
        library.episodes["tv-1"] = [airedStale, upcoming]

        let watchedOld = Episode(tmdbID: 2, seasonNumber: 1, episodeNumber: 1, name: "Finale",
                                 overview: nil, airDate: now - 60 * day, stillPath: nil)
        library.episodes["tv-2"] = [watchedOld]
        library.watchedEpisodes.insert(watchedOld.id)

        library.movieReleases["movie-3"] = [MovieRelease(
            tmdbID: 3, kind: .digital, region: "US", date: now + 20 * day, hasTime: true)]
        library.movieReleases["movie-4"] = [MovieRelease(
            tmdbID: 4, kind: .physical, region: "US", date: now - 90 * day, hasTime: false)]
        library.movieReleases["movie-5"] = [MovieRelease(
            tmdbID: 5, kind: .digital, region: "GB", date: now - 30 * day, hasTime: false)]
        library.watchedMovies.insert("movie-5")

        return library
    }

    // MARK: - Search

    func testSearchMatchesTitlesCaseInsensitivelyAndAcrossMediaTypes() {
        let library = makeLibrary()
        XCTAssertEqual(library.queryShows(searchText: "AST", filter: .all, sort: .name, now: now).map(\.name), ["Astra"])
        XCTAssertEqual(library.queryMovies(searchText: "dr", filter: .all, sort: .name, now: now).map(\.name), ["Drift"])
        // Blank search is a pass-through.
        XCTAssertEqual(library.queryShows(searchText: "   ", filter: .all, sort: .name, now: now).count, 2)
    }

    // MARK: - Show filters

    func testShowFilterBuckets() {
        let library = makeLibrary()
        XCTAssertEqual(library.queryShows(searchText: "", filter: .airingSoon, sort: .name, now: now).map(\.name), ["Astra"])
        // Boreal's only episode was watched, so nothing is unwatched to catch up on.
        XCTAssertEqual(library.queryShows(searchText: "", filter: .notCaughtUp, sort: .name, now: now).map(\.name), ["Astra"])
        XCTAssertEqual(library.queryShows(searchText: "", filter: .ended, sort: .name, now: now).map(\.name), ["Boreal"])
    }

    func testEndedShowWithFutureAiringDoesNotCountAsEnded() {
        var library = makeLibrary()
        // Give the "ended" show a surprise premiere via nextAiring — it must leave the
        // Ended bucket and land in Airing soon instead.
        library.titles["tv-2"]?.nextAiring = Episode(
            tmdbID: 2, seasonNumber: 2, episodeNumber: 1, name: "Revival",
            overview: nil, airDate: now + 30 * day, stillPath: nil
        )
        let shows = library.queryShows(searchText: "", filter: .ended, sort: .name, now: now).map(\.name)
        XCTAssertFalse(shows.contains("Boreal"))
        XCTAssertEqual(library.queryShows(searchText: "", filter: .airingSoon, sort: .name, now: now).map(\.name),
                       ["Astra", "Boreal"])
    }

    /// An episode that aired BEFORE the show was tracked is deliberately not "not caught up"
    /// — History is about what came out while you have been tracking it.
    func testNotCaughtUpIgnoresEpisodesAiredBeforeTheEntryWasAdded() {
        var library = makeLibrary()
        library.watchedEpisodes.removeAll()
        // Astra's pilot aired at now-10d but the show is only tracked from now-2d, so the
        // pilot predates tracking; Boreal's finale predates its entry too. Nobody is behind.
        library.entries[0].addedAt = now - 2 * day
        XCTAssertEqual(
            library.queryShows(searchText: "", filter: .notCaughtUp, sort: .name, now: now).map(\.name),
            []
        )
    }

    // MARK: - Movie filters

    func testMovieFilterBuckets() {
        let library = makeLibrary()
        XCTAssertEqual(library.queryMovies(searchText: "", filter: .comingUp, sort: .name, now: now).map(\.name), ["Cinema"])
        XCTAssertEqual(library.queryMovies(searchText: "", filter: .released, sort: .name, now: now).map(\.name), ["Drift"])
        XCTAssertEqual(library.queryMovies(searchText: "", filter: .watched, sort: .name, now: now).map(\.name), ["Echo"])
    }

    // MARK: - Sorting

    func testRecentlyAddedSortUsesEntryAddedAtDescending() {
        let library = makeLibrary()
        XCTAssertEqual(library.queryShows(searchText: "", filter: .all, sort: .recentlyAdded, now: now).map(\.name),
                       ["Boreal", "Astra"])  // added 3d ago vs 12d ago
        XCTAssertEqual(library.queryMovies(searchText: "", filter: .all, sort: .recentlyAdded, now: now).map(\.name),
                       ["Drift", "Echo", "Cinema"])  // 1d, 2d, 5d
    }

    func testNextUpSortOrdersBySoonestDateWithNilsLast() {
        let library = makeLibrary()
        // Astra: next episode +7d; Boreal: nothing future → last.
        XCTAssertEqual(library.queryShows(searchText: "", filter: .all, sort: .nextUp, now: now).map(\.name),
                       ["Astra", "Boreal"])
        // Cinema at +20d beats Drift/Echo (past → nothing coming → last); past releases sort last.
        let movies = library.queryMovies(searchText: "", filter: .all, sort: .nextUp, now: now).map(\.name)
        XCTAssertEqual(movies.first, "Cinema")
        XCTAssertEqual(movies.count, 3)
    }
}
