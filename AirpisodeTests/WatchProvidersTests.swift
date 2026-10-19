import XCTest
@testable import Airpisode

final class WatchProvidersTests: XCTestCase {
    private func response(_ region: String, flatrate: [TMDBWatchProvider]) -> TMDBWatchProvidersResponse {
        TMDBWatchProvidersResponse(results: [region: TMDBRegionProviders(
            link: "https://www.justwatch.com/rest/region", flatrate: flatrate, rent: nil, buy: nil
        )])
    }

    @MainActor
    func testFetchWatchProvidersResolvesTheRequestedRegion() async {
        let stub = StubTMDBClient()
        stub.watchProvidersResult = response(
            "US", flatrate: [TMDBWatchProvider(providerID: 8, name: "Netflix", logoPath: "/netflix.jpg")]
        )
        let app = AppState(
            store: LibraryStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)),
            tmdb: stub
        )

        let result = await app.fetchWatchProviders(mediaType: .movie, tmdbID: 7, region: "US")

        XCTAssertEqual(stub.watchProvidersCallCount, 1)
        XCTAssertEqual(result?.flatrate?.count, 1)
        XCTAssertEqual(result?.flatrate?.first?.name, "Netflix")
        XCTAssertEqual(result?.link, "https://www.justwatch.com/rest/region")
    }

    @MainActor
    func testFetchWatchProvidersReturnsNilForARegionTMDBDoesNotList() async {
        let stub = StubTMDBClient()
        stub.watchProvidersResult = response("US", flatrate: [])
        let app = AppState(
            store: LibraryStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)),
            tmdb: stub
        )

        let result = await app.fetchWatchProviders(mediaType: .tv, tmdbID: 7, region: "DE")

        XCTAssertNil(result)
        XCTAssertEqual(stub.watchProvidersCallCount, 1)
    }

    @MainActor
    func testRegionLookupIsCaseInsensitive() async {
        let stub = StubTMDBClient()
        stub.watchProvidersResult = response(
            "US", flatrate: [TMDBWatchProvider(providerID: 3, name: "Max", logoPath: "/max.jpg")]
        )
        let app = AppState(
            store: LibraryStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)),
            tmdb: stub
        )

        let result = await app.fetchWatchProviders(mediaType: .movie, tmdbID: 7, region: "us")

        XCTAssertEqual(result?.flatrate?.first?.name, "Max")
    }
}
