import XCTest
@testable import Airpisode

@MainActor
final class AppStateBackgroundRefreshTests: XCTestCase {
    private func makeSUT() -> AppState {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return AppState(store: LibraryStore(directory: dir), tmdb: StubTMDBClient())
    }

    /// Fixed GMT calendar + built dates so sweep-slot assertions are time-zone-independent.
    private let gmt: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }()

    private func gmtDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        gmt.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testTickerFiresInBackgroundPasses() async throws {
        let app = makeSUT()
        app.startBackgroundRefresh(every: 0.05)
        XCTAssertTrue(app.isBackgroundRefreshRunning())
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertGreaterThanOrEqual(app.backgroundRefreshTicks, 2)
        app.stopBackgroundRefresh()
        XCTAssertFalse(app.isBackgroundRefreshRunning())
    }

    func testStartIgnoresSecondSchedule() throws {
        let app = makeSUT()
        app.startBackgroundRefresh(every: 0.05)
        // A second schedule attempt (e.g. the window is re-created) must be a no-op.
        app.startBackgroundRefresh(every: 0.01)
        XCTAssertTrue(app.isBackgroundRefreshRunning())
        app.stopBackgroundRefresh()
        XCTAssertFalse(app.isBackgroundRefreshRunning())
    }

    func testSweepsOncePerLocalMorningSlot() async {
        let app = makeSUT()
        // Launched after the 6 AM anchor with no sweep yet today: sweep right away.
        await app.tickBackgroundRefresh(now: gmtDate(2026, 10, 17, 7), in: gmt)
        XCTAssertEqual(app.lastDailySweepSlot, gmtDate(2026, 10, 17, 6))
        // Further heartbeats the same day do not sweep again.
        await app.tickBackgroundRefresh(now: gmtDate(2026, 10, 17, 15), in: gmt)
        XCTAssertEqual(app.lastDailySweepSlot, gmtDate(2026, 10, 17, 6))
        // The next local day sweeps again, shortly after its own anchor.
        await app.tickBackgroundRefresh(now: gmtDate(2026, 10, 18, 6, 30), in: gmt)
        XCTAssertEqual(app.lastDailySweepSlot, gmtDate(2026, 10, 18, 6))
    }

    func testNoSweepBeforeTheMorningAnchor() async {
        let app = makeSUT()
        await app.tickBackgroundRefresh(now: gmtDate(2026, 10, 17, 7), in: gmt)
        // Heartbeats at 3 AM are not due: the previous morning's sweep still stands.
        await app.tickBackgroundRefresh(now: gmtDate(2026, 10, 18, 3), in: gmt)
        XCTAssertEqual(app.lastDailySweepSlot, gmtDate(2026, 10, 17, 6))
    }

    func testOfflineMorningSweepDefersUntilReachable() async throws {
        let stub = StubTMDBClient() // every call throws while "offline"
        let app = AppState(store: LibraryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), tmdb: stub)
        app.addToLibrary(Title(tmdbID: 100, mediaType: .tv, name: "Severance", overview: "", posterPath: nil, firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil))
        app.library.titles["tv-100"]?.lastRefreshed = gmtDate(2026, 10, 16, 6)

        // Due at 6:30 AM, but the sweep fails while offline: the slot stays unstamped.
        await app.tickBackgroundRefresh(now: gmtDate(2026, 10, 17, 6, 30), in: gmt)
        XCTAssertNil(app.lastDailySweepSlot)
        XCTAssertNotNil(app.lastRefreshError)
        XCTAssertEqual(stub.tvDetailCallCount, 1)

        // Still offline an hour later: due again, retry again, still unstamped.
        await app.tickBackgroundRefresh(now: gmtDate(2026, 10, 17, 7), in: gmt)
        XCTAssertNil(app.lastDailySweepSlot)
        XCTAssertEqual(stub.tvDetailCallCount, 2)

        // Connectivity returns at 8 AM: the same morning slot finally sweeps and stamps.
        stub.tvDetailResult = TMDBTVDetail(
            id: 100, name: "Severance", overview: nil, posterPath: nil, firstAirDate: nil,
            status: "Returning Series",
            seasons: [TMDBSeasonSummary(seasonNumber: 1, episodeCount: 0, airDate: nil)],
            nextEpisodeToAir: nil
        )
        stub.seasons[1] = TMDBSeason(seasonNumber: 1, episodes: [])
        await app.tickBackgroundRefresh(now: gmtDate(2026, 10, 17, 8), in: gmt)
        XCTAssertEqual(app.lastDailySweepSlot, gmtDate(2026, 10, 17, 6))
        XCTAssertNil(app.lastRefreshError)
        XCTAssertEqual(stub.tvDetailCallCount, 3)
    }
}
