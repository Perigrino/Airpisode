import Foundation

enum ImageURL {
    /// Builds `https://image.tmdb.org/t/p/<size><path>`; nil when path is missing or malformed.
    static func poster(_ path: String?, size: String = "w185") -> URL? {
        guard let path, path.hasPrefix("/") else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }
}
