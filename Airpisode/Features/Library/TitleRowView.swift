import SwiftUI

struct TitleRowView: View {
    let title: Title
    let nextLabel: String?

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: ImageURL.poster(title.posterPath)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 40, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(title.name)
                    .fontWeight(.medium)
                if let nextLabel {
                    Text(nextLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
