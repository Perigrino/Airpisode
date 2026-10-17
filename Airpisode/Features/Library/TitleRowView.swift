import SwiftUI

/// Plain row content (no background/padding of its own) — the hosting card supplies those.
struct TitleRowView: View {
    let title: Title
    let nextLabel: String?
    var isExpanded = false

    var body: some View {
        HStack(spacing: 14) {
            PosterImage(path: title.posterPath, width: 76, height: 114, cornerRadius: 10)

            VStack(alignment: .leading, spacing: 6) {
                Text(title.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                Chip(text: title.mediaType == .tv ? "TV Show" : "Movie")
                if let nextLabel {
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                        Text(nextLabel)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .animation(Motion.quick, value: isExpanded)
        }
        .padding(12)
        .contentShape(Rectangle())
    }
}
