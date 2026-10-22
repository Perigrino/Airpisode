import XCTest
@testable import Airpisode

final class DiaryTests: XCTestCase {
    private let now = TMDBMapper.parseDate("2026-10-16")!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }()

    private func days(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
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
            ),
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 6, name: "Cold Harbor",
                overview: nil, airDate: days(-9), stillPath: nil
            ),
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 7, name: "Day 7",
                overview: nil, airDate: days(-8), stillPath: nil
            ),
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

        let entries = lib.diaryEntries(now: now, calendar: calendar)

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

        let entries = lib.diaryEntries(now: now, calendar: calendar)
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

    func testDiarySearchMatchesShowEpisodeAndMovie() {
        var lib = makeLibrary()
        lib.watchLog = [
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e5", watchedAt: now),
            WatchRecord(kind: .movie, titleID: "movie-200", itemID: "movie-200", watchedAt: now),
        ]

        XCTAssertEqual(lib.diaryEntries(now: now, filter: .all, search: "severance").count, 1)
        XCTAssertEqual(lib.diaryEntries(now: now, filter: .all, search: "woe").count, 1)
        XCTAssertEqual(lib.diaryEntries(now: now, filter: .all, search: "dune").count, 1)
        XCTAssertEqual(lib.diaryEntries(now: now, filter: .all, search: "digital").count, 1)
        XCTAssertEqual(
            lib.diaryEntries(now: now, filter: .all, search: "  WOE  ").count, 1,
            "search trims whitespace and ignores case"
        )
    }

    func testDiaryFilterSeparatesEpisodesAndMovies() {
        var lib = makeLibrary()
        lib.watchLog = [
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e5", watchedAt: now),
            WatchRecord(kind: .movie, titleID: "movie-200", itemID: "movie-200", watchedAt: now),
        ]

        XCTAssertEqual(lib.diaryEntries(now: now, filter: .all, search: "").count, 2)
        XCTAssertEqual(lib.diaryEntries(now: now, filter: .episodes, search: "").count, 1)
        XCTAssertEqual(lib.diaryEntries(now: now, filter: .movies, search: "").count, 1)
        XCTAssertTrue(lib.diaryEntries(now: now, filter: .episodes, search: "dune").isEmpty)
    }

    func testDiaryStatsCountLifetimeMonthAndUndated() {
        var lib = makeLibrary()
        lib.watchLog = [
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e5", watchedAt: days(-1)),
            WatchRecord(kind: .movie, titleID: "movie-200", itemID: "movie-200", watchedAt: days(-2)),
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e6", watchedAt: days(-40)),
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e7", watchedAt: nil),
        ]

        lib.rebuildWatchSummary(calendar: calendar)
        let stats = lib.diaryStats(now: now, calendar: calendar)

        XCTAssertEqual(stats.lifetimeEpisodes, 3)
        XCTAssertEqual(stats.lifetimeMovies, 1)
        XCTAssertEqual(stats.lifetimeTotal, 4)
        XCTAssertEqual(stats.episodesThisMonth, 1)
        XCTAssertEqual(stats.moviesThisMonth, 1)
        XCTAssertEqual(stats.monthTotal, 2)
        XCTAssertEqual(stats.undatedCount, 1)
        XCTAssertEqual(stats.currentStreak, 2, "Oct 15 + Oct 14, starting yesterday")
    }

    func testDiaryStatsStreakResetsAfterGapAndCountsToday() {
        var lib = makeLibrary()
        lib.watchLog = [
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e5", watchedAt: days(0)),
            WatchRecord(kind: .movie, titleID: "movie-200", itemID: "movie-200", watchedAt: days(-3)),
        ]

        lib.rebuildWatchSummary(calendar: calendar)
        let stats = lib.diaryStats(now: now, calendar: calendar)

        XCTAssertEqual(stats.currentStreak, 1, "today counts, the three-day-old watch does not")
    }

    func testDiaryStatsUndatedOnlyHasNoMonthOrStreak() {
        var lib = makeLibrary()
        lib.watchLog = [
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e5", watchedAt: nil),
        ]

        lib.rebuildWatchSummary(calendar: calendar)
        let stats = lib.diaryStats(now: now, calendar: calendar)

        XCTAssertEqual(stats.lifetimeEpisodes, 1)
        XCTAssertEqual(stats.lifetimeMovies, 0)
        XCTAssertEqual(stats.monthTotal, 0)
        XCTAssertEqual(stats.currentStreak, 0)
        XCTAssertEqual(stats.undatedCount, 1)
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
        XCTAssertTrue(lib.watchDays.isEmpty)
        XCTAssertEqual(lib.undatedWatchCount, 2)
    }

    func testPruneKeepsSevenCalendarDaysAndUndatedRecords() {
        var lib = makeLibrary()
        lib.watchLog = [
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e5", watchedAt: days(0)),
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e6", watchedAt: days(-6)),
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e7", watchedAt: days(-7)),
            WatchRecord(kind: .movie, titleID: "movie-200", itemID: "movie-200", watchedAt: nil),
        ]
        lib.rebuildWatchSummary(calendar: calendar)
        let statsBefore = lib.diaryStats(now: now, calendar: calendar)

        let removed = lib.pruneWatchLog(now: now, calendar: calendar)

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(lib.watchLog.count, 3)
        XCTAssertTrue(lib.watchLog.contains { $0.watchedAt == nil })
        XCTAssertFalse(lib.watchLog.contains { $0.itemID == "100-s2e7" })
        XCTAssertEqual(lib.watchDays, [
            WatchDaySummary(day: calendar.startOfDay(for: days(-7)), episodes: 1, movies: 0),
            WatchDaySummary(day: calendar.startOfDay(for: days(-6)), episodes: 1, movies: 0),
            WatchDaySummary(day: calendar.startOfDay(for: days(0)), episodes: 1, movies: 0),
        ])
        XCTAssertEqual(lib.diaryStats(now: now, calendar: calendar), statsBefore)
    }

    func testDiaryDetailHidesDatedRecordsOutsideSevenDays() {
        var lib = makeLibrary()
        lib.watchLog = [
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e5", watchedAt: days(-6)),
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e6", watchedAt: days(-7)),
            WatchRecord(kind: .movie, titleID: "movie-200", itemID: "movie-200", watchedAt: nil),
        ]

        let entries = lib.diaryEntries(now: now, calendar: calendar)

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains { $0.record.watchedAt == nil })
        XCTAssertFalse(entries.contains { $0.record.itemID == "100-s2e6" })
    }

    func testVersionThreeWatchLogBackfillsDailySummary() {
        var lib = makeLibrary()
        lib.schemaVersion = 3
        lib.watchLog = [
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e5", watchedAt: days(-1)),
            WatchRecord(kind: .movie, titleID: "movie-200", itemID: "movie-200", watchedAt: days(-2)),
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s2e7", watchedAt: nil),
        ]

        XCTAssertTrue(lib.migrateSchemaIfNeeded(calendar: calendar))

        XCTAssertEqual(lib.schemaVersion, 4)
        XCTAssertEqual(lib.watchDays, [
            WatchDaySummary(day: calendar.startOfDay(for: days(-2)), episodes: 0, movies: 1),
            WatchDaySummary(day: calendar.startOfDay(for: days(-1)), episodes: 1, movies: 0),
        ])
        XCTAssertEqual(lib.undatedWatchCount, 1)
        XCTAssertEqual(lib.diaryStats(now: now, calendar: calendar).lifetimeTotal, 3)
    }
}
