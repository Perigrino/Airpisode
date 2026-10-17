import SwiftUI

/// Plain row content (no background) — the hosting card supplies the surface.
struct SearchRowView: View {
    let result: TMDBSearchResult
    var isExpanded = false
    var isTracked = false

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: ImageURL.poster(result.posterPath, size: "w185")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Theme.posterPlaceholder
            }
            .frame(width: 60, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    private var year: String {
        String((result.firstAirDate ?? result.releaseDate ?? "").prefix(4))
    }
}
