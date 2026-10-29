import SwiftUI

/// "Where to watch" — TMDB's JustWatch-sourced streaming offers for one country.
/// Rendered as a compact catalog card consistent with the rest of the app; the detail page
/// fetches the data lazily (same shape as cast and trailers) and shows this section once
/// the fetch has finished.
struct WhereToWatchSection: View {
    let providers: TMDBRegionProviders?
    let region: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Where to watch · \(region)")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let providers {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    offerRow("Stream", providers.flatrate)
                    offerRow("Rent", providers.rent)
                    offerRow("Buy", providers.buy)
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                        .fill(Theme.chip)
                )

                attribution(providers.link)
            } else {
                emptyCard
            }
        }
    }

    /// TMDB has no offer for this region yet — styled like the season placeholder card.
    private var emptyCard: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "tv")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Not available in \(region) yet")
                    .font(.callout.weight(.medium))
                Text("Streaming offers will appear here once TMDB lists them for this country.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .fill(Theme.chip)
        )
    }

    @ViewBuilder
    private func offerRow(_ label: String, _ list: [TMDBWatchProvider]?) -> some View {
        if let list, !list.isEmpty {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)

                ForEach(list) { provider in
                    VStack(spacing: Theme.Space.xs) {
                        AsyncImage(url: ImageURL.poster(provider.logoPath, size: "w45")) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Theme.chip
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))

                        Text(provider.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 64)
                    }
                    .accessibilityElement(children: .combine)
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
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
