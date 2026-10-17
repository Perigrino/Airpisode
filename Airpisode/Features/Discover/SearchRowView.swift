import SwiftUI

/// Plain row content (no background) — the hosting card supplies the surface.
struct SearchRowView: View {
    let result: TMDBSearchResult
    var isExpanded = false
    var isTracked = false

    var body: some View {
        HStack(spacing: 14) {
            PosterImage(path: result.posterPath, width: 60, height: 90, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 5) {
                Text(result.displayName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Chip(text: result.mediaType == "tv" ? "TV Show" : "Movie")
                    if !year.isEmpty {
                        Text(year)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            if isTracked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
            }

            Image(systemName: "chevron.down")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .animation(Motion.quick, value: isExpanded)
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    private var year: String {
        String((result.firstAirDate ?? result.releaseDate ?? "").prefix(4))
    }
}
