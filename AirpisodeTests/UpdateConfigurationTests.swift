import XCTest
@testable import Airpisode

final class UpdateConfigurationTests: XCTestCase {
    /// `generate_keys` prints a 32-byte Ed25519 public key as base64.
    private let validKey = Data(repeating: 7, count: 32).base64EncodedString()

    func testAcceptsHTTPSFeedAndEd25519Key() {
        let result = UpdateConfiguration.evaluate(
            feedURLString: "https://example.com/appcast.xml",
            publicKey: validKey
        )

        guard case .success(let configuration) = result else {
            return XCTFail("Expected the feed to be accepted, got \(result)")
        }
        XCTAssertEqual(configuration.feedURL.absoluteString, "https://example.com/appcast.xml")
        XCTAssertEqual(configuration.publicKey, validKey)
    }

    func testTrimsSurroundingWhitespace() {
        let result = UpdateConfiguration.evaluate(
            feedURLString: "  https://example.com/appcast.xml\n",
            publicKey: "  \(validKey)  "
        )

        XCTAssertNoThrow(try result.get())
    }

    func testRejectsMissingFeed() {
        for value in [nil, "", "   "] {
            XCTAssertEqual(
                UpdateConfiguration.evaluate(feedURLString: value, publicKey: validKey),
                .failure(.missingFeedURL)
            )
        }
    }

    /// Xcode leaves an unresolved build setting in place when the xcconfig is absent.
    func testRejectsUnresolvedBuildSetting() {
        XCTAssertEqual(
            UpdateConfiguration.evaluate(feedURLString: "$(SU_FEED_URL)", publicKey: validKey),
            .failure(.missingFeedURL)
        )
    }

    func testRejectsPlainHTTP() {
        XCTAssertEqual(
            UpdateConfiguration.evaluate(feedURLString: "http://example.com/appcast.xml", publicKey: validKey),
            .failure(.insecureFeedURL)
        )
    }

    func testRejectsNonWebScheme() {
        for url in ["ftp://example.com/appcast.xml", "file:///tmp/appcast.xml", "example.com/appcast.xml"] {
            XCTAssertEqual(
                UpdateConfiguration.evaluate(feedURLString: url, publicKey: validKey),
                .failure(.insecureFeedURL)
            )
        }
    }

    func testRejectsMissingKey() {
        for value in [nil, "", "  ", "$(SU_PUBLIC_ED_KEY)"] {
            XCTAssertEqual(
                UpdateConfiguration.evaluate(feedURLString: "https://example.com/appcast.xml", publicKey: value),
                .failure(.missingPublicKey)
            )
        }
    }

    func testRejectsKeyThatIsNotBase64() {
        XCTAssertEqual(
            UpdateConfiguration.evaluate(
                feedURLString: "https://example.com/appcast.xml",
                publicKey: "not base64!"
            ),
            .failure(.malformedPublicKey)
        )
    }

    /// A truncated key would import into Sparkle as an invalid one.
    func testRejectsKeyOfWrongLength() {
        let shortKey = Data(repeating: 1, count: 16).base64EncodedString()
        XCTAssertEqual(
            UpdateConfiguration.evaluate(
                feedURLString: "https://example.com/appcast.xml",
                publicKey: shortKey
            ),
            .failure(.malformedPublicKey)
        )
    }

    func testLoadFallsBackToUnconfiguredWhenTheBundleHasNoFeed() {
        // The test bundle's Info.plist has no Sparkle keys; the app's own bundle is not
        // used here because tests must pass with or without a developer's local xcconfig.
        guard case .failure = UpdateConfiguration.load(from: Bundle(for: Self.self)) else {
            return XCTFail("Expected the test bundle to have no update feed")
        }
    }
}
