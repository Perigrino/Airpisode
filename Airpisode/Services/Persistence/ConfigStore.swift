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
        return stored.isEmpty ? "US" : stored
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
