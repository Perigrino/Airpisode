import XCTest
@testable import Airpisode

/// Trailer selection + fetch plumbing. One thing matters: when videos come back, the button
/// links to the ONE video a person would call the trailer — official trailers first, plain
/// trailers next, teasers as the last resort, YouTube only.
final class TrailerPickingTests: XCTestCase {
    private func makeStub(_ videos: [TMDBVideo]) -> StubTMDBClient {
        let stub = StubTMDBClient()
        stub.videosResult = videos
        return stub
    }

    func testOfficialTrailerWinsOverLaterPlainTrailer() {
        let videos = [
            TMDBVideo(id: "v1", key: "plain", name: "Trailer", site: "YouTube", type: "Trailer", official: false),
            TMDBVideo(id: "v2", key: "official", name: "Official Trailer", site: "YouTube", type: "Trailer", official: true),
        ]
        XCTAssertEqual(makeStub(videos).videosResult?.youTubeTrailer?.key, "official")
    }

    func testPlainTrailerBeatsTeaserAndClip() {
        let videos = [
            TMDBVideo(id: "v1", key: "teaser", name: "Teaser", site: "YouTube", type: "Teaser", official: true),
            TMDBVideo(id: "v2", key: "clip", name: "Clip", site: "YouTube", type: "Clip", official: false),
            TMDBVideo(id: "v3", key: "trailer", name: "Trailer", site: "YouTube", type: "Trailer", official: false),
        ]
        XCTAssertEqual(makeStub(videos).videosResult?.youTubeTrailer?.key, "trailer")
    }

    func testIgnoresNotYouTubeAndFallsBackToTeaser() {
        let videos = [
            TMDBVideo(id: "v1", key: "vim", name: "Trailer", site: "Vimeo", type: "Trailer", official: true),
            TMDBVideo(id: "v2", key: "teaser", name: "Teaser", site: "YouTube", type: "Teaser", official: false),
        ]
        XCTAssertEqual(makeStub(videos).videosResult?.youTubeTrailer?.key, "teaser")
    }

    @MainActor
    func testFetchTrailerReturnsYouTubeURLOrNilWhenUnreachable() async {
        // Reachable stub: one plain trailer.
        let stub = makeStub([TMDBVideo(id: "v1", key: "abc123", name: "Trailer", site: "YouTube", type: "Trailer", official: false)])
        let app = AppState(store: LibraryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), tmdb: stub)
        let url = await app.fetchTrailer(tmdbID: 42, mediaType: .movie)
        XCTAssertEqual(url?.absoluteString, "https://youtube.com/watch?v=abc123")
        XCTAssertEqual(stub.videosCallCount, 1)

        // Unreachable stub: no URL, no crash.
        let dead = AppState(store: LibraryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), tmdb: StubTMDBClient())
        let nilURL = await dead.fetchTrailer(tmdbID: 42, mediaType: .tv)
        XCTAssertNil(nilURL)
    }
}
