import XCTest
@testable import Airpisode

final class LibraryStoreTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private var primary: URL { dir.appendingPathComponent("library.json") }
    private var backup: URL { dir.appendingPathComponent("library.backup.json") }

    private func library(named name: String, id: Int = 1) -> Library {
        var lib = Library()
        lib.entries.append(WatchlistEntry(tmdbID: id, mediaType: .tv, addedAt: .now, isTrackingEnabled: true))
        lib.titles["tv-\(id)"] = Title(
            tmdbID: id, mediaType: .tv, name: name, overview: "", posterPath: nil,
            firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil
        )
        return lib
    }

    private func corruptFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("library.corrupt-") } ?? []
    }

    func testSaveAndLoadRoundTrip() async throws {
        let store = LibraryStore(directory: dir)
        try await store.save(library(named: "Test Show"))
        let loaded = await store.load()
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.titles["tv-1"]?.name, "Test Show")
    }

    func testLoadOnEmptyDirReturnsEmptyLibrary() async throws {
        let store = LibraryStore(directory: dir)
        let report = await store.loadReport()
        XCTAssertTrue(report.library.entries.isEmpty)
        XCTAssertNil(report.warning)
    }

    func testSaveKeepsACompleteBackup() async throws {
        let store = LibraryStore(directory: dir)
        try await store.save(library(named: "First"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))

        try await store.save(library(named: "Second"))
        let backupData = try Data(contentsOf: backup)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(Library.self, from: backupData)
        XCTAssertEqual(restored.titles["tv-1"]?.name, "Second")
    }

    func testUnreadablePrimaryIsPreservedAndBackupRestored() async throws {
        let store = LibraryStore(directory: dir)
        try await store.save(library(named: "Good"))
        try Data("not json".utf8).write(to: primary)

        let report = await store.loadReport()
        XCTAssertEqual(report.library.titles["tv-1"]?.name, "Good")
        let warning = try XCTUnwrap(report.warning)
        XCTAssertTrue(warning.contains("couldn't be read"))
        XCTAssertTrue(warning.contains("backup was restored"))
        XCTAssertEqual(corruptFiles().count, 1)
        XCTAssertEqual(try String(contentsOf: corruptFiles()[0], encoding: .utf8), "not json")
    }

    func testUnreadablePrimaryWithoutBackupKeepsTheFileAndWarns() async throws {
        let store = LibraryStore(directory: dir)
        try Data("not json".utf8).write(to: primary)

        let report = await store.loadReport()
        XCTAssertTrue(report.library.entries.isEmpty)
        let warning = try XCTUnwrap(report.warning)
        XCTAssertTrue(warning.contains("no backup was available"))
        XCTAssertEqual(corruptFiles().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: primary.path))
    }

    func testMissingPrimaryFallsBackToTheBackup() async throws {
        let store = LibraryStore(directory: dir)
        try await store.save(library(named: "Restored"))
        try FileManager.default.removeItem(at: primary)

        let report = await store.loadReport()
        XCTAssertEqual(report.library.titles["tv-1"]?.name, "Restored")
        XCTAssertEqual(report.warning, "Your library file was missing, so the last backup was restored.")
    }

    func testAStaleSequenceCannotOverwriteANewerSave() async throws {
        let store = LibraryStore(directory: dir)
        try await store.save(library(named: "Newest"), sequence: 7)
        try await store.save(library(named: "Stale"), sequence: 3)

        let loaded = await store.load()
        XCTAssertEqual(loaded.titles["tv-1"]?.name, "Newest")
    }

    func testAEqualSequenceCanStillRewrite() async throws {
        let store = LibraryStore(directory: dir)
        try await store.save(library(named: "First"), sequence: 4)
        try await store.save(library(named: "Second"), sequence: 4)

        let loaded = await store.load()
        XCTAssertEqual(loaded.titles["tv-1"]?.name, "Second")
    }

    @MainActor
    func testAppStateSurfacesAFailedSave() async throws {
        // A regular file where the library directory should be makes every write fail.
        let blocked = dir.appendingPathComponent("blocked")
        try Data("x".utf8).write(to: blocked)
        let state = AppState(
            store: LibraryStore(directory: blocked),
            tmdb: StubTMDBClient(),
            notifications: NotificationScheduler(client: SystemNotificationClient()),
            airTimes: StubAirTimeProvider()
        )
        state.addToLibrary(Title(
            tmdbID: 42, mediaType: .tv, name: "Unsavable", overview: "", posterPath: nil,
            firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil
        ))
        for _ in 0..<40 where state.storageError == nil {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let message = try XCTUnwrap(state.storageError)
        XCTAssertTrue(message.hasPrefix("Couldn't save your library"))
        state.dismissStorageError()
        XCTAssertNil(state.storageError)
    }
}
