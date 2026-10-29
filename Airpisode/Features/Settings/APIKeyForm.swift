import AppKit
import SwiftUI

/// Prompts for the user's own TMDB API key. Shown on first launch and in Settings.
struct APIKeyForm: View {
    /// Called after a key is saved, so the caller can start using it right away.
    var onSave: () -> Void = {}

    @State private var key: String = Secrets.tmdbKey
    @State private var saved = false
    @State private var isEditing = false

    private var trimmed: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Label("API key", systemImage: "key.fill")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
                if saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        .transition(.opacity)
                }
            }

            HStack(spacing: Theme.Space.s) {
                KeyTextField(
                    text: $key,
                    isEditing: $isEditing,
                    placeholder: "Paste your TMDB API key",
                    onChange: { saved = false }
                )
                .padding(.horizontal, Theme.Space.s)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                        .fill(Theme.chip)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                        .strokeBorder(
                            isEditing ? Theme.accent : Theme.hairline,
                            lineWidth: isEditing ? 1.5 : 1
                        )
                )

                Button(action: save) {
                    Text("Save")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentFill)
                .disabled(trimmed.isEmpty || saved)
            }
        }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        Secrets.setTMDBKey(trimmed)
        withAnimation(Motion.quick) { saved = true }
        onSave()
    }
}

/// AppKit field so the key reads left-aligned like every other Mac text field, with no focus ring
/// fighting the custom chip around it.
private struct KeyTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    var placeholder: String
    var onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.placeholderString = placeholder
        field.alignment = .left
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: KeyTextField

        init(_ parent: KeyTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onChange()
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isEditing = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isEditing = false
        }
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
                    .foregroundStyle(Theme.accent)
            }
            .padding(.top, 2)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.onAccent)
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
