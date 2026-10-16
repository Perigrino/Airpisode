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
    func testShortQueryClearsWithoutNetwork() async {
        let stub = StubTMDBClient()
        let vm = DiscoverViewModel(client: stub)
        vm.query = "a"
        await vm.search()
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertEqual(stub.lastQuery, nil)
    }
}
