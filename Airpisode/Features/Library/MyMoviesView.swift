import SwiftUI

struct MyMoviesView: View {
    @EnvironmentObject private var appState: AppState

    private var movies: [Title] {
        appState.library.entries
            .filter { $0.mediaType == .movie }
            .compactMap { appState.library.titles[$0.id] }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Group {
            if movies.isEmpty {
                VStack(spacing: 12) {
                    Text("No movies yet")
                        .foregroundStyle(.secondary)
                    Button {
                        appState.selectedSection = .discover
                    } label: {
                        Label("Find Movies in Discover", systemImage: "plus.circle")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(movies) { title in
                    NavigationLink {
                        TitleDetailView(tmdbID: title.tmdbID, mediaType: .movie, name: title.name)
                    } label: {
                        TitleRowView(title: title, nextLabel: nextLabel(for: title))
                    }
                    .contextMenu {
                            Button(role: .destructive) {
                                appState.removeFromLibrary(title.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("My Movies")
        .toolbar {
            Button {
                appState.selectedSection = .discover
            } label: {
                Label("Add Movie", systemImage: "plus")
            }
            .help("Find a movie in Discover")
        }
    }

    private func nextLabel(for title: Title) -> String? {
        guard let release = (appState.library.movieReleases[title.id] ?? [])
            .filter({ ($0.date ?? .distantPast) >= .now })
            .min(by: { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }),
              let date = release.date
        else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = release.hasTime ? "MMM d 'at' HH:mm" : "MMM d"
        return "\(release.kind.label): \(formatter.string(from: date))"
    }
}
