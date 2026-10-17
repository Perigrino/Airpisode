import SwiftUI

/// Prompts for the user's own TMDB API key. Shown on first launch and in Settings.
struct APIKeyForm: View {
    /// Called after a key is saved, so the caller can start using it right away.
    var onSave: () -> Void = {}

    @State private var key: String = Secrets.tmdbKey
    @State private var saved = false

    private var trimmed: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Paste your TMDB API key", text: $key)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .disableAutocorrection(true)
                    .onSubmit(save)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.chip)
            )

            Button(action: save) {
                Label(saved ? "Saved" : "Save",
                      systemImage: saved ? "checkmark" : "arrow.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(trimmed.isEmpty)
        }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        Secrets.setTMDBKey(trimmed)
        withAnimation(Motion.quick) { saved = true }
        onSave()
    }
}

/// The "get a key" instructions, shared by onboarding and Settings.
struct TMDBKeyHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            step(1, "Create a free account at themoviedb.org")
            step(2, "Open Settings → API and copy the API key")
            step(3, "Paste it here and save")

            Link(destination: URL(string: "https://www.themoviedb.org/settings/api")!) {
                Label("Open TMDB API settings", systemImage: "arrow.up.right.square")
                    .font(.callout)
            }
            .padding(.top, 2)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption2).bold()
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.gradient))
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
