import SwiftUI

struct TitleRowView: View {
    let title: Title
    let nextLabel: String?

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: ImageURL.poster(title.posterPath, size: "w185")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 66, height: 99)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(title.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                if let nextLabel {
                    Text(nextLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
