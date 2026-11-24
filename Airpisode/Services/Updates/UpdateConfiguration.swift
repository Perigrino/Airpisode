import Foundation

/// The update feed settings a build ships with, read from `Info.plist`.
///
/// Kept free of Sparkle so the validation rules are unit-testable, and so a development
/// build without a feed never starts an updater that would point at a placeholder host.
/// The real values live in `Airpisode/Config/Sparkle.local.xcconfig`, which is not
/// committed; see `docs/UPDATES.md`.
struct UpdateConfiguration: Equatable {
    enum Problem: Error, Equatable {
        /// `SUFeedURL` is empty, so this build was compiled without release settings.
        case missingFeedURL
        /// Sparkle downloads and installs whatever the feed points at: HTTPS only.
        case insecureFeedURL
        /// `SUPublicEDKey` is empty, so feeds and archives could not be verified.
        case missingPublicKey
        /// The configured key is not a base64-encoded 32-byte Ed25519 public key.
        case malformedPublicKey

        var message: String {
            switch self {
            case .missingFeedURL:
                return "This build has no update feed configured."
            case .insecureFeedURL:
                return "The update feed must be an HTTPS URL."
            case .missingPublicKey:
                return "This build has no update signing key configured."
            case .malformedPublicKey:
                return "The update signing key is not a valid EdDSA public key."
            }
        }
    }

    let feedURL: URL
    let publicKey: String

    /// Reads `SUFeedURL` and `SUPublicEDKey` from a bundle's Info.plist.
    static func load(from bundle: Bundle = .main) -> Result<UpdateConfiguration, Problem> {
        let info = bundle.infoDictionary ?? [:]
        return evaluate(
            feedURLString: info["SUFeedURL"] as? String,
            publicKey: info["SUPublicEDKey"] as? String
        )
    }

    /// The validation rule on its own, so tests do not need a bundle.
    static func evaluate(
        feedURLString: String?,
        publicKey: String?
    ) -> Result<UpdateConfiguration, Problem> {
        let feed = (feedURLString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !feed.isEmpty, !feed.contains("$(") else { return .failure(.missingFeedURL) }

        guard let url = URL(string: feed),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty
        else {
            return .failure(.insecureFeedURL)
        }

        let key = (publicKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("$(") else { return .failure(.missingPublicKey) }
        guard let decoded = Data(base64Encoded: key), decoded.count == 32 else {
            return .failure(.malformedPublicKey)
        }

        return .success(UpdateConfiguration(feedURL: url, publicKey: key))
    }
}
