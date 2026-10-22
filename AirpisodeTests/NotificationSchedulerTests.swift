import XCTest
import UserNotifications
@testable import Airpisode

final class MockNotificationClient: NotificationClientProtocol, @unchecked Sendable {
    var addCalls: [UNNotificationRequest] = []
    var removeCalls: [[String]] = []
    var authResult = true
    var authStatus: UNAuthorizationStatus = .authorized
    var pending: [PendingAlert] = []
    var delivered: Set<String> = []

    func requestAuthorization() async throws -> Bool { authResult }
    func add(_ request: UNNotificationRequest) async throws { addCalls.append(request) }
    func removePending(withIdentifiers ids: [String]) { removeCalls.append(ids) }
    func authorizationStatus() async -> UNAuthorizationStatus { authStatus }
    func pendingAlerts() async -> [PendingAlert] { pending }
    func deliveredIDs() async -> Set<String> { delivered }
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

        // TMDB date-only encoding: exactly noon UTC, no TVmaze time available.
        await scheduler.schedule(for: title(), episodes: [episode(airDate: now.addingTimeInterval(86_400))], prefs: prefs, now: now)

        XCTAssertTrue(mock.addCalls.isEmpty)
    }

    func testTVmazeTimestampOverridesDateOnlyAirDate() async {
        let mock = MockNotificationClient()
        let scheduler = NotificationScheduler(client: mock)
        let prefs = NotificationPreferences(preAlertHours: 24, imminentAlertMinutes: 15, permissionRequested: true)
        let exact = now.addingTimeInterval(30 * 3600 + 900)  // 30.25h away, not noon UTC

        var ep = episode(airDate: now.addingTimeInterval(86_400))  // date-only TMDB value
        ep.airTimestamp = exact
        await scheduler.schedule(for: title(), episodes: [ep], prefs: prefs, now: now)

        XCTAssertEqual(mock.addCalls.count, 2)
        XCTAssertEqual(triggerDate(of: mock.addCalls[0]), exact.addingTimeInterval(-24 * 3600))
        XCTAssertEqual(triggerDate(of: mock.addCalls[1]), exact.addingTimeInterval(-15 * 60))
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

    func testApplyRemovesStaleManagedAlertsButKeepsTestAlerts() async {
        let mock = MockNotificationClient()
        mock.pending = [
            PendingAlert(id: "pre-tv-100-old", title: "Old", body: "", fireDate: now),
            PendingAlert(id: "test-123", title: "Test", body: "", fireDate: now),
        ]
        let scheduler = NotificationScheduler(client: mock)

        await scheduler.apply(plan: [])

        XCTAssertEqual(mock.removeCalls, [["pre-tv-100-old"]])
    }

    func testTestAlertUsesATenSecondTrigger() async {
        let mock = MockNotificationClient()
        await NotificationScheduler(client: mock).sendTestAlert(now: now)

        XCTAssertEqual(mock.addCalls.count, 1)
        let trigger = mock.addCalls[0].trigger as? UNTimeIntervalNotificationTrigger
        XCTAssertEqual(trigger?.timeInterval, 10)
        XCTAssertTrue(mock.addCalls[0].identifier.hasPrefix(NotificationScheduler.testIDPrefix))
    }

    func testCatchUpUsesAnIntervalTrigger() async {
        let mock = MockNotificationClient()
        let scheduler = NotificationScheduler(client: mock)
        let prefs = NotificationPreferences(
            preAlertHours: nil, imminentAlertMinutes: 15, permissionRequested: true
        )
        var ep = episode(airDate: now.addingTimeInterval(86_400))
        ep.airTimestamp = now.addingTimeInterval(600)

        await scheduler.schedule(for: title(), episodes: [ep], prefs: prefs, now: now)

        XCTAssertEqual(mock.addCalls.count, 1)
        XCTAssertEqual(mock.addCalls[0].identifier, "imminent-tv-100-100-s2e5")
        let trigger = mock.addCalls[0].trigger as? UNTimeIntervalNotificationTrigger
        XCTAssertNotNil(trigger)
        XCTAssertGreaterThan(trigger?.timeInterval ?? 0, 0)
        XCTAssertLessThanOrEqual(trigger?.timeInterval ?? 99, 6)
    }

    func testDeliveredCatchUpIsNotScheduledAgain() async {
        let mock = MockNotificationClient()
        mock.delivered = ["imminent-tv-100-100-s2e5"]
        let scheduler = NotificationScheduler(client: mock)
        let prefs = NotificationPreferences(
            preAlertHours: nil, imminentAlertMinutes: 15, permissionRequested: true
        )
        var ep = episode(airDate: now.addingTimeInterval(86_400))
        ep.airTimestamp = now.addingTimeInterval(600)

        await scheduler.schedule(for: title(), episodes: [ep], prefs: prefs, now: now)

        XCTAssertTrue(mock.addCalls.isEmpty)
    }

    private func record(
        titleName: String, label: String, kind: ScheduleChangeRecord.Kind,
        newDate: Date?, posterPath: String? = nil
    ) -> ScheduleChangeRecord {
        ScheduleChangeRecord(
            id: "\(titleName)|\(label)|\(kind.rawValue)", titleID: "tv-100", key: "key",
            titleName: titleName, label: label, kind: kind, oldDate: nil,
            newDate: newDate, detectedAt: now, posterPath: posterPath
        )
    }

    func testSingleScheduleChangeSpeaksOncePerFact() async {
        let mock = MockNotificationClient()
        let moved = record(
            titleName: "Severance", label: "S2E5", kind: .dateChanged,
            newDate: now.addingTimeInterval(86_400)
        )

        await NotificationScheduler(client: mock).notifyScheduleChanges([moved], now: now)

        XCTAssertEqual(mock.addCalls.count, 1)
        XCTAssertEqual(mock.addCalls[0].content.title, "Schedule change")
        XCTAssertEqual(mock.addCalls[0].content.subtitle, "Severance · S2E5")
        XCTAssertTrue(mock.addCalls[0].content.body.hasPrefix("Moved to"))
    }

    func testSingleNewReleaseNamesTheKindNotTheDate() async {
        let mock = MockNotificationClient()
        let added = record(
            titleName: "Severance", label: "S2E5", kind: .newRelease,
            newDate: now.addingTimeInterval(86_400)
        )

        await NotificationScheduler(client: mock).notifyScheduleChanges([added], now: now)

        XCTAssertEqual(mock.addCalls[0].content.title, "New release")
        XCTAssertEqual(mock.addCalls[0].content.subtitle, "Severance · S2E5")
        XCTAssertTrue(mock.addCalls[0].content.body.hasPrefix("Available"))
    }

    func testBatchedScheduleChangesListEachTitleOnce() async {
        let mock = MockNotificationClient()
        let records = [
            record(titleName: "Dune", label: "Digital", kind: .newRelease, newDate: now.addingTimeInterval(86_400)),
            record(titleName: "Severance", label: "S2E5", kind: .dateChanged, newDate: nil),
        ]

        await NotificationScheduler(client: mock).notifyScheduleChanges(records, now: now)

        XCTAssertEqual(mock.addCalls[0].content.title, "2 release changes")
        XCTAssertTrue(mock.addCalls[0].content.body.contains("Dune · Digital"))
        XCTAssertTrue(mock.addCalls[0].content.body.contains("Severance · S2E5"))
    }
}
