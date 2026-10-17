import XCTest
@testable import Airpisode

final class LibraryHistoryTests: XCTestCase {
    private let now = TMDBMapper.parseDate("2026-10-16")!  // noon UTC

    private func days(_ offset: Int) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: now)!
    }

    private func makeLibrary() -> Library {
        var lib = Library()
        lib.titles["tv-100"] = Title(tmdbID: 100, mediaType: .tv, name: "Severance", overview: "",
                                     posterPath: nil, firstAirDate: nil, tvStatus: nil,
                                     seasons: [], lastRefreshed: nil)
        lib.titles["movie-200"] = Title(tmdbID: 200, mediaType: .movie, name: "Dune", overview: "",
                                        posterPath: nil, firstAirDate: nil, tvStatus: nil,
                                        seasons: [], lastRefreshed: nil)
        // The show has been tracked a while, so its older episodes are eligible history.
        // Movies have no addedAt cutoff.
        lib.entries = [
            WatchlistEntry(tmdbID: 100, mediaType: .tv, addedAt: days(-30), isTrackingEnabled: true),
            WatchlistEntry(tmdbID: 200, mediaType: .movie, addedAt: now, isTrackingEnabled: true),
        ]
        return lib
    }

    private func episode(_ season: Int, _ number: Int, airDate: Date?) -> Episode {
        Episode(tmdbID: 100, seasonNumber: season, episodeNumber: number, name: "E\(number)",
                overview: nil, airDate: airDate, stillPath: nil)
    }

    func testReleasedUnwatchedEpisodesSkipsFutureAndWatched() {
        var lib = makeLibrary()
        let aired = episode(1, 1, airDate: days(-3))
        let watched = episode(1, 2, airDate: days(-2))
        let future = episode(1, 3, airDate: days(4))
        lib.episodes["tv-100"] = [aired, watched, future]
        lib.watchedEpisodes.insert(watched.id)

        let released = lib.releasedUnwatchedEpisodes(now: now)

        XCTAssertEqual(released.map(\.id), [aired.id])
        XCTAssertEqual(released.first?.label, "S1E1 · E1")
        XCTAssertEqual(released.first?.title.name, "Severance")
    }

    func testReleasedUnwatchedEpisodesNewestFirst() {
        var lib = makeLibrary()
        lib.episodes["tv-100"] = [
            episode(1, 1, airDate: days(-9)),
            episode(1, 2, airDate: days(-1)),
            episode(1, 3, airDate: days(-5)),
        ]

        XCTAssertEqual(lib.releasedUnwatchedEpisodes(now: now).map(\.episode.episodeNumber), [2, 3, 1])
    }

    func testReleasedUnwatchedEpisodesSkipsUntrackedAndUndated() {
        var lib = makeLibrary()
        lib.entries[0].isTrackingEnabled = false
        lib.episodes["tv-100"] = [episode(1, 1, airDate: days(-1)), episode(1, 2, airDate: nil)]

        XCTAssertTrue(lib.releasedUnwatchedEpisodes(now: now).isEmpty)
    }

    func testReleasedUnwatchedMoviesUsesEarliestPastRelease() {
        var lib = makeLibrary()
        lib.movieReleases["movie-200"] = [
            MovieRelease(tmdbID: 200, kind: .digital, region: "US", date: days(-2), hasTime: false),
            MovieRelease(tmdbID: 200, kind: .physical, region: "US", date: days(5), hasTime: false),
        ]

        let released = lib.releasedUnwatchedMovies(now: now)

        XCTAssertEqual(released.map(\.id), ["movie-200"])
        XCTAssertEqual(released.first?.release.kind, .digital)
    }

    func testReleasedUnwatchedMoviesSkipsWatchedAndFuture() {
        var lib = makeLibrary()
        lib.movieReleases["movie-200"] = [
            MovieRelease(tmdbID: 200, kind: .theatrical, region: "US", date: days(3), hasTime: false)
        ]
        XCTAssertTrue(lib.releasedUnwatchedMovies(now: now).isEmpty, "a future release is not history yet")

        lib.movieReleases["movie-200"] = [
            MovieRelease(tmdbID: 200, kind: .digital, region: "US", date: days(-1), hasTime: false)
        ]
        lib.watchedMovies.insert("movie-200")
        XCTAssertTrue(lib.releasedUnwatchedMovies(now: now).isEmpty, "watched movies leave the history list")
    }

    func testIsWatchedHelpers() {
        var lib = makeLibrary()
        let watched = episode(2, 5, airDate: days(-1))
        lib.watchedEpisodes.insert(watched.id)
        lib.watchedMovies.insert("movie-200")

        XCTAssertTrue(lib.isWatched(watched))
        XCTAssertFalse(lib.isWatched(episode(2, 6, airDate: days(-1))))
        XCTAssertTrue(lib.isWatchedMovie("movie-200"))
        XCTAssertFalse(lib.isWatchedMovie("tv-100"))
    }

    func testMigrateLegacyWatchedStateMovesEpisodeIDs() {
        var lib = makeLibrary()
        lib.watchedShows = ["100-s2e5", "tv-100"]

        XCTAssertTrue(lib.migrateLegacyWatchedState())
        XCTAssertEqual(lib.watchedEpisodes, ["100-s2e5"])
        XCTAssertEqual(lib.watchedShows, ["tv-100"])

        XCTAssertFalse(lib.migrateLegacyWatchedState(), "migration is idempotent")
    }

    func testReleasedUnwatchedEpisodesSkipsEpisodesFromBeforeTheShowWasAdded() {
        var lib = makeLibrary()
        let beforeAdd = episode(1, 1, airDate: days(-40))  // aired before the show was tracked
        let afterAdd = episode(1, 2, airDate: days(-1))
        lib.episodes["tv-100"] = [beforeAdd, afterAdd]

        XCTAssertEqual(lib.releasedUnwatchedEpisodes(now: now).map(\.id), [afterAdd.id],
                       "History only covers what came out while tracking the show")
    }
}
