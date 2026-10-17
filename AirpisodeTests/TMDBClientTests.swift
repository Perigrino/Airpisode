import XCTest
@testable import Airpisode

final class TMDBClientTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        let url = Bundle(for: TMDBClientTests.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle(for: TMDBClientTests.self).url(forResource: name, withExtension: "json")
        return try Data(contentsOf: XCTUnwrap(url))
    }
    func testDecodesSearchMulti() throws {
        let page = try JSONDecoder().decode(TMDBSearchResponse.self, from: fixture("search_multi"))
        XCTAssertTrue(page.results.contains { $0.mediaType == "tv" && !$0.displayName.isEmpty })
        XCTAssertTrue(page.results.contains { $0.mediaType == "movie" && !$0.displayName.isEmpty })
    }
    func testDecodesTVDetail() throws {
        let d = try JSONDecoder().decode(TMDBTVDetail.self, from: fixture("tv_detail"))
        XCTAssertFalse(d.name.isEmpty)
        XCTAssertFalse(d.seasons.isEmpty)
    }
    func testDecodesSeason() throws {
        let s = try JSONDecoder().decode(TMDBSeason.self, from: fixture("season"))
        XCTAssertFalse(s.episodes.isEmpty)
    }
    func testDecodesMovieDetail() throws {
        let d = try JSONDecoder().decode(TMDBMovieDetail.self, from: fixture("movie_detail"))
        XCTAssertFalse(d.title.isEmpty)
    }
    func testDecodesSimilar() throws {
        let page = try JSONDecoder().decode(TMDBRecommendationsResponse.self, from: fixture("similar_tv"))
        XCTAssertFalse(page.results.isEmpty)
        XCTAssertFalse(page.results[0].name?.isEmpty ?? true)
    }
    func testDecodesCredits() throws {
        let page = try JSONDecoder().decode(TMDBCreditsResponse.self, from: fixture("credits_tv"))
        XCTAssertFalse(page.cast.isEmpty)
        XCTAssertFalse(page.cast[0].name.isEmpty)
    }
    func testDecodesMovieReleaseDates() throws {
        let r = try JSONDecoder().decode(TMDBReleaseDatesResponse.self, from: fixture("movie_release_dates"))
        XCTAssertTrue(r.results.contains { !$0.releaseDates.isEmpty })
    }
}
