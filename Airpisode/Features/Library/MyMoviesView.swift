import SwiftUI

struct MyMoviesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var expandedID: String?

    private var movies: [Title] {
        appState.library.entries
            .filter { $0.mediaType == .movie }
            .compactMap { appState.library.titles[$0.id] }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                PageHeader(title: "My Movies",
                           subtitle: movies.isEmpty ? "Track your first movie from Discover"
                                                    : "\(movies.count) movie\(movies.count == 1 ? "" : "s") tracked")
                if movies.isEmpty {
                    emptyState
                } else {
                    ForEach(movies) { title in
                        card(title)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .screenBackground()
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

    @ViewBuilder
    private func card(_ title: Title) -> some View {
        VStack(spacing: 0) {
            TitleRowView(title: title, nextLabel: nextLabel(for: title),
                         isExpanded: expandedID == title.id)
                .onTapGesture {
                    withAnimation(Motion.smooth) {
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
                TitleDetailContent(tmdbID: title.tmdbID, mediaType: .movie, name: title.name)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Theme.cardBackground(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hoverLift()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No movies yet")
                .font(.headline)
            Button {
                appState.selectedSection = .discover
            } label: {
                Label("Find Movies in Discover", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .appear()
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
