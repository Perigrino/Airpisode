import XCTest
import UserNotifications
@testable import Airpisode

final class NotificationDiagnosticsTests: XCTestCase {
    private let now = TMDBMapper.parseDate("2026-10-16")!

    private func library() -> Library {
        var library = Library()
        library.preferences.permissionRequested = true
        library.titles["tv-100"] = Title(
            tmdbID: 100, mediaType: .tv, name: "Abbott Elementary", overview: "", posterPath: nil,
            firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: now
        )
        library.entries = [
            WatchlistEntry(tmdbID: 100, mediaType: .tv, addedAt: now, isTrackingEnabled: true)
        ]
        // TMDB date-only sentinel: noon UTC, no TVmaze time.
        library.episodes["tv-100"] = [
            Episode(
                tmdbID: 100, seasonNumber: 6, episodeNumber: 3, name: "Tryouts",
                overview: nil, airDate: now.addingTimeInterval(86_400), stillPath: nil
            )
        ]
        return library
    }

    func testDeniedPermissionIsAWarning() {
        let report = NotificationDiagnostics.report(
            library: library(), authorization: .denied, pending: [], now: now
        )
        XCTAssertTrue(report.rows.contains { $0.id == "permission" && $0.severity == .warning })
    }

    func testDateOnlyShowIsExplained() {
        let report = NotificationDiagnostics.report(
            library: library(), authorization: .authorized, pending: [], now: now
        )
        let row = report.rows.first { $0.id == "date-only" }
        XCTAssertNotNil(row)
        XCTAssertTrue(row?.detail.contains("Abbott Elementary") == true)
    }

    func testPendingCountOverTheCapIsAWarning() {
        let pending = (0..<61).map { index in
            PendingAlert(
                id: "pre-tv-100-100-s1e\(index)", title: "Alert \(index)", body: "",
                fireDate: now.addingTimeInterval(Double(index) * 3600)
            )
        }
        let report = NotificationDiagnostics.report(
            library: library(), authorization: .authorized, pending: pending, now: now
        )
        XCTAssertTrue(report.rows.contains { $0.id == "cap" })
        XCTAssertEqual(report.scheduledCount, 61)
    }

    func testEmptyScheduleExplainsWhy() {
        let report = NotificationDiagnostics.report(
            library: library(), authorization: .authorized, pending: [], now: now
        )
        XCTAssertTrue(report.rows.contains { $0.id == "empty" })
    }
}
