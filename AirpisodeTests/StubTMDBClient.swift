import Foundation
@testable import Airpisode

/// In-memory TMDB client for tests. Assign canned results per test; call counts are recorded.
final class StubTMDBClient: TMDBClientProtocol, @unchecked Sendable {
    var searchResults: [TMDBSearchResult] = []
    var lastQuery: String?
    var tvDetailResult: TMDBTVDetail?
    var seasons: [Int: TMDBSeason] = [:]
    var movieDetailResult: TMDBMovieDetail?
    var releaseDatesResult: TMDBReleaseDatesResponse?
    var tvDetailCallCount = 0
    var movieDetailCallCount = 0
    var seasonCallNumbers: [Int] = []

    func searchMulti(query: String) async throws -> [TMDBSearchResult] {
        lastQuery = query
        return searchResults
    }

    func tvDetail(id: Int) async throws -> TMDBTVDetail {
        tvDetailCallCount += 1
        guard let tvDetailResult else { throw URLError(.badServerResponse) }
        return tvDetailResult
    }

    func season(tvID: Int, season: Int) async throws -> TMDBSeason {
        seasonCallNumbers.append(season)
        guard let s = seasons[season] else { throw URLError(.badServerResponse) }
        return s
    }

    func movieDetail(id: Int) async throws -> TMDBMovieDetail {
        movieDetailCallCount += 1
        guard let movieDetailResult else { throw URLError(.badServerResponse) }
        return movieDetailResult
    }

    func movieReleaseDates(id: Int) async throws -> TMDBReleaseDatesResponse {
        guard let releaseDatesResult else { throw URLError(.badServerResponse) }
        return releaseDatesResult
    }
}
