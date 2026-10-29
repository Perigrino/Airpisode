import Foundation

/// Reads and writes the library as a single JSON document, with the failure behaviour a
/// personal library deserves: never silently replace unreadable data, always keep the last
/// good copy, and only let the newest write win.
actor LibraryStore {
    struct LoadReport: Sendable {
        let library: Library
        /// A non-nil message describes a recovery the person should know about.
        let warning: String?
    }

    private let directory: URL
    private let fileURL: URL
    private let backupURL: URL
    private var lastSequence: UInt64 = 0

    init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.directory = dir
        fileURL = dir.appendingPathComponent("library.json")
        backupURL = dir.appendingPathComponent("library.backup.json")
    }

    static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Airpisode", isDirectory: true)
    }

    /// Convenience for callers and tests that only need the value.
    func load() -> Library {
        loadReport().library
    }

    /// Loads the primary file, falling back to the last good backup. A file that exists but
    /// cannot be decoded is copied aside before anything overwrites it, so a schema regression
    /// or a truncated write is recoverable by hand instead of being lost.
    func loadReport() -> LoadReport {
        let primaryExists = FileManager.default.fileExists(atPath: fileURL.path)

        if primaryExists {
            if let library = decode(fileURL) {
                return LoadReport(library: library, warning: nil)
            }
            let preserved = preserveUnreadablePrimary()
            let kept = preserved.map { " The unreadable file was kept as \($0)." } ?? ""
            if let backup = decode(backupURL) {
                return LoadReport(
                    library: backup,
                    warning: "Your library file couldn't be read, so the last backup was restored.\(kept)"
                )
            }
            return LoadReport(
                library: Library(),
                warning: "Your library file couldn't be read and no backup was available.\(kept)"
            )
        }

        if let backup = decode(backupURL) {
            return LoadReport(
                library: backup,
                warning: "Your library file was missing, so the last backup was restored."
            )
        }
        return LoadReport(library: Library(), warning: nil)
    }

    /// Writes the document, keeping the newest sequence. Two overlapping saves can finish in
    /// any order; the older snapshot is discarded instead of overwriting newer state.
    func save(_ library: Library, sequence: UInt64 = 0) throws {
        guard sequence >= lastSequence else { return }
        let data = try Self.makeEncoder().encode(library)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let tmp = directory.appendingPathComponent("library.json.tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: fileURL)
        }

        // The backup is written only after the primary lands, so it is always a complete
        // document. A failed copy must not fail a save that already succeeded.
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.copyItem(at: fileURL, to: backupURL)
        lastSequence = sequence
    }

    private func decode(_ url: URL) -> Library? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.makeDecoder().decode(Library.self, from: data)
    }

    /// Copies the unreadable primary beside itself. Returns the new file name, or nil when
    /// even the copy fails (a permissions problem).
    private func preserveUnreadablePrimary() -> String? {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let name = "library.corrupt-\(stamp).json"
        let destination = directory.appendingPathComponent(name)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: fileURL, to: destination)
            return name
        } catch {
            return nil
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
}
