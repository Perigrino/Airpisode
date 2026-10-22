import XCTest
@testable import Airpisode

final class NotificationPlannerTests: XCTestCase {
    private let now = TMDBMapper.parseDate("2026-10-16")!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }()

    private func library(
        overrides: AlertOverride? = nil,
        prefs: NotificationPreferences? = nil,
        watchedMovie: Bool = false,
        muted: Bool = false
    ) -> Library {
        var library = Library()
        library.preferences = prefs ?? NotificationPreferences(
            preAlertHours: 1, imminentAlertMinutes: nil, permissionRequested: true
        )
        let title = Title(
            tmdbID: 100, mediaType: .tv, name: "Severance", overview: "", posterPath: nil,
            firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil
        )
        library.titles[title.id] = title
        var entry = WatchlistEntry(
            tmdbID: 100, mediaType: .tv, addedAt: now, isTrackingEnabled: true
        )
        entry.preAlertOverride = overrides
        entry.alertsMuted = muted
        library.entries = [entry]
        library.episodes[title.id] = [
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                overview: nil, airDate: now.addingTimeInterval(86_400),
                airTimestamp: now.addingTimeInterval(10 * 3600), stillPath: nil
            )
        ]
        if watchedMovie {
            library.entries = [
                WatchlistEntry(tmdbID: 200, mediaType: .movie, addedAt: now, isTrackingEnabled: true)
            ]
            library.titles = [
                "movie-200": Title(
                    tmdbID: 200, mediaType: .movie, name: "Dune", overview: "", posterPath: nil,
                    firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil
                )
            ]
            library.movieReleases["movie-200"] = [
                MovieRelease(
                    tmdbID: 200, kind: .digital, region: "US",
                    date: now.addingTimeInterval(72 * 3600), hasTime: true
                )
            ]
            library.watchedMovies.insert("movie-200")
        }
        return library
    }

    func testPerShowOffSkipsPreAlert() {
        let plan = NotificationPlanner.plan(
            library: library(overrides: .off), now: now, calendar: calendar
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testPerShowOverrideBeatsGlobalSetting() {
        var lib = library(overrides: .twoDays)
        lib.episodes["tv-100"] = [
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                overview: nil, airDate: now.addingTimeInterval(72 * 3600),
                airTimestamp: now.addingTimeInterval(72 * 3600), stillPath: nil
            )
        ]
        let plan = NotificationPlanner.plan(library: lib, now: now, calendar: calendar)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].id, "pre-tv-100-100-s2e5")
        XCTAssertEqual(plan[0].fireDate, now.addingTimeInterval(24 * 3600))
    }

    func testMutedTitleGetsNothing() {
        let plan = NotificationPlanner.plan(
            library: library(muted: true), now: now, calendar: calendar
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testPlanWithoutPermissionIsEmpty() {
        let prefs = NotificationPreferences(
            preAlertHours: 1, imminentAlertMinutes: nil, permissionRequested: false
        )
        XCTAssertTrue(NotificationPlanner.plan(library: library(prefs: prefs), now: now, calendar: calendar).isEmpty)
    }

    func testDigestAddsADailySummaryWithoutInventingTimes() {
        var lib = library()
        lib.preferences.preAlertHours = nil
        lib.preferences.digestEnabled = true
        lib.preferences.digestHour = 9
        // Episode is tomorrow at 22:00 GMT, inside tomorrow's 9 AM digest window.
        lib.episodes["tv-100"] = [
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                overview: nil, airDate: now.addingTimeInterval(30 * 3600),
                airTimestamp: now.addingTimeInterval(30 * 3600), stillPath: nil
            )
        ]
        let plan = NotificationPlanner.plan(library: lib, now: now, calendar: calendar)
        XCTAssertEqual(plan.count, 1)
        XCTAssertTrue(plan[0].id.hasPrefix(NotificationPlanner.digestPrefix))
        XCTAssertTrue(plan[0].body.contains("Severance"))
    }

    func testWatchedMovieGetsNoAlert() {
        let plan = NotificationPlanner.plan(
            library: library(watchedMovie: true), now: now, calendar: calendar
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testCapKeepsTheSoonestSixtyAlerts() {
        var lib = library()
        lib.preferences.preAlertHours = 1
        lib.episodes["tv-100"] = (1...80).map { number in
            Episode(
                tmdbID: 100, seasonNumber: 1, episodeNumber: number,
                name: "Episode \(number)", overview: nil, airDate: nil,
                airTimestamp: now.addingTimeInterval(Double(number) * 86_400), stillPath: nil
            )
        }
        let plan = NotificationPlanner.plan(library: lib, now: now, calendar: calendar)
        XCTAssertEqual(plan.count, NotificationPlanner.maxPending)
        XCTAssertEqual(plan.first?.id, "pre-tv-100-100-s1e1")
        XCTAssertEqual(plan.last?.id, "pre-tv-100-100-s1e60")
    }
}
