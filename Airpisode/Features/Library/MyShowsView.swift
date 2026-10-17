import SwiftUI

struct MyShowsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var expandedID: String?

    private var shows: [Title] {
        appState.library.entries
            .filter { $0.mediaType == .tv }
            .compactMap { appState.library.titles[$0.id] }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                PageHeader(title: "My Shows",
                           subtitle: shows.isEmpty ? "Track your first show from Discover"
                                                   : "\(shows.count) show\(shows.count == 1 ? "" : "s") tracked")
                if shows.isEmpty {
                    emptyState
                } else {
                    ForEach(shows) { title in
                        card(title)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .screenBackground()
        .navigationTitle("My Shows")
        .toolbar {
            Button {
                appState.selectedSection = .discover
            } label: {
                Label("Add Show", systemImage: "plus")
            }
            .help("Find a show in Discover")
        }
    }

    @ViewBuilder
    private func card(_ title: Title) -> some View {
        VStack(spacing: 0) {
            TitleRowView(title: title, nextLabel: nextLabel(for: title),
                         isExpanded: expandedID == title.id)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedID = expandedID == title.id ? nil : title.id
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        appState.removeFromLibrary(title.id)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            if expandedID == title.id {
                TitleDetailContent(tmdbID: title.tmdbID, mediaType: .tv, name: title.name)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(Theme.cardBackground(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tv")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No shows yet")
                .font(.headline)
            Button {
                appState.selectedSection = .discover
            } label: {
                Label("Find Shows in Discover", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func nextLabel(for title: Title) -> String? {
        guard let episode = appState.library.nextEpisode(forTitle: title.id) else { return nil }
        let when = episode.airDate.map { EpisodeRowView.dayFormatter.string(from: $0) } ?? "TBD"
        return "Next: S\(episode.seasonNumber)E\(episode.episodeNumber) · \(when)"
    }
}
