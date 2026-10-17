import SwiftUI

/// Inline detail content: embedded directly in lists, expanded/collapsed per row.
/// No outer ScrollView — the hosting list provides scrolling.
struct TitleDetailContent: View {
    let tmdbID: Int
    let mediaType: MediaType
    let name: String

    @EnvironmentObject private var appState: AppState
    @State private var selectedSeason: Int?
    @State private var previewTitle: Title?
    @State private var cast: [TMDBCastMember] = []

    private var titleID: String { "\(mediaType.rawValue)-\(tmdbID)" }
    private var title: Title? { appState.library.titles[titleID] }
    private var displayTitle: Title? { title ?? previewTitle }
    private var isTracked: Bool { appState.library.entries.contains { $0.id == titleID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            if let title {
                if mediaType == .tv {
                    tvEpisodeList(for: title)
                } else {
                    movieReleaseList
                }
            } else if previewTitle == nil {
                HStack {
                    Spacer()
                    ProgressView().padding(.vertical, 40)
                    Spacer()
                }
            }
            if !cast.isEmpty {
                castSection
            }
        }
        .padding()
        .task(id: titleID) {
            async let castFetch: [TMDBCastMember] = appState.fetchCredits(tmdbID: tmdbID, mediaType: mediaType)
            if let title {
                await appState.refreshTitle(titleID)
            } else {
                previewTitle = await appState.fetchPreviewTitle(tmdbID: tmdbID, mediaType: mediaType)
            }
            cast = await castFetch
        }
    }

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cast")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(cast.prefix(20), id: \.id) { member in
                        CastMemberView(member: member)
                    }
                }
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 20) {
            AsyncImage(url: ImageURL.poster(displayTitle?.posterPath, size: "w342")) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 220)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                Text(displayTitle?.name ?? name)
                    .font(.title).bold()
                if let status = displayTitle?.tvStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Text(displayTitle?.overview ?? "")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Button {
                    if isTracked {
                        appState.removeFromLibrary(titleID)
                    } else if let t = displayTitle {
                        appState.addToLibrary(t)
                        Task { await appState.refreshTitle(titleID) }  // pull episodes/releases right after adding
                    }
                } label: {
                    Label(isTracked ? "Remove from Library" : "Add to Library",
                          systemImage: isTracked ? "minus.circle" : "plus.circle")
                }
                .disabled(displayTitle == nil)
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func tvEpisodeList(for title: Title) -> some View {
        let seasons = title.seasons.filter { $0.seasonNumber > 0 }.map(\.seasonNumber).sorted()
        if seasons.isEmpty {
            Text("No seasons listed").foregroundStyle(.secondary)
        } else {
            Picker("Season", selection: Binding(
                get: { selectedSeason ?? seasons.first },
                set: { selectedSeason = $0 }
            )) {
                ForEach(seasons, id: \.self) { season in
                    Text("Season \(season)").tag(season)
                }
            }
            .pickerStyle(.menu)

            let episodes = (appState.library.episodes[titleID] ?? [])
                .filter { $0.seasonNumber == (selectedSeason ?? seasons.first) }
                .sorted { $0.episodeNumber < $1.episodeNumber }
            ForEach(episodes) { episode in
                EpisodeRowView(episode: episode)
            }
        }
    }

    private var movieReleaseList: some View {
        let releases = (appState.library.movieReleases[titleID] ?? [])
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        return Group {
            if releases.isEmpty {
                Text("No release dates listed").foregroundStyle(.secondary)
            } else {
                ForEach(releases) { release in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(release.kind.label).fontWeight(.medium)
                            Text(release.region).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(releaseDateLabel(release))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func releaseDateLabel(_ release: MovieRelease) -> String {
        guard let date = release.date else { return "TBD" }
        let formatter = DateFormatter()
        if release.hasTime {
            formatter.dateFormat = "MMM d, yyyy 'at' HH:mm"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date)
    }
}

extension ReleaseKind {
    var label: String {
        switch self {
        case .theatrical: return "Theatrical"
        case .digital: return "Digital"
        case .physical: return "Physical"
        case .tv: return "TV"
        }
    }
}
