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
        VStack(alignment: .leading, spacing: 18) {
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
        .padding(.top, 4)
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

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 20) {
            AsyncImage(url: ImageURL.poster(displayTitle?.posterPath, size: "w342")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Theme.posterPlaceholder
            }
            .frame(width: 200, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text(displayTitle?.name ?? name)
                    .font(.title).bold()

                metaChips

                if let overview = displayTitle?.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                }

                watchlistButton

                if let callout = nextCallout {
                    calloutView(callout)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var metaChips: some View {
        HStack(spacing: 6) {
            Chip(text: mediaType == .tv ? "TV Show" : "Movie")
            if let status = displayTitle?.tvStatus, !status.isEmpty {
                Chip(text: status)
            }
            if let year = yearText {
                Chip(text: year)
            }
        }
    }

    private var watchlistButton: some View {
        Group {
            if isTracked {
                Button {
                    appState.removeFromLibrary(titleID)
                } label: {
                    Label("Remove from Watchlist", systemImage: "minus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    if let t = displayTitle {
                        appState.addToLibrary(t)
                        Task { await appState.refreshTitle(titleID) }  // pull episodes/releases right after adding
                    }
                } label: {
                    Label("Add to Watchlist", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .disabled(displayTitle == nil)
    }

    private func calloutView(_ callout: Callout) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(callout.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(callout.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.15)))
    }

    // MARK: - Episodes

    @ViewBuilder
    private func tvEpisodeList(for title: Title) -> some View {
        let seasons = title.seasons.filter { $0.seasonNumber > 0 }.map(\.seasonNumber).sorted()
        if seasons.isEmpty {
            Text("No seasons listed").foregroundStyle(.secondary)
        } else {
            sectionHeader("Episodes")
            Picker("Season", selection: Binding(
                get: { selectedSeason ?? seasons.first },
                set: { selectedSeason = $0 }
            )) {
                ForEach(seasons, id: \.self) { season in
                    Text("Season \(season)").tag(season)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            let episodes = (appState.library.episodes[titleID] ?? [])
                .filter { $0.seasonNumber == (selectedSeason ?? seasons.first) }
                .sorted { $0.episodeNumber < $1.episodeNumber }
            ForEach(episodes) { episode in
                EpisodeRowView(episode: episode)
            }
        }
    }

    // MARK: - Movie releases

    private var movieReleaseList: some View {
        let releases = (appState.library.movieReleases[titleID] ?? [])
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        return Group {
            if releases.isEmpty {
                Text("No release dates listed").foregroundStyle(.secondary)
            } else {
                sectionHeader("Releases")
                ForEach(releases) { release in
                    HStack {
                        Image(systemName: "film")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(release.kind.label).fontWeight(.medium)
                            Text(release.region).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(releaseDateLabel(release))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Cast

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Starring")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(cast.prefix(20), id: \.id) { member in
                        CastMemberView(member: member)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var yearText: String? {
        guard let date = displayTitle?.firstAirDate else { return nil }
        return Self.yearFormatter.string(from: date)
    }

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()

    private struct Callout {
        let title: String
        let detail: String
    }

    /// Next thing happening for this title, if any — drives the highlighted countdown callout.
    private var nextCallout: Callout? {
        if mediaType == .tv {
            guard let episode = appState.library.nextEpisode(forTitle: titleID) else { return nil }
            let detail = episode.airDate.map { "\(Self.relativeLabel($0)) · \(EpisodeRowView.dayFormatter.string(from: $0))" } ?? "Air date TBD"
            return Callout(title: "S\(episode.seasonNumber)E\(episode.episodeNumber) · \(episode.name)", detail: detail)
        } else {
            guard let release = (appState.library.movieReleases[titleID] ?? [])
                .filter({ ($0.date ?? .distantPast) >= .now })
                .min(by: { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }),
                  let date = release.date else { return nil }
            // Only promise a time when the source actually has one.
            let detail = release.hasTime
                ? "\(Self.relativeLabel(date)) · \(releaseDateLabel(release))"
                : "\(Self.relativeLabel(date)) · \(releaseDateLabel(release)) (no time announced)"
            return Callout(title: "\(release.kind.label) release", detail: detail)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static func relativeLabel(_ date: Date) -> String {
        let now = Date.now
        if date <= now { return "Out now" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
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
