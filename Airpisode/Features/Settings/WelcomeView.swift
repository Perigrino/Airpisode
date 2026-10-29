import SwiftUI

/// First-run onboarding: explains what Airpisode is, then asks for the user's own TMDB key.
/// Shown as a sheet only when no key is saved, so returning users are never asked again.
struct WelcomeView: View {
    /// Called once a key is saved.
    var onDone: () -> Void
    /// Called when the user chooses to continue without a key.
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            VStack(spacing: Theme.Space.m) {
                AppLogo(size: 84)
                VStack(spacing: Theme.Space.xs) {
                    Text("Airpisode")
                        .font(.title2.weight(.bold))
                    Text("Never miss what's next.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Airpisode tracks when your shows and movies come out and notifies you before they drop. It reads its metadata from TMDB, so it needs your own free API key.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Get a key in three steps")
                    .font(.headline)
                TMDBKeyHelp()
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground(cornerRadius: Theme.Radius.l))

            APIKeyForm(onSave: onDone)

            HStack {
                Button("Skip for Now", action: onSkip)
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
        .padding(Theme.Space.xxl)
        .frame(width: 480)
        .screenBackground()
    }
}
