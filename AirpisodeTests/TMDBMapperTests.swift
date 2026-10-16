import XCTest
@testable import Airpisode

final class TMDBMapperTests: XCTestCase {
    func testParsesDateOnlyAsNoonUTC() {
        let d = TMDBMapper.parseDate("2026-10-16")
        XCTAssertNotNil(d)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.hour, .day], from: d!)
        XCTAssertEqual(comps.hour, 12)
        XCTAssertEqual(comps.day, 16)
    }

    func testParsesFullDateTime() {
        let d = TMDBMapper.parseDateTime("2026-10-16T20:00:00.000Z")
        XCTAssertNotNil(d)
        // 20:00 UTC
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(cal.component(.hour, from: d!), 20)
    }

    func testParsesPlainISODateTimeFallback() {
        let d = TMDBMapper.parseDateTime("2026-10-16T20:00:00Z")
        XCTAssertNotNil(d)
    }

    func testMovieReleaseMappingMarksTypeAndTimed() {
        let resp = TMDBReleaseDatesResponse(id: 1, results: [
            TMDBRegionReleases(iso3166_1: "US", releaseDates: [
                TMDBReleaseDate(certification: "PG-13", releaseDate: "2026-10-16T20:00:00.000Z", type: 1),
                TMDBReleaseDate(certification: nil, releaseDate: "2026-11-01", type: 2),
                TMDBReleaseDate(certification: nil, releaseDate: "2026-12-01", type: 99), // unknown type
            ])
        ])
        let rel = TMDBMapper.movieReleases(resp, movieID: 1, region: "US")
        XCTAssertEqual(rel.count, 2)
        XCTAssertEqual(rel[0].kind, .theatrical)
        XCTAssertEqual(rel[0].hasTime, true)
        XCTAssertEqual(rel[1].kind, .digital)
        XCTAssertEqual(rel[1].hasTime, false) // date-only stays honest
    }

    func testMovieReleaseFiltersOtherRegions() {
        let resp = TMDBReleaseDatesResponse(id: 1, results: [
            TMDBRegionReleases(iso3166_1: "US", releaseDates: [
                TMDBReleaseDate(certification: nil, releaseDate: "2026-10-16T20:00:00.000Z", type: 1)]),
            TMDBRegionReleases(iso3166_1: "FR", releaseDates: [
                TMDBReleaseDate(certification: nil, releaseDate: "2026-10-16T20:00:00.000Z", type: 1)]),
        ])
        let rel = TMDBMapper.movieReleases(resp, movieID: 1, region: "US")
        XCTAssertEqual(rel.count, 1)
        XCTAssertEqual(rel[0].region, "US")
    }

    func testEpisodeMapping() {
        let season = TMDBSeason(seasonNumber: 2, episodes: [
            TMDBTVEpisode(episodeNumber: 1, seasonNumber: 2, name: "Good News About Hell",
                          overview: "o", airDate: "2025-01-17", stillPath: nil),
            TMDBTVEpisode(episodeNumber: 2, seasonNumber: 2, name: "Untitled", overview: nil,
                          airDate: nil, stillPath: nil),
        ])
        let eps = TMDBMapper.episodes(season, tvID: 100088)
        XCTAssertEqual(eps.count, 2)
        XCTAssertEqual(eps[0].id, "100088-s2e1")
        XCTAssertNotNil(eps[0].airDate)
        XCTAssertNil(eps[1].airDate, "missing air date stays nil — never invented")
    }

    func testTVTitleMapping() {
        let detail = TMDBTVDetail(id: 100088, name: "The Last of Us", overview: "o",
                                  posterPath: "/x.jpg", firstAirDate: "2023-01-15",
                                  status: "Returning Series",
                                  seasons: [TMDBSeasonSummary(seasonNumber: 1, episodeCount: 9, airDate: "2023-01-15")])
        let title = TMDBMapper.title(from: detail)
        XCTAssertEqual(title.id, "tv-100088")
        XCTAssertEqual(title.mediaType, .tv)
        XCTAssertNotNil(title.firstAirDate)
        XCTAssertEqual(title.seasons.count, 1)
    }

    func testMovieTitleMapping() {
        let detail = TMDBMovieDetail(id: 693134, title: "Dune: Part Two", overview: "o",
                                     posterPath: "/x.jpg", releaseDate: "2024-03-01")
        let title = TMDBMapper.title(from: detail)
        XCTAssertEqual(title.id, "movie-693134")
        XCTAssertEqual(title.name, "Dune: Part Two")
    }
}
