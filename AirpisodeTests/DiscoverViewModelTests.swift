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
    func testLoadRecommendationsUsesMostRecentSeedAndCapsAtSix() async {
        let stub = StubTMDBClient()
        stub.similarTitles["movie-20"] = (1...10).map {
            .init(id: $0, mediaType: "movie", name: "Rec \($0)", title: nil, overview: nil, posterPath: nil, firstAirDate: nil, releaseDate: nil)
        }
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)
        var library = Library()
        library.entries = [
            WatchlistEntry(tmdbID: 1, mediaType: .tv, addedAt: older, isTrackingEnabled: true),
            WatchlistEntry(tmdbID: 20, mediaType: .movie, addedAt: newer, isTrackingEnabled: true),
        ]
        let vm = DiscoverViewModel(client: stub)
        await vm.loadRecommendations(library: library)
        XCTAssertEqual(stub.similarRequests, ["movie-20"], "only the most recently added title seeds suggestions")
        XCTAssertEqual(vm.recommendations.count, 6)
    }

    @MainActor
    func testLoadRecommendationsEmptyLibraryDoesNothing() async {
        let stub = StubTMDBClient()
        let vm = DiscoverViewModel(client: stub)
        await vm.loadRecommendations(library: Library())
        XCTAssertTrue(vm.recommendations.isEmpty)
        XCTAssertTrue(stub.similarRequests.isEmpty)
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
