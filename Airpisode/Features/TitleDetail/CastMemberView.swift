import SwiftUI

struct CastMemberView: View {
    let member: TMDBCastMember

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            AsyncImage(url: ImageURL.poster(member.profilePath, size: "w185")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Theme.posterPlaceholder
            }
            .frame(width: 84, height: 126)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))

            Text(member.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            if let character = member.character, !character.isEmpty {
                Text(character)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 84)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
