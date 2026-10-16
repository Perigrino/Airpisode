import Foundation

actor LibraryStore {
    private let fileURL: URL
    init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("library.json")
    }
    static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Airpisode", isDirectory: true)
    }
    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
    func load() -> Library {
        guard let data = try? Data(contentsOf: fileURL) else { return Library() }
        return (try? Self.makeDecoder().decode(Library.self, from: data)) ?? Library()
    }
    func save(_ library: Library) throws {
        let data = try Self.makeEncoder().encode(library)
        let tmp = fileURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
    }
}
