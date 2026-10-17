import SwiftUI

/// First-run onboarding: explains what Airpisode is, then asks for the user's own TMDB key.
/// Shown as a sheet only when no key is saved, so returning users are never asked again.
struct WelcomeView: View {
    /// Called once a key is saved.
    var onDone: () -> Void
    /// Called when the user chooses to continue without a key.
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                AppLogo(size: 84)
                VStack(spacing: 4) {
                    Text("Airpisode")
                        .font(.system(size: 24, weight: .bold))
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

            VStack(alignment: .leading, spacing: 12) {
                Text("Get a key in three steps")
                    .font(.headline)
                TMDBKeyHelp()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground(cornerRadius: 14))

            APIKeyForm(onSave: onDone)

            Button("Skip for now", action: onSkip)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 460)
        .screenBackground()
    }
}
