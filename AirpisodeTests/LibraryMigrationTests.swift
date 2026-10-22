import XCTest
@testable import Airpisode

final class LibraryMigrationTests: XCTestCase {
    func testVersionOneLibraryDecodesIntoCurrentDefaults() throws {
        let json = """
        {
          "schemaVersion": 1,
          "titles": {},
          "entries": [],
          "watchedShows": [],
          "watchedMovies": [],
          "watchedEpisodes": [],
          "episodes": {},
          "movieReleases": {},
          "preferences": { "permissionRequested": true }
        }
        """
        var library = try JSONDecoder().decode(Library.self, from: Data(json.utf8))
        XCTAssertEqual(library.schemaVersion, 1)
        XCTAssertTrue(library.migrateSchemaIfNeeded())
        XCTAssertEqual(library.schemaVersion, Library.currentSchemaVersion)
        XCTAssertTrue(library.scheduleChanges.isEmpty)
        XCTAssertTrue(library.watchLog.isEmpty)
        XCTAssertEqual(library.preferences.preAlertHours, 24)
        XCTAssertFalse(library.preferences.digestEnabled)
        XCTAssertTrue(library.preferences.notifyScheduleChanges)
    }

    func testExplicitlyDisabledPreAlertStaysOff() throws {
        let json = #"{"preAlertHours":null,"imminentAlertMinutes":null}"#
        let prefs = try JSONDecoder().decode(NotificationPreferences.self, from: Data(json.utf8))
        XCTAssertNil(prefs.preAlertHours)
        XCTAssertNil(prefs.imminentAlertMinutes)
    }

    func testMissingNotificationKeysUseDefaults() throws {
        let prefs = try JSONDecoder().decode(NotificationPreferences.self, from: Data("{}".utf8))
        XCTAssertEqual(prefs.preAlertHours, 24)
        XCTAssertEqual(prefs.imminentAlertMinutes, 15)
        XCTAssertFalse(prefs.digestEnabled)
    }
}
