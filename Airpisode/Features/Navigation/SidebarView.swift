import SwiftUI

/// Persistent navigation. Everything the dock used to hide lives here, with counts and a
/// quiet status line at the bottom so refresh state is never a mystery.
struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selection: AppSection?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                row(.dashboard)
                row(.shows, count: showCount)
                row(.movies, count: movieCount)
                row(.diary)
            }

            Section {
                row(.discover)
            } footer: {
                Text("Search TMDB and add shows or movies.")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Airpisode")
        .safeAreaInset(edge: .bottom, spacing: 0) { statusFooter }
    }

    private var showCount: Int {
        appState.library.entries.filter { $0.mediaType == .tv }.count
    }

    private var movieCount: Int {
        appState.library.entries.filter { $0.mediaType == .movie }.count
    }

    private func row(_ section: AppSection, count: Int? = nil) -> some View {
        Label {
            HStack(spacing: Theme.Space.s) {
                Text(section.label)
                Spacer(minLength: 0)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        } icon: {
            Image(systemName: section.icon)
        }
        .tag(section)
        .accessibilityLabel(count.map { "\(section.label), \($0)" } ?? section.label)
    }

    private var statusFooter: some View {
        HStack(spacing: 6) {
            if appState.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                Text("Refreshing releases…")
            } else if appState.lastRefreshError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Refresh needs attention")
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.tertiary)
                Text(DateText.freshness(appState.lastRefreshAt))
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
