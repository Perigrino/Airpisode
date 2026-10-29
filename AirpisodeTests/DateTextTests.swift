import XCTest
@testable import Airpisode

final class DateTextTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12))!
    }

    private func date(day: Int, hour: Int = 12, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - relative

    func testRelativeUsesSingularAndPluralUnits() {
        XCTAssertEqual(DateText.relative(date(day: 28, hour: 12).addingTimeInterval(30), now: now), "less than a minute")
        XCTAssertEqual(DateText.relative(date(day: 28, hour: 13), now: now), "1 hour")
        XCTAssertEqual(DateText.relative(date(day: 28, hour: 15), now: now), "3 hours")
        XCTAssertEqual(DateText.relative(date(day: 30), now: now), "2 days")
        XCTAssertEqual(DateText.relative(date(day: 4, month: 11), now: now), "1 week")
        XCTAssertEqual(DateText.relative(date(day: 28, month: 12), now: now), "2 months")
    }

    func testRelativeCountsBackwardsForPastDates() {
        XCTAssertEqual(DateText.relative(date(day: 27), now: now), "1 day")
    }

    // MARK: - compact

    func testCompactStepsThroughMinutesHoursDaysWeeksMonths() {
        XCTAssertEqual(DateText.compact(date(day: 28, hour: 12).addingTimeInterval(90), now: now), "1m")
        XCTAssertEqual(DateText.compact(date(day: 28, hour: 14), now: now), "2h")
        XCTAssertEqual(DateText.compact(date(day: 31), now: now), "3d")
        XCTAssertEqual(DateText.compact(date(day: 8, month: 11), now: now), "1w")
        XCTAssertEqual(DateText.compact(date(day: 28, month: 12), now: now), "2mo")
        XCTAssertEqual(DateText.compact(date(day: 28, month: 10, year: 2027), now: now), "1y")
    }

    func testCompactTreatsPastAsNow() {
        XCTAssertEqual(DateText.compact(date(day: 27), now: now), "Now")
    }

    // MARK: - upcoming

    func testUpcomingNamesNearDaysInWords() {
        XCTAssertEqual(DateText.upcoming(date(day: 28, hour: 20), now: now, calendar: calendar), "Today")
        XCTAssertEqual(DateText.upcoming(date(day: 29), now: now, calendar: calendar), "Tomorrow")
        let weekday = date(day: 30)
        XCTAssertEqual(DateText.upcoming(weekday, now: now, calendar: calendar), weekday.formatted(.dateTime.weekday(.abbreviated)))
    }

    func testUpcomingIncludesTimeOnlyWhenAsked() {
        let today = date(day: 28, hour: 20)
        XCTAssertEqual(DateText.upcoming(today, now: now, calendar: calendar, includeTime: true), "Today, " + DateText.time(today))
    }

    func testUpcomingFallsBackToPastWordingForAiredDates() {
        XCTAssertEqual(DateText.upcoming(date(day: 27), now: now, calendar: calendar), "Yesterday")
    }

    // MARK: - airing

    func testAiringDescribesRecentPast() {
        XCTAssertEqual(DateText.airing(date(day: 28, hour: 9), now: now, calendar: calendar), "Today")
        XCTAssertEqual(DateText.airing(date(day: 27), now: now, calendar: calendar), "Yesterday")
        XCTAssertEqual(DateText.airing(date(day: 25), now: now, calendar: calendar), "3 days ago")
        let older = date(day: 12)
        XCTAssertEqual(DateText.airing(older, now: now, calendar: calendar), older.formatted(.dateTime.month(.abbreviated).day()))
    }

    func testAiringIncludesYearForAnotherYear() {
        let older = date(day: 12, month: 10, year: 2025)
        XCTAssertEqual(
            DateText.airing(older, now: now, calendar: calendar),
            older.formatted(.dateTime.month(.abbreviated).day().year())
        )
    }

    // MARK: - freshness

    func testFreshnessDescribesTheLastRefresh() {
        XCTAssertEqual(DateText.freshness(nil, now: now), "Not refreshed yet")
        XCTAssertEqual(DateText.freshness(now.addingTimeInterval(-20), now: now), "Updated just now")
        XCTAssertEqual(DateText.freshness(now.addingTimeInterval(-300), now: now), "Updated 5 min ago")
        XCTAssertEqual(DateText.freshness(now.addingTimeInterval(-7200), now: now), "Updated 2 hr ago")
        XCTAssertEqual(DateText.freshness(date(day: 27), now: now), "Updated Yesterday")
    }
}
