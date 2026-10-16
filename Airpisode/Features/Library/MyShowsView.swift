import SwiftUI

struct MyShowsView: View {
    @EnvironmentObject private var appState: AppState

    private var shows: [Title] {
        appState.library.entries
            .filter { $0.mediaType == .tv }
            .compactMap { appState.library.titles[$0.id] }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Group {
            if shows.isEmpty {
                Text("Add your first show in Discover")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shows) { title in
                    TitleRowView(title: title, nextLabel: nextLabel(for: title))
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
        .navigationTitle("My Shows")
    }

    private func nextLabel(for title: Title) -> String? {
        guard let episode = appState.library.nextEpisode(forTitle: title.id) else { return nil }
        let when = episode.airDate.map { EpisodeRowView.dayFormatter.string(from: $0) } ?? "TBD"
        return "Next: S\(episode.seasonNumber)E\(episode.episodeNumber) · \(when)"
    }
}
