import SwiftUI

/// Prompts for the user's own TMDB API key. Shown on first launch and in Settings.
struct APIKeyForm: View {
    /// Called after a key is saved, so the caller can start using it right away.
    var onSave: () -> Void = {}

    @State private var key: String = Secrets.tmdbKey

    private var trimmed: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Airpisode reads show and movie data from TMDB. Paste your own free API key to get started.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("TMDB API key", text: $key)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .disableAutocorrection(true)

            HStack {
                Link("Get a free key from TMDB", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                    .font(.caption)
                Spacer()
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(trimmed.isEmpty)
            }
        }
    }

    private func save() {
        Secrets.setTMDBKey(trimmed)
        onSave()
    }
}
