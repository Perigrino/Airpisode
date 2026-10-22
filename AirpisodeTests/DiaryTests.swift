import XCTest
@testable import Airpisode

final class DiaryTests: XCTestCase {
    private let now = TMDBMapper.parseDate("2026-10-16")!

    private func days(_ offset: Int) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: now)!
    }

    private func makeLibrary() -> Library {
        var lib = Library()
        lib.titles["tv-100"] = Title(
            tmdbID: 100, mediaType: .tv, name: "Severance", overview: "", posterPath: "/sev.jpg",
            firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil
        )
        lib.titles["movie-200"] = Title(
            tmdbID: 200, mediaType: .movie, name: "Dune", overview: "", posterPath: "/dune.jpg",
            firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil
        )
        lib.episodes["tv-100"] = [
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                overview: nil, airDate: days(-10), stillPath: nil
            )
        ]
        lib.movieReleases["movie-200"] = [
            MovieRelease(tmdbID: 200, kind: .digital, region: "US", date: days(-2), hasTime: false)
        ]
        return lib
    }

    func testDiarySortsNewestFirstAndLegacyLast() {
        var lib = makeLibrary()
        lib.watchLog = [
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e5", watchedAt: days(-3)),
            WatchRecord(kind: .movie, titleID: "movie-200", itemID: "movie-200", watchedAt: days(-1)),
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e5", watchedAt: nil),
        ]

        let entries = lib.diaryEntries(now: now)

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].kind, .movie)
        XCTAssertEqual(entries[1].date, days(-3))
        XCTAssertNil(entries[2].date, "legacy records never get an invented date")
    }

    func testDiaryLabelsEpisodesAndMovies() {
        var lib = makeLibrary()
        lib.watchLog = [
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e5", watchedAt: now),
            WatchRecord(kind: .movie, titleID: "movie-200", itemID: "movie-200", watchedAt: now),
        ]

        let entries = lib.diaryEntries(now: now)
        XCTAssertEqual(entries.first(where: { $0.kind == .episode })?.label, "S2E5 · Woe's Hollow")
        XCTAssertEqual(entries.first(where: { $0.kind == .movie })?.label, "Digital · US")
    }

    func testDiarySkipsRecordsWhoseTitleOrEpisodeIsGone() {
        var lib = makeLibrary()
        lib.watchLog = [
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s9e9", watchedAt: now),
            WatchRecord(kind: .movie, titleID: "movie-999", itemID: "movie-999", watchedAt: now),
        ]

        XCTAssertTrue(lib.diaryEntries(now: now).isEmpty)
    }

    func testVersionTwoWatchedSetsBackfillUndatedDiaryRecords() {
        var lib = makeLibrary()
        lib.schemaVersion = 2
        lib.watchedEpisodes = ["100-s2e5"]
        lib.watchedMovies = ["movie-200"]

        XCTAssertTrue(lib.migrateSchemaIfNeeded())

        XCTAssertEqual(lib.schemaVersion, Library.currentSchemaVersion)
        XCTAssertEqual(lib.watchLog.count, 2)
        XCTAssertTrue(lib.watchLog.allSatisfy { $0.watchedAt == nil })
        XCTAssertEqual(
            Set(lib.watchLog.map(\.id)),
            ["episode:100-s2e5", "movie:movie-200"]
        )
        XCTAssertEqual(
            lib.watchLog.first(where: { $0.kind == .episode })?.titleID,
            "tv-100"
        )
    }
}
