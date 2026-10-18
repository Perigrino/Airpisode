import SwiftUI

/// Small inline popover shown when a cast member is tapped: basic person data
/// fetched live from TMDB (`/person/{id}`), styled like the app's dark cards.
struct PersonPopoverView: View {
    let member: TMDBCastMember
    let appState: AppState

    @State private var person: TMDBPersonDetail?
    @State private var finishedLoading = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            portrait
            VStack(alignment: .leading, spacing: 6) {
                Text(member.name)
                    .font(.headline)
                if let character = member.character, !character.isEmpty {
                    Text(character)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let person {
                    if let department = person.knownForDepartment {
                        Chip(text: department)
                    }
                    if let life = lifeLine(person) {
                        Text(life)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let bio = person.biography {
                        Text(shortened(bio))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                } else if finishedLoading {
                    Text("Couldn't load details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(width: 330, height: 330, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.background)
        )
        .task {
            person = await appState.fetchPerson(tmdbID: member.id)
            finishedLoading = true
        }
    }

    private var portrait: some View {
        AsyncImage(url: ImageURL.poster(person?.profilePath ?? member.profilePath, size: "w185")) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.gray.opacity(0.2)
        }
        .frame(width: 100, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// "Born July 12, 1942 in Chicago, Illinois, USA" (+ "Died …" when applicable).
    private func lifeLine(_ p: TMDBPersonDetail) -> String? {
        var parts: [String] = []
        if let birthday = p.birthday {
            parts.append("Born \(Self.usDateText(birthday))")
        }
        if let place = p.placeOfBirth {
            parts.append(parts.isEmpty ? "From \(place)" : " in \(place)")
        }
        if let deathday = p.deathday {
            parts.append("· Died \(Self.usDateText(deathday))")
        }
        return parts.isEmpty ? nil : parts.joined()
    }

    private func shortened(_ bio: String) -> String {
        let lines = bio.components(separatedBy: " \n")
            .flatMap { $0.components(separatedBy: "\n") }
            .filter { !$0.isEmpty }
        let prefix = lines.prefix(4).joined(separator: " ")
        return prefix.count < bio.count ? prefix + " …" : prefix
    }

    private static let inputFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let outputFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
    private static func usDateText(_ ymd: String) -> String {
        guard let date = inputFormatter.date(from: ymd) else { return ymd }
        return outputFormatter.string(from: date)
    }
}
