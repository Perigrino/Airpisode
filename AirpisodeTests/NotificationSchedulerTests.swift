import XCTest
import UserNotifications
@testable import Airpisode

final class MockNotificationClient: NotificationClientProtocol, @unchecked Sendable {
    var addCalls: [UNNotificationRequest] = []
    var removeCalls: [[String]] = []
    var authResult = true

    func requestAuthorization() async throws -> Bool { authResult }
    func add(_ request: UNNotificationRequest) async throws { addCalls.append(request) }
    func removePending(withIdentifiers ids: [String]) { removeCalls.append(ids) }
}

final class NotificationSchedulerTests: XCTestCase {
    private let now = TMDBMapper.parseDate("2026-10-16")!  // noon UTC

    private var timedEpisodeDate: Date { now.addingTimeInterval(30 * 3600 + 900) }  // 30.25h away, not noon UTC

    private func episode(airDate: Date?) -> Episode {
        Episode(tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow", overview: nil, airDate: airDate, stillPath: nil)
    }

    private func title() -> Title {
        Title(tmdbID: 100, mediaType: .tv, name: "Severance", overview: "", posterPath: nil, firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil)
    }

    private func triggerDate(of request: UNNotificationRequest) -> Date? {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
        return Calendar.current.date(from: trigger.dateComponents)
    }

    func testTimedEpisodeGetsPreAlertAtMinusPreAlertHours() async {
        let mock = MockNotificationClient()
        let scheduler = NotificationScheduler(client: mock)
        let prefs = NotificationPreferences(preAlertHours: 24, imminentAlertMinutes: nil, permissionRequested: true)

        await scheduler.schedule(for: title(), episodes: [episode(airDate: timedEpisodeDate)], prefs: prefs, now: now)

        XCTAssertEqual(mock.addCalls.count, 1)
        let request = mock.addCalls[0]
        XCTAssertEqual(request.identifier, "pre-tv-100-100-s2e5")
        XCTAssertEqual(triggerDate(of: request), timedEpisodeDate.addingTimeInterval(-24 * 3600))
    }

    func testSameCallTwiceProducesIdenticalIdentifiers() async {
        let mock = MockNotificationClient()
        let scheduler = NotificationScheduler(client: mock)
        let prefs = NotificationPreferences(preAlertHours: 24, imminentAlertMinutes: 15, permissionRequested: true)
        let episodes = [episode(airDate: timedEpisodeDate)]

        await scheduler.schedule(for: title(), episodes: episodes, prefs: prefs, now: now)
        await scheduler.schedule(for: title(), episodes: episodes, prefs: prefs, now: now)

        let ids = mock.addCalls.map(\.identifier)
        XCTAssertEqual(ids.count, 4)  // 2 alerts × 2 runs; IDs identical so the OS replaces, not duplicates
        XCTAssertEqual(Array(Set(ids)).count, 2)
    }

    func testDateOnlyEpisodeGetsNoAlerts() async {
        let mock = MockNotificationClient()
        let scheduler = NotificationScheduler(client: mock)
        let prefs = NotificationPreferences(preAlertHours: 24, imminentAlertMinutes: 15, permissionRequested: true)

        // TMDB date-only encoding: exactly noon UTC.
        await scheduler.schedule(for: title(), episodes: [episode(airDate: now.addingTimeInterval(86_400))], prefs: prefs, now: now)

        XCTAssertTrue(mock.addCalls.isEmpty)
    }

    func testTimedMovieReleaseGetsPreAlertOnly() async {
        let mock = MockNotificationClient()
        let scheduler = NotificationScheduler(client: mock)
        let prefs = NotificationPreferences(preAlertHours: 24, imminentAlertMinutes: 15, permissionRequested: true)
        let movie = Title(tmdbID: 200, mediaType: .movie, name: "Dune", overview: "", posterPath: nil, firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil)
        let releases = [MovieRelease(tmdbID: 200, kind: .digital, region: "US", date: timedEpisodeDate, hasTime: true)]

        await scheduler.schedule(for: movie, episodes: [], movieReleases: releases, prefs: prefs, now: now)

        XCTAssertEqual(mock.addCalls.count, 1)
        XCTAssertEqual(mock.addCalls[0].identifier, "pre-movie-200-200-digital-US")
    }

    func testCancelAllRemovesPreAndImminentIDsForEveryKey() {
        let mock = MockNotificationClient()
        let scheduler = NotificationScheduler(client: mock)

        scheduler.cancelAll(forTitle: "tv-100", keys: ["100-s1e1", "100-s1e2"])

        XCTAssertEqual(mock.removeCalls.count, 1)
        XCTAssertEqual(Set(mock.removeCalls[0]), [
            "pre-tv-100-100-s1e1", "imminent-tv-100-100-s1e1",
            "pre-tv-100-100-s1e2", "imminent-tv-100-100-s1e2",
        ])
    }

    func testPastReleaseGetsNothing() async {
        let mock = MockNotificationClient()
        let scheduler = NotificationScheduler(client: mock)
        let prefs = NotificationPreferences(preAlertHours: 24, imminentAlertMinutes: 15, permissionRequested: true)

        await scheduler.schedule(for: title(), episodes: [episode(airDate: now.addingTimeInterval(-86_400))], prefs: prefs, now: now)

        XCTAssertTrue(mock.addCalls.isEmpty)
    }

    // MARK: - Release sample (real data)

    private func libraryWithAiredEpisode() -> Library {
        var library = Library()
        library.titles["tv-100"] = title()
        library.entries = [WatchlistEntry(tmdbID: 100, mediaType: .tv, addedAt: now, isTrackingEnabled: true)]
        library.episodes["tv-100"] = [episode(airDate: Date.now.addingTimeInterval(-86_400))]
        return library
    }

    func testReleaseSampleUsesLatestAiredEpisode() {
        let sample = NotificationScheduler.releaseSample(from: libraryWithAiredEpisode())
        XCTAssertEqual(sample?.title, "Severance — New Episode Out Now!")
        XCTAssertEqual(sample?.body, "S2E5 · \"Woe's Hollow\" just aired · \(NotificationSchedulerTests.dayLabel(Date.now.addingTimeInterval(-86_400)))")
    }

    func testReleaseSampleFallsBackToUpcomingEpisode() {
        var library = Library()
        library.titles["tv-100"] = title()
        library.entries = [WatchlistEntry(tmdbID: 100, mediaType: .tv, addedAt: now, isTrackingEnabled: true)]
        library.episodes["tv-100"] = [episode(airDate: Date.now.addingTimeInterval(3 * 86_400))]

        let sample = NotificationScheduler.releaseSample(from: library)
        XCTAssertEqual(sample?.title, "Severance — New Episode Incoming!")
        XCTAssertTrue(sample?.body.contains("premieres") == true)
    }

    func testReleaseSampleFallsBackToMovieRelease() {
        var library = Library()
        let movie = Title(tmdbID: 200, mediaType: .movie, name: "Dune", overview: "", posterPath: nil, firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil)
        library.titles["movie-200"] = movie
        library.entries = [WatchlistEntry(tmdbID: 200, mediaType: .movie, addedAt: now, isTrackingEnabled: true)]
        library.movieReleases["movie-200"] = [MovieRelease(tmdbID: 200, kind: .digital, region: "US", date: Date.now.addingTimeInterval(86_400), hasTime: true)]

        let sample = NotificationScheduler.releaseSample(from: library)
        XCTAssertEqual(sample?.title, "Dune — Digital Releasing Soon!")
        XCTAssertTrue(sample?.body.contains("US") == true)
    }

    func testReleaseSampleNilWhenLibraryEmpty() {
        XCTAssertNil(NotificationScheduler.releaseSample(from: Library()))
        XCTAssertNil(NotificationScheduler.releaseSamplePreview(library: Library()))
    }

    static func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }
}
