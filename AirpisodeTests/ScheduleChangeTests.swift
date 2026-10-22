import XCTest
@testable import Airpisode

final class ScheduleChangeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func library() -> Library {
        var library = Library()
        library.titles["tv-100"] = Title(
            tmdbID: 100, mediaType: .tv, name: "Severance", overview: "", posterPath: nil,
            firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: now
        )
        library.entries = [
            WatchlistEntry(tmdbID: 100, mediaType: .tv, addedAt: now, isTrackingEnabled: true)
        ]
        library.episodes["tv-100"] = [
            Episode(
                tmdbID: 100, seasonNumber: 3, episodeNumber: 1, name: "Cold Harbor",
                overview: nil, airDate: now.addingTimeInterval(3 * 86_400), stillPath: nil
            )
        ]
        return library
    }

    func testFirstRefreshOfANewTitleStaysSilent() {
        let change = ReleaseChange.newRelease(
            titleID: "tv-100", key: "100-s3e1",
            date: now.addingTimeInterval(3 * 86_400), hasTime: false
        )
        let records = ScheduleChangeRecorder.records(
            from: [change], library: library(), previouslyRefreshed: [], now: now
        )
        XCTAssertTrue(records.isEmpty)
    }

    func testFutureDateChangeIsRecorded() {
        let old = now.addingTimeInterval(2 * 86_400)
        let new = now.addingTimeInterval(5 * 86_400)
        let change = ReleaseChange.dateChanged(
            titleID: "tv-100", key: "100-s3e1", old: old, new: new, hasTime: false
        )
        let records = ScheduleChangeRecorder.records(
            from: [change], library: library(), previouslyRefreshed: ["tv-100"], now: now
        )
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].kind, .dateChanged)
        XCTAssertEqual(records[0].oldDate, old)
        XCTAssertEqual(records[0].newDate, new)
        XCTAssertEqual(records[0].label, "S3E1")
    }

    func testChangesBeyondThirtyDaysAreIgnored() {
        let change = ReleaseChange.newRelease(
            titleID: "tv-100", key: "100-s3e1",
            date: now.addingTimeInterval(60 * 86_400), hasTime: false
        )
        let records = ScheduleChangeRecorder.records(
            from: [change], library: library(), previouslyRefreshed: ["tv-100"], now: now
        )
        XCTAssertTrue(records.isEmpty)
    }

    func testMergeDeduplicatesAndCaps() {
        let existing = (0..<5).map { index in
            ScheduleChangeRecord(
                id: "existing-\(index)", titleID: "tv-100", key: "k", titleName: "Severance",
                label: "S3E1", kind: .dateChanged, oldDate: nil, newDate: now,
                detectedAt: now
            )
        }
        let duplicate = existing[0]
        var fresh = [duplicate]
        for index in 0..<10 {
            fresh.append(ScheduleChangeRecord(
                id: "fresh-\(index)", titleID: "tv-100", key: "k", titleName: "Severance",
                label: "S3E1", kind: .newRelease, oldDate: nil, newDate: now,
                detectedAt: now
            ))
        }
        let merged = ScheduleChangeRecorder.merge(fresh, into: existing)
        XCTAssertEqual(merged.count, 15)
        XCTAssertEqual(merged.filter { $0.id == duplicate.id }.count, 1)
        XCTAssertEqual(merged.first?.id, "fresh-9")
    }

    func testMergeCapsTheList() {
        let fresh = (0..<60).map { index in
            ScheduleChangeRecord(
                id: "fresh-\(index)", titleID: "tv-100", key: "k", titleName: "Severance",
                label: "S3E1", kind: .newRelease, oldDate: nil, newDate: now,
                detectedAt: now
            )
        }
        let merged = ScheduleChangeRecorder.merge(fresh, into: [])
        XCTAssertEqual(merged.count, ScheduleChangeRecorder.maxRecords)
        XCTAssertEqual(merged.first?.id, "fresh-59")
    }
}
