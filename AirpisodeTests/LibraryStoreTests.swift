import XCTest
@testable import Airpisode

final class LibraryStoreTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testSaveAndLoadRoundTrip() async throws {
        let store = LibraryStore(directory: dir)
        var lib = Library()
        lib.entries.append(WatchlistEntry(tmdbID: 1, mediaType: .tv, addedAt: .now, isTrackingEnabled: true))
        lib.titles["tv-1"] = Title(tmdbID: 1, mediaType: .tv, name: "Test Show", overview: "", posterPath: nil, firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil)
        try await store.save(lib)
        let loaded = await store.load()
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.titles["tv-1"]?.name, "Test Show")
    }
    func testLoadOnEmptyDirReturnsEmptyLibrary() async throws {
        let store = LibraryStore(directory: dir)
        let loaded = await store.load()
        XCTAssertTrue(loaded.entries.isEmpty)
    }
}
