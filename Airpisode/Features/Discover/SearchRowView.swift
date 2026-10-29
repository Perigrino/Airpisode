import SwiftUI

/// Plain row content (no background) — the hosting card supplies the surface.
struct SearchRowView: View {
    let result: TMDBSearchResult
    var isExpanded = false
    var isTracked = false

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            PosterImage(path: result.posterPath, width: 52, height: 76, cornerRadius: Theme.Radius.s)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(result.displayName)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: Theme.Space.s) {
                    Chip(text: result.mediaType == "tv" ? "Show" : "Movie")
                    if !year.isEmpty {
                        Text(year)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let rating, rating > 0 {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
                if let overview, !overview.isEmpty {
                    Text(overview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 620, alignment: .leading)
                }
            }

            Spacer(minLength: 0)

            if isTracked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(Theme.accent)
                    .help("Already in your library")
                    .accessibilityLabel("Already in your library")
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(Motion.quick, value: isExpanded)
                .accessibilityHidden(true)
        }
        .padding(Theme.Space.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(isExpanded ? "Collapses details" : "Shows details")
    }

    private var year: String {
        String((result.firstAirDate ?? result.releaseDate ?? "").prefix(4))
    }

    private var overview: String? {
        result.overview?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rating: Double? {
        guard let voteCount = result.voteCount, voteCount >= 25 else { return nil }
        return result.voteAverage
    }
}
