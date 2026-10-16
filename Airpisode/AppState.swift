import SwiftUI

enum Secrets {
    static var tmdbKey: String {
        Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String ?? ""
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var lastRefreshError: String?
}
