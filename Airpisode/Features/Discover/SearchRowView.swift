import SwiftUI

struct SearchRowView: View {
    let result: TMDBSearchResult

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: ImageURL.poster(result.posterPath)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 40, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.displayName)
                    .fontWeight(.medium)
                Text(year)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(result.mediaType == "tv" ? "TV" : "Movie")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
        }
        .padding(.vertical, 2)
    }

    private var year: String {
        String((result.firstAirDate ?? result.releaseDate ?? "").prefix(4))
    }
}
