import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    private var items: [UpcomingItem] { appState.library.upcomingReleases() }

    private var today: [UpcomingItem] { items.filter { ($0.date ?? .distantPast) < Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400) && $0.date != nil } }
    private var thisWeek: [UpcomingItem] { items.filter { item in
        guard let date = item.date else { return false }
        let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
        return date >= start && date < start.addingTimeInterval(6 * 86_400)
    } }
    private var later: [UpcomingItem] { items.filter { item in
        guard let date = item.date else { return true }
        let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(7 * 86_400)
        return date >= start
    } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let error = appState.lastRefreshError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
                }

                PageHeader(title: "Upcoming",
                           subtitle: "Don't miss out on these upcoming releases")

                if items.isEmpty {
                    emptyState
                } else {
                    section("Today", today)
                    section("This Week", thisWeek)
                    section("Later", later)
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .screenBackground()
        .navigationTitle("Upcoming")
        .toolbar {
            Button {
                Task { await appState.runFullRefresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh release dates")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Nothing on the calendar yet")
                .font(.headline)
            Text("Track a show or movie and its next release shows up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                appState.selectedSection = .discover
            } label: {
                Label("Find something to track", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    @ViewBuilder
    private func section(_ name: String, _ items: [UpcomingItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(name)
                    .font(.title3)
                    .fontWeight(.semibold)
                ForEach(items) { item in
                    DashboardRowView(item: item)
                }
            }
        }
    }
}
