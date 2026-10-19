import XCTest
import UserNotifications
@testable import Airpisode

final class MutePinTests: XCTestCase {
    @MainActor
    private func makeApp(mock: MockNotificationClient) -> AppState {
        AppState(
            store: LibraryStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)),
            tmdb: StubTMDBClient(),
            notifications: NotificationScheduler(client: mock)
        )
    }

    @MainActor
    private func addTrackedMovie(_ app: AppState) {
        app.addToLibrary(Title(
            tmdbID: 200, mediaType: .movie, name: "Fugue", overview: "", posterPath: nil,
            firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil
        ))
        app.library.movieReleases["movie-200"] = [MovieRelease(
            tmdbID: 200, kind: .digital, region: "US",
            date: .now.addingTimeInterval(10 * 86_400), hasTime: true
        )]
    }

    /// `AppState.reschedule` fires its scheduling in a detached Task, so poll briefly.
    private func waitFor(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 2) async {
        let start = Date()
        while !condition() {
            try? await Task.sleep(nanoseconds: 30_000_000)
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("condition not satisfied within \(timeout)s")
                return
            }
        }
    }

    @MainActor
    func testMuteCancelsPendingAlertsAndKeepsThemCancelledWhileMuted() async {
        let mock = MockNotificationClient()
        let app = makeApp(mock: mock)
        addTrackedMovie(app)

        // Enable alerts: the future timed release schedules one pre-alert.
        app.updateNotificationPreferences { $0.permissionRequested = true }
        await waitFor(mock.addCalls.count == 1)

        // Mutuing cancels what is pending...
        app.setAlertsMuted(true, titleID: "movie-200")
        XCTAssertFalse(mock.removeCalls.isEmpty, "muting must cancel the pending pre-alert")

        // ...and any later reschedule pass must not re-add alerts while muted.
        app.updateNotificationPreferences { $0.preAlertHours = 24 }
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(mock.addCalls.count, 1)

        // Unmuting brings scheduling back.
        app.setAlertsMuted(false, titleID: "movie-200")
        await waitFor(mock.addCalls.count == 2)
    }

    @MainActor
    func testUnmutedTitleReschedulesWithStoredReleases() async {
        // Guard against the mute guard accidentally blocking everyone.
        let mock = MockNotificationClient()
        let app = makeApp(mock: mock)
        addTrackedMovie(app)

        app.updateNotificationPreferences { $0.permissionRequested = true }
        await waitFor(mock.addCalls.count == 1)
        let identifier = mock.addCalls[0].identifier
        XCTAssertEqual(identifier, "pre-movie-200-200-digital-US")
    }

    @MainActor
    func testPinnedRowsSortToTheTopAndOthersKeepTheirOrder() async {
        let app = makeApp(mock: MockNotificationClient())
        for (offset, name) in ["Alpha", "Minima", "Zebra"].enumerated() {
            app.addToLibrary(Title(
                tmdbID: offset + 1, mediaType: .tv, name: "\(name)", overview: "", posterPath: nil,
                firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil
            ))
        }
        let alphabetical = [1, 2, 3].map {
            app.library.titles["tv-\($0)"]!
        }

        app.setPinned(true, titleID: "tv-2")

        let ordered = app.library.orderedWithPinnedFirst(alphabetical)
        XCTAssertEqual(ordered.map(\.id), ["tv-2", "tv-1", "tv-3"])

        app.setPinned(false, titleID: "tv-2")
        XCTAssertEqual(alphabetical, [1, 2, 3].map { app.library.titles["tv-\($0)"]! })
        XCTAssertEqual(app.library.orderedWithPinnedFirst(alphabetical).map(\.id), ["tv-1", "tv-2", "tv-3"])
    }

    func testOptionalEntryFieldsDecodeFromLegacyJSON() throws {
        let json = #"{"tmdbID":1,"mediaType":"tv","addedAt":0.0,"isTrackingEnabled":true}"#
        let entry = try JSONDecoder().decode(WatchlistEntry.self, from: Data(json.utf8))
        XCTAssertNil(entry.alertsMuted)
        XCTAssertNil(entry.pinnedAt)
    }
}
