import SwiftUI

struct CastMemberView: View {
    let member: TMDBCastMember

    var body: some View {
        VStack(spacing: 6) {
            AsyncImage(url: ImageURL.poster(member.profilePath, size: "w185")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 90, height: 135)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(member.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
            if let character = member.character, !character.isEmpty {
                Text(character)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 90)
    }
}
