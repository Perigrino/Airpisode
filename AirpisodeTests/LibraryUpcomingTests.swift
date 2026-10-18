import XCTest
@testable import Airpisode

final class LibraryUpcomingTests: XCTestCase {
    private let now = TMDBMapper.parseDate("2026-10-16")!  // noon UTC

    private func future(_ days: Int) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: now)!
    }

    private func makeLibrary() -> Library {
        var lib = Library()
        lib.titles["tv-100"] = Title(tmdbID: 100, mediaType: .tv, name: "Severance", overview: "", posterPath: nil, firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil)
        lib.titles["movie-200"] = Title(tmdbID: 200, mediaType: .movie, name: "Dune", overview: "", posterPath: nil, firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil)
        lib.entries = [
            WatchlistEntry(tmdbID: 100, mediaType: .tv, addedAt: now, isTrackingEnabled: true),
            WatchlistEntry(tmdbID: 200, mediaType: .movie, addedAt: now, isTrackingEnabled: true),
        ]
        return lib
    }

    func testNextEpisodeIsEarliestFutureEpisode() {
        var lib = makeLibrary()
        lib.episodes["tv-100"] = [
            Episode(tmdbID: 100, seasonNumber: 1, episodeNumber: 1, name: "Aired", overview: nil, airDate: future(-7), stillPath: nil),
            Episode(tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Soon", overview: nil, airDate: future(3), stillPath: nil),
            Episode(tmdbID: 100, seasonNumber: 2, episodeNumber: 6, name: "Later", overview: nil, airDate: future(10), stillPath: nil),
        ]
        XCTAssertEqual(lib.nextEpisode(forTitle: "tv-100", now: now)?.episodeNumber, 5)
    }

    func testNextEpisodeSkipsWatchedAndUndated() {
        var lib = makeLibrary()
        let upcoming = Episode(tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Soon", overview: nil, airDate: future(3), stillPath: nil)
        lib.episodes["tv-100"] = [
            upcoming,
            Episode(tmdbID: 100, seasonNumber: 2, episodeNumber: 6, name: "No date", overview: nil, airDate: nil, stillPath: nil),
        ]
        lib.watchedEpisodes.insert(upcoming.id)
        XCTAssertNil(lib.nextEpisode(forTitle: "tv-100", now: now))
    }

    func testUpcomingReleasesIncludesDateOnlyMovieAsUntimed() {
        var lib = makeLibrary()
        // Timed TV episode (episodes are date-only in TMDB → isTimed false).
        lib.episodes["tv-100"] = [
            Episode(tmdbID: 100, seasonNumber: 2, episodeNumber: 1, name: "Premiere", overview: nil, airDate: future(1), stillPath: nil)
        ]
        // Movie with only a date-only release.
        lib.movieReleases["movie-200"] = [
            MovieRelease(tmdbID: 200, kind: .digital, region: "US", date: future(5), hasTime: false)
        ]
        let items = lib.upcomingReleases(now: now)
        XCTAssertEqual(items.count, 2)
        let movie = items.first { $0.title.id == "movie-200" }
        XCTAssertEqual(movie?.isTimed, false)
        XCTAssertEqual(movie?.label, "Digital")
        // Sorted by date: episode (day 1) before movie (day 5).
        XCTAssertEqual(items.first?.title.id, "tv-100")
    }

    func testUpcomingReleasesSkipsPastAndTimedMovieFlag() {
        var lib = makeLibrary()
        lib.episodes["tv-100"] = [
            Episode(tmdbID: 100, seasonNumber: 1, episodeNumber: 1, name: "Aired", overview: nil, airDate: future(-1), stillPath: nil)
        ]
        lib.movieReleases["movie-200"] = [
            MovieRelease(tmdbID: 200, kind: .theatrical, region: "US", date: future(2), hasTime: true),
            MovieRelease(tmdbID: 200, kind: .physical, region: "US", date: future(-3), hasTime: false),
        ]
        let items = lib.upcomingReleases(now: now)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title.id, "movie-200")
        XCTAssertEqual(items[0].isTimed, true)
        XCTAssertEqual(items[0].label, "Theatrical")
    }

    func testUpcomingReleasesUsesNextAiringSeasonPremiere() {
        var lib = makeLibrary()
        // Season ended; that season's episodes aired, and the next season isn't fetched
        // (or TMDB has no episodes for it yet) — but TMDB knows the premiere date.
        lib.titles["tv-100"]?.nextAiring = Episode(
            tmdbID: 100, seasonNumber: 7, episodeNumber: 1,
            name: "Season 7 Premiere", overview: nil, airDate: future(120), stillPath: nil
        )
        let items = lib.upcomingReleases(now: now)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title.id, "tv-100")
        XCTAssertEqual(items[0].label, "S7E1 · Season 7 Premiere")
        XCTAssertEqual(items[0].isTimed, false)
    }

    func testNextAiringIgnoredWhenPastOrWhenFetchedEpisodeCovers() {
        var lib = makeLibrary()
        // Past date (e.g. the last aired episode of an ended show) → no upcoming item.
        lib.titles["tv-100"]?.nextAiring = Episode(
            tmdbID: 100, seasonNumber: 2, episodeNumber: 8,
            name: "Finale", overview: nil, airDate: future(-30), stillPath: nil
        )
        XCTAssertTrue(lib.upcomingReleases(now: now).filter { $0.title.id == "tv-100" }.isEmpty)
        // A fetched upcoming episode wins over the raw nextAiring stub.
        lib.titles["tv-100"]?.nextAiring = Episode(
            tmdbID: 100, seasonNumber: 7, episodeNumber: 1,
            name: "Season 7 Premiere", overview: nil, airDate: future(120), stillPath: nil
        )
        lib.episodes["tv-100"] = [
            Episode(tmdbID: 100, seasonNumber: 2, episodeNumber: 9, name: "Soon", overview: nil, airDate: future(3), stillPath: nil)
        ]
        let items = lib.upcomingReleases(now: now)
        XCTAssertEqual(items.first { $0.title.id == "tv-100" }?.label, "S2E9 · Soon")
    }
}
