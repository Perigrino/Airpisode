import SwiftUI

struct SearchRowView: View {
    let result: TMDBSearchResult
    var isExpanded = false

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: ImageURL.poster(result.posterPath, size: "w185")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 60, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(result.displayName)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(year)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(result.mediaType == "tv" ? "TV" : "Movie")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))

            Image(systemName: "chevron.down")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .padding(.vertical, 4)
    }

    private var year: String {
        String((result.firstAirDate ?? result.releaseDate ?? "").prefix(4))
    }
}
