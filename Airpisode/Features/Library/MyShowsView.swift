import SwiftUI

struct MyShowsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var expandedID: String?

    private var shows: [Title] {
        appState.library.orderedWithPinnedFirst(
            appState.library.entries
                .filter { $0.mediaType == .tv }
                .compactMap { appState.library.titles[$0.id] }
                .sorted { $0.name < $1.name }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    PageHeader(title: "My Shows",
                               subtitle: subtitle(trackedCount: shows.count))
                    if shows.isEmpty {
                        emptyState
                    } else {
                        ForEach(shows) { title in
                            card(title).id(title.id)
                        }
                    }
                }
                .padding(24)
                .padding(.bottom, DockBar.contentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            // Snap the expanded card to the top so its details are fully in view.
            .onChange(of: expandedID) { newValue in
                guard let id = newValue else { return }
                withAnimation(Motion.smooth) { proxy.scrollTo(id, anchor: .top) }
            }
        }
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
            Button {
                withAnimation(Motion.smooth) {
                    expandedID = expandedID == title.id ? nil : title.id
                }
            } label: {
                TitleRowView(title: title, nextLabel: nextLabel(for: title),
                             isExpanded: expandedID == title.id,
                             badge: appState.library.isMuted(title.id) ? "Muted" : nil)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    appState.setPinned(!appState.library.isPinned(title.id), titleID: title.id)
                } label: {
                    Label(appState.library.isPinned(title.id) ? "Unpin" : "Pin to top",
                          systemImage: "pin")
                }
                Button {
                    appState.setAlertsMuted(!appState.library.isMuted(title.id), titleID: title.id)
                } label: {
                    Label(appState.library.isMuted(title.id) ? "Unmute alerts" : "Mute alerts",
                          systemImage: appState.library.isMuted(title.id) ? "bell.fill" : "bell.slash")
                }
                Menu("Pre-release alert") {
                    ForEach(AlertOverride.allCases) { option in
                        Button {
                            appState.setPreAlertOverride(option, titleID: title.id)
                        } label: {
                            if preAlertOverride(for: title.id) == option {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                }
                Divider()
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
                    .contentShape(Rectangle())
                    .onTapGesture { collapse() }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(PosterTintedCard(posterPath: title.posterPath))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hoverLift()
    }

    private func preAlertOverride(for titleID: String) -> AlertOverride {
        appState.library.entries.first(where: { $0.id == titleID })?.preAlertOverride ?? .inherit
    }

    private func subtitle(trackedCount: Int) -> String {
        if trackedCount == 0 { return "Track your first show from Discover" }
        return "\(trackedCount) show\(trackedCount == 1 ? "" : "s") tracked"
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
        .appear()
    }

    private func collapse() {
        withAnimation(Motion.smooth) { expandedID = nil }
    }

    private func nextLabel(for title: Title) -> String? {
        if let episode = appState.library.nextEpisode(forTitle: title.id) {
            let when = episode.airDate.map { EpisodeRowView.dayFormatter.string(from: $0) } ?? "TBD"
            return "Next: S\(episode.seasonNumber)E\(episode.episodeNumber) · \(when)"
        }
        // Season gap: the current season is over, but TMDB may already know the next
        // airing — often the premiere of a season months away.
        if let airing = title.nextAiring, let date = airing.airDate, date >= .now {
            let when = EpisodeRowView.dayFormatter.string(from: date)
            if airing.episodeNumber == 1 {
                return "Season \(airing.seasonNumber) · \(when)"
            }
            return "Next: S\(airing.seasonNumber)E\(airing.episodeNumber) · \(when)"
        }
        return nil
    }
}
