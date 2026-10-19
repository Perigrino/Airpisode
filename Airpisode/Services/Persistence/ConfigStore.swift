import Foundation

/// App settings persisted in a dedicated file beside the library:
/// `~/Library/Application Support/Airpisode/config.json`.
///
/// Deliberately not UserDefaults: that store is generic to the machine and can be
/// cleared at any time. Everything Airpisode owns lives in its own folder.
enum ConfigStore {
    private struct Config: Codable {
        var tmdbAPIKey: String?
        var defaultRegion: String?
    }

    private static let filename = "config.json"
    /// Where the key used to live before it moved into this file.
    private static let legacyDefaultsKey = "tmdbAPIKey"

    static var fileURL: URL {
        LibraryStore.defaultDirectory().appendingPathComponent(filename)
    }

    // MARK: - API key

    static var tmdbAPIKey: String {
        (read().tmdbAPIKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func setTMDBAPIKey(_ value: String) {
        var config = read()
        config.tmdbAPIKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
        write(config)
    }

    // MARK: - Region

    static var defaultRegion: String {
        let stored = (read().defaultRegion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return stored.isEmpty ? autoRegion() : stored
    }

    /// The region used when the user has never picked one: the Mac's own locale region,
    /// so a German Mac sees German release dates instead of silently hard-coded "US".
    static func autoRegion(for locale: Locale = .current) -> String {
        locale.region?.identifier ?? "US"
    }

    static func setDefaultRegion(_ value: String) {
        var config = read()
        config.defaultRegion = value.trimmingCharacters(in: .whitespacesAndNewlines)
        write(config)
    }

    // MARK: - Storage

    private static func read() -> Config {
        var config: Config
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            config = decoded
        } else {
            config = Config()
        }
        return migrateLegacyKey(into: config)
    }

    private static func write(_ config: Config) {
        do {
            try FileManager.default.createDirectory(
                at: LibraryStore.defaultDirectory(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: fileURL, options: .atomic)
        } catch {
            // Settings are best-effort; a failed write just means we ask again next launch.
        }
    }

    /// One-time move of a key saved in the old UserDefaults location.
    private static func migrateLegacyKey(into config: Config) -> Config {
        guard let legacy = UserDefaults.standard.string(forKey: legacyDefaultsKey) else { return config }
        let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
        var config = config
        if (config.tmdbAPIKey ?? "").isEmpty, !trimmed.isEmpty {
            config.tmdbAPIKey = trimmed
            write(config)
        }
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        return config
    }
}

/// Country codes offered by the Settings region picker, labelled in the user's language and
/// sorted by name. The picker always also includes the currently stored region even when it
/// is not part of this list.
enum RegionCatalog {
    /// Regions TMDB serves release-date and watch-provider data for. Deliberately bounded —
    /// a 420-point-wide Settings window needs a plain menu, not a world gazetteer.
    static let codes: [String] = [
        "US", "GB", "CA", "AU", "NZ", "IE", "FR", "DE", "ES", "IT", "NL", "BE", "CH", "AT",
        "SE", "NO", "DK", "FI", "PL", "PT", "CZ", "HU", "RO", "GR", "TR", "UA",
        "BR", "MX", "AR", "CL", "CO", "PE", "JP", "KR", "CN", "HK", "TW", "IN", "ID",
        "TH", "MY", "SG", "PH", "VN", "ZA", "NG", "EG", "AE", "IL", "SA",
    ]

    static func label(for code: String, in locale: Locale = .current) -> String {
        let name = locale.localizedString(forRegionCode: code) ?? ""
        return name.isEmpty ? code : "\(name) (\(code))"
    }

    /// Picker entries sorted by display name, `current` always present even off-list.
    static func options(including current: String, in locale: Locale = .current) -> [(code: String, title: String)] {
        var all = Set(codes)
        all.insert(current)
        return all
            .map { (code: $0, title: label(for: $0, in: locale)) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
