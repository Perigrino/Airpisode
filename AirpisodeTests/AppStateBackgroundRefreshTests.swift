import XCTest
@testable import Airpisode

@MainActor
final class AppStateBackgroundRefreshTests: XCTestCase {
    private func makeSUT() -> AppState {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return AppState(store: LibraryStore(directory: dir), tmdb: StubTMDBClient())
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
}
