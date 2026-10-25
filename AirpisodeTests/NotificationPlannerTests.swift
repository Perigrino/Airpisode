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

    func testDigestListsHonestTimesAndCarriesTheSoonestPoster() {
        var lib = library()
        lib.preferences.preAlertHours = nil
        lib.preferences.digestEnabled = true
        lib.preferences.digestHour = 9
        lib.titles["tv-100"] = Title(
            tmdbID: 100, mediaType: .tv, name: "Severance", overview: "", posterPath: "/severance.jpg",
            firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil
        )
        // Tomorrow 22:00 GMT: an exact air moment inside tomorrow's 9 AM digest window.
        lib.episodes["tv-100"] = [
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                overview: nil, airDate: nil,
                airTimestamp: now.addingTimeInterval(32 * 3600), stillPath: nil
            )
        ]
        lib.entries.append(WatchlistEntry(tmdbID: 200, mediaType: .movie, addedAt: now, isTrackingEnabled: true))
        lib.titles["movie-200"] = Title(
            tmdbID: 200, mediaType: .movie, name: "Dune", overview: "", posterPath: "/dune.jpg",
            firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil
        )
        // Date-only TMDB value: the digest must list it without inventing a time.
        lib.movieReleases["movie-200"] = [
            MovieRelease(tmdbID: 200, kind: .digital, region: "US", date: now.addingTimeInterval(36 * 3600), hasTime: false)
        ]

        let plan = NotificationPlanner.plan(library: lib, now: now, calendar: calendar)
        let digest = plan.first { $0.id.hasPrefix(NotificationPlanner.digestPrefix) }

        XCTAssertNotNil(digest)
        // The title names the real span, not a calendar day that may not match its contents.
        XCTAssertEqual(digest?.title, "Next 24 hours")
        // The soonest show fronts the banner; art is carried again like the other alerts.
        XCTAssertEqual(digest?.posterPath, "/severance.jpg")
        let airText = NotificationPlanner.time(
            now.addingTimeInterval(32 * 3600), calendar: calendar
        )
        XCTAssertTrue(digest?.body.contains("Severance · S2E5 · \(airText)") ?? false)
        XCTAssertTrue(digest?.body.contains("Dune · Digital") ?? false)
        XCTAssertFalse(digest?.body.contains("12:00") ?? true)
    }

    func testDigestMarksLinesThatFallOnTheNextDay() {
        var lib = library()
        lib.preferences.preAlertHours = nil
        lib.preferences.digestEnabled = true
        lib.preferences.digestHour = 9
        lib.episodes["tv-100"] = [
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                overview: nil, airDate: nil,
                // 38 hours out (02:00 the day after tomorrow): the window opens tomorrow
                // at 09:00, so this line falls on the next calendar day.
                airTimestamp: now.addingTimeInterval(38 * 3600), stillPath: nil
            )
        ]

        let plan = NotificationPlanner.plan(library: lib, now: now, calendar: calendar)
        let digest = plan.first { $0.id == "digest-2026-10-17" }

        XCTAssertNotNil(digest)
        XCTAssertTrue(digest?.body.contains("Severance · S2E5 · Tomorrow") ?? false)
    }

    func testDigestSuppressesTheMatchingPreAlert() {
        var lib = library()
        lib.preferences.preAlertHours = 24
        lib.preferences.digestEnabled = true
        lib.preferences.digestHour = 9
        lib.episodes["tv-100"] = [
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                overview: nil, airDate: nil,
                airTimestamp: now.addingTimeInterval(32 * 3600), stillPath: nil
            )
        ]

        let plan = NotificationPlanner.plan(library: lib, now: now, calendar: calendar)

        // The digest already announces this release within the same day; a second banner
        // saying "Airs tomorrow at ..." would be noise.
        XCTAssertFalse(plan.contains { $0.id.hasPrefix("pre-") })
        XCTAssertTrue(plan.contains { $0.id.hasPrefix(NotificationPlanner.digestPrefix) })
    }

    func testQuietHoursDeferANightAlertToMorning() {
        var lib = library(prefs: NotificationPreferences(
            preAlertHours: nil, imminentAlertMinutes: 15, permissionRequested: true
        ))
        // 03:59 GMT tomorrow: inside the default 23:00–07:00 window.
        let airDate = now.addingTimeInterval(16 * 3600 - 60)
        lib.episodes["tv-100"] = [
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                overview: nil, airDate: nil, airTimestamp: airDate, stillPath: nil
            )
        ]

        let plan = NotificationPlanner.plan(library: lib, now: now, calendar: calendar)

        XCTAssertEqual(plan.count, 1)
        let alert = plan[0]
        XCTAssertEqual(calendar.component(.hour, from: alert.fireDate), 7)
        XCTAssertEqual(calendar.component(.day, from: alert.fireDate), 17)
        // The show already aired by the time the window closes, and the copy says so
        // instead of delivering a stale "Starts in 15 minutes".
        XCTAssertTrue(alert.body.hasPrefix("Aired at "))
        XCTAssertFalse(alert.isCatchUp)
        XCTAssertTrue(alert.isUrgent)
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

    func testLateLaunchInsideLeadWindowSchedulesCatchUp() {
        var lib = library(prefs: NotificationPreferences(
            preAlertHours: nil, imminentAlertMinutes: 15, permissionRequested: true
        ))
        lib.episodes["tv-100"] = [
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                overview: nil, airDate: now.addingTimeInterval(600),
                airTimestamp: now.addingTimeInterval(600), stillPath: nil
            )
        ]

        let plan = NotificationPlanner.plan(
            library: lib, now: now, calendar: calendar, catchUpWindow: 1_800
        )

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].id, "imminent-tv-100-100-s2e5")
        XCTAssertTrue(plan[0].isCatchUp)
        XCTAssertEqual(plan[0].fireDate, now.addingTimeInterval(5))
        XCTAssertTrue(plan[0].body.contains("Starts in 10 minutes"))
    }

    /// The minute-level reconciler must not manufacture a catch-up for an alert that was
    /// already delivered and then dismissed.
    func testRoutineReconcileDoesNotRepeatAnAlreadyDeliveredImminent() {
        var lib = library(prefs: NotificationPreferences(
            preAlertHours: nil, imminentAlertMinutes: 15, permissionRequested: true
        ))
        lib.episodes["tv-100"] = [
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                overview: nil, airDate: now.addingTimeInterval(600),
                airTimestamp: now.addingTimeInterval(600), stillPath: nil
            )
        ]

        XCTAssertTrue(
            NotificationPlanner.plan(library: lib, now: now, calendar: calendar).isEmpty
        )
    }

    func testEpisodeThatAlreadyAiredGetsNoCatchUp() {
        var lib = library(prefs: NotificationPreferences(
            preAlertHours: nil, imminentAlertMinutes: 15, permissionRequested: true
        ))
        lib.episodes["tv-100"] = [
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                overview: nil, airDate: now.addingTimeInterval(-60),
                airTimestamp: now.addingTimeInterval(-60), stillPath: nil
            )
        ]

        XCTAssertTrue(
            NotificationPlanner.plan(library: lib, now: now, calendar: calendar).isEmpty
        )
    }

    func testWakeCatchUpSpeaksForAnEpisodeThatStartedWhileAsleep() {
        var lib = library(prefs: NotificationPreferences(
            preAlertHours: nil, imminentAlertMinutes: 15, permissionRequested: true
        ))
        lib.episodes["tv-100"] = [
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                overview: nil, airDate: now.addingTimeInterval(-20 * 60),
                airTimestamp: now.addingTimeInterval(-20 * 60), stillPath: nil
            )
        ]

        let plan = NotificationPlanner.plan(
            library: lib, now: now, calendar: calendar, catchUpWindow: 1_800
        )

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].id, "imminent-tv-100-100-s2e5")
        XCTAssertTrue(plan[0].isCatchUp)
        XCTAssertEqual(plan[0].body, "Started 20 minutes ago")
    }

    func testLateCatchUpRespectsItsWindow() {
        var lib = library(prefs: NotificationPreferences(
            preAlertHours: nil, imminentAlertMinutes: 15, permissionRequested: true
        ))
        lib.episodes["tv-100"] = [
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                overview: nil, airDate: now.addingTimeInterval(-2 * 3_600),
                airTimestamp: now.addingTimeInterval(-2 * 3_600), stillPath: nil
            )
        ]

        XCTAssertTrue(
            NotificationPlanner.plan(
                library: lib, now: now, calendar: calendar, catchUpWindow: 1_800
            ).isEmpty
        )
    }

    func testAlertBeforeLeadWindowStaysOnItsNormalSchedule() {
        var lib = library(prefs: NotificationPreferences(
            preAlertHours: nil, imminentAlertMinutes: 15, permissionRequested: true
        ))
        lib.episodes["tv-100"] = [
            Episode(
                tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                overview: nil, airDate: now.addingTimeInterval(1_200),
                airTimestamp: now.addingTimeInterval(1_200), stillPath: nil
            )
        ]

        let plan = NotificationPlanner.plan(library: lib, now: now, calendar: calendar)

        XCTAssertEqual(plan.count, 1)
        XCTAssertFalse(plan[0].isCatchUp)
        XCTAssertEqual(plan[0].fireDate, now.addingTimeInterval(300))
    }
}
