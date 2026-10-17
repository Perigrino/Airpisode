import XCTest
@testable import Airpisode

final class DiscoverViewModelTests: XCTestCase {
    @MainActor
    func testSearchFiltersOutPersonsAndKeepsTitles() async {
        let stub = StubTMDBClient()
        stub.searchResults = [
            .init(id: 1, mediaType: "tv", name: "Severance", title: nil, overview: nil, posterPath: nil, firstAirDate: nil, releaseDate: nil),
            .init(id: 2, mediaType: "movie", name: nil, title: "Dune", overview: nil, posterPath: nil, firstAirDate: nil, releaseDate: nil),
            .init(id: 3, mediaType: "person", name: "Adam Scott", title: nil, overview: nil, posterPath: nil, firstAirDate: nil, releaseDate: nil),
        ]
        let vm = DiscoverViewModel(client: stub)
        vm.query = "severance"
        await vm.search()
        XCTAssertEqual(vm.results.map(\.id), [1, 2])
        XCTAssertFalse(vm.results.contains { $0.mediaType == "person" })
    }

    @MainActor
    func testLoadRecommendationsDedupesExcludesTrackedAndCaps() async {
        let stub = StubTMDBClient()
        stub.recommendations["tv-1"] = [
            .init(id: 10, mediaType: "tv", name: "Rec A", title: nil, overview: nil, posterPath: nil, firstAirDate: nil, releaseDate: nil),
            .init(id: 20, mediaType: "tv", name: "Rec B", title: nil, overview: nil, posterPath: nil, firstAirDate: nil, releaseDate: nil),
        ]
        stub.recommendations["movie-20"] = [
            .init(id: 20, mediaType: "movie", name: "Same ID other type", title: nil, overview: nil, posterPath: nil, firstAirDate: nil, releaseDate: nil),
            .init(id: 30, mediaType: "movie", name: "Rec C", title: nil, overview: nil, posterPath: nil, firstAirDate: nil, releaseDate: nil),
            .init(id: 20, mediaType: "movie", name: "Duplicate", title: nil, overview: nil, posterPath: nil, firstAirDate: nil, releaseDate: nil),
        ]
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)
        var library = Library()
        library.entries = [
            WatchlistEntry(tmdbID: 1, mediaType: .tv, addedAt: older, isTrackingEnabled: true),
            WatchlistEntry(tmdbID: 20, mediaType: .movie, addedAt: newer, isTrackingEnabled: true),
        ]
        let vm = DiscoverViewModel(client: stub)
        await vm.loadRecommendations(library: library)
        // Most recently added first → movie-20's recs before tv-1's.
        XCTAssertEqual(stub.recommendationRequests, ["movie-20", "tv-1"])
        XCTAssertEqual(vm.recommendations.map { "\($0.mediaType)-\($0.id)" }, ["movie-30", "tv-10", "tv-20"])
        XCTAssertFalse(vm.recommendations.contains { $0.id == 20 && $0.mediaType == "movie" }, "already-tracked title excluded")
    }

    @MainActor
    func testLoadRecommendationsEmptyLibraryDoesNothing() async {
        let stub = StubTMDBClient()
        let vm = DiscoverViewModel(client: stub)
        await vm.loadRecommendations(library: Library())
        XCTAssertTrue(vm.recommendations.isEmpty)
        XCTAssertTrue(stub.recommendationRequests.isEmpty)
    }

    @MainActor
    func testShortQueryClearsWithoutNetwork() async {
        let stub = StubTMDBClient()
        let vm = DiscoverViewModel(client: stub)
        vm.query = "a"
        await vm.search()
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertEqual(stub.lastQuery, nil)
    }
}
