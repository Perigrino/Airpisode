import SwiftUI

/// "Where to watch" — TMDB's JustWatch-sourced streaming offers for one country.
/// Rendered as a compact catalog card consistent with the rest of the app; the detail page
/// fetches the data lazily (same shape as cast and trailers) and shows this section once
/// the fetch has finished.
struct WhereToWatchSection: View {
    let providers: TMDBRegionProviders?
    let region: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where to watch · \(region)")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            if let providers {
                offerRow("Stream", providers.flatrate)
                offerRow("Rent", providers.rent)
                offerRow("Buy", providers.buy)
                attribution(providers.link)
            } else {
                emptyCard
            }
        }
    }

    /// TMDB has no offer for this region yet — styled like the season placeholder card.
    private var emptyCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "tv")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Not available in \(region) yet")
                    .font(.callout)
                    .fontWeight(.medium)
                Text("Streaming offers will appear here once TMDB lists them for this country.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.chip))
    }

    @ViewBuilder
    private func offerRow(_ label: String, _ list: [TMDBWatchProvider]?) -> some View {
        if let list, !list.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                ForEach(list) { provider in
                    VStack(spacing: 4) {
                        AsyncImage(url: ImageURL.poster(provider.logoPath, size: "w45")) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.white.opacity(0.08)
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Text(provider.name)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 56)
                    }
                    .padding(.vertical, 2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// The provider listing is licensed from JustWatch, so the attribution and its link are
    /// required by TMDB's terms whenever this section shows.
    private func attribution(_ link: String?) -> some View {
        let target = link.flatMap { URL(string: $0) } ?? URL(string: "https://www.themoviedb.org")!
        return Link(destination: target) {
            Text("Powered by JustWatch")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}
