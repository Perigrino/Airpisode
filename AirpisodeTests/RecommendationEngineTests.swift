import XCTest
@testable import Airpisode

final class RecommendationEngineTests: XCTestCase {
    private let now = TMDBMapper.parseDate("2026-10-16")!

    private func candidate(id: Int, type: String = "tv", name: String,
                           votes: Int? = 500, score: Double? = 8.0) -> TMDBSearchResult {
        TMDBSearchResult(id: id, mediaType: type, name: name, title: nil, overview: nil,
                         posterPath: nil, firstAirDate: nil, releaseDate: nil,
                         popularity: 10, voteAverage: score, voteCount: votes)
    }

    /// Two tracked titles: tv-100 added now, movie-200 added a day earlier.
    private func makeLibrary() -> Library {
        var lib = Library()
        lib.titles["tv-100"] = Title(tmdbID: 100, mediaType: .tv, name: "Severance",
                                     overview: "", posterPath: nil, firstAirDate: nil,
                                     tvStatus: nil, seasons: [], lastRefreshed: now)
        lib.titles["movie-200"] = Title(tmdbID: 200, mediaType: .movie, name: "Dune",
                                        overview: "", posterPath: nil, firstAirDate: nil,
                                        tvStatus: nil, seasons: [], lastRefreshed: now)
        lib.entries = [
            WatchlistEntry(tmdbID: 100, mediaType: .tv, addedAt: now, isTrackingEnabled: true),
            WatchlistEntry(tmdbID: 200, mediaType: .movie,
                           addedAt: now.addingTimeInterval(-86_400), isTrackingEnabled: true),
        ]
        return lib
    }

    func testCandidateFromBothSeedsOutranksSingleSeed() async {
        let stub = StubTMDBClient()
        let shared = candidate(id: 900, name: "Shared")
        // Higher score, but recommended by only one seed.
        let single = candidate(id: 901, name: "Single", score: 9.5)
        stub.recommendationTitles["tv-100"] = [shared, single]
        stub.recommendationTitles["movie-200"] = [shared]

        let suggestion = await RecommendationEngine(client: stub).suggestions(for: makeLibrary())

        XCTAssertEqual(suggestion.items.map(\.uniqueID), ["tv-900", "tv-901"])
    }

    func testExcludesTrackedTitlesAndPeople() async {
        let stub = StubTMDBClient()
        stub.recommendationTitles["tv-100"] = [
            candidate(id: 100, name: "Already tracked"),
            candidate(id: 5, type: "person", name: "An Actor"),
            candidate(id: 902, name: "Fresh"),
        ]

        let suggestion = await RecommendationEngine(client: stub).suggestions(for: makeLibrary())

        XCTAssertEqual(suggestion.items.map(\.uniqueID), ["tv-902"])
    }

    func testFiltersThinVoteCountWhenBetterOptionsExist() async {
        let stub = StubTMDBClient()
        stub.recommendationTitles["tv-100"] = [
            candidate(id: 903, name: "Obscure", votes: 10),
            candidate(id: 904, name: "Established", votes: 1000),
        ]

        let suggestion = await RecommendationEngine(client: stub).suggestions(for: makeLibrary())

        XCTAssertEqual(suggestion.items.map(\.uniqueID), ["tv-904"])
    }

    func testKeepsThinVoteCountWhenNothingElseRemains() async {
        let stub = StubTMDBClient()
        stub.recommendationTitles["tv-100"] = [candidate(id: 903, name: "Obscure", votes: 10)]

        let suggestion = await RecommendationEngine(client: stub).suggestions(for: makeLibrary())

        XCTAssertEqual(suggestion.items.map(\.uniqueID), ["tv-903"])
    }

    func testFallsBackToSimilarWhenRecommendationsEmpty() async {
        let stub = StubTMDBClient()
        stub.recommendationTitles["tv-100"] = []
        stub.similarTitles["tv-100"] = [candidate(id: 905, name: "Similar")]
        stub.recommendationTitles["movie-200"] = []
        stub.similarTitles["movie-200"] = []

        let suggestion = await RecommendationEngine(client: stub).suggestions(for: makeLibrary())

        XCTAssertEqual(suggestion.items.map(\.uniqueID), ["tv-905"])
        XCTAssertEqual(stub.recommendationRequests.sorted(), ["movie-200", "tv-100"])
        XCTAssertEqual(stub.similarRequests.sorted(), ["movie-200", "tv-100"])
    }

    func testSeedsAreMostRecentlyAddedFirst() async {
        let stub = StubTMDBClient()
        stub.recommendationTitles["tv-100"] = [candidate(id: 900, name: "A")]
        stub.recommendationTitles["movie-200"] = [candidate(id: 901, name: "B")]

        let suggestion = await RecommendationEngine(client: stub).suggestions(for: makeLibrary())

        XCTAssertEqual(suggestion.seedNames, ["Severance", "Dune"])
    }
}
