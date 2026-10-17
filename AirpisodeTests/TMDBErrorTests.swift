import XCTest
@testable import Airpisode

/// HTTP status handling for `TMDBClient`. A wrong or absent key used to reach the
/// UI as the opaque `NSURLErrorDomain -1011`.
final class TMDBErrorTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func client(key: String = "test-key", status: Int, body: String = "{}") -> TMDBClient {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(body.utf8))
        }
        return TMDBClient(apiKey: { key }, session: MockURLProtocol.session())
    }

    func testUnauthorizedSurfacesTheMissingKeyMessage() async {
        let sut = client(status: 401)

        do {
            _ = try await sut.searchMulti(query: "abbott")
            XCTFail("Expected the request to throw")
        } catch let error as TMDBError {
            XCTAssertEqual(error, .missingKey)
            XCTAssertEqual(error.errorDescription, "Your TMDB API key is missing or invalid. Add it in Settings.")
        } catch {
            XCTFail("Expected a TMDBError, got \(error)")
        }
    }

    func testNotFoundMapsToItsOwnCase() async {
        let sut = client(status: 404)

        do {
            _ = try await sut.tvDetail(id: 1)
            XCTFail("Expected the request to throw")
        } catch let error as TMDBError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("Expected a TMDBError, got \(error)")
        }
    }

    func testOtherFailuresCarryTheStatusCode() async {
        let sut = client(status: 503)

        do {
            _ = try await sut.movieDetail(id: 1)
            XCTFail("Expected the request to throw")
        } catch let error as TMDBError {
            XCTAssertEqual(error, .server(503))
        } catch {
            XCTFail("Expected a TMDBError, got \(error)")
        }
    }

    func testSuccessDecodesAndSendsTheKey() async throws {
        var seen: URL?
        MockURLProtocol.handler = { request in
            seen = request.url
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"results":[]}"#.utf8))
        }
        let sut = TMDBClient(apiKey: { "test-key" }, session: MockURLProtocol.session())

        let results = try await sut.searchMulti(query: "abbott")

        XCTAssertTrue(results.isEmpty)
        let query = try XCTUnwrap(seen?.query)
        XCTAssertTrue(query.contains("api_key=test-key"), "query was \(query)")
        XCTAssertTrue(seen!.path.hasSuffix("/search/multi"))
    }
}
