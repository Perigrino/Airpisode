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
        Group {
            if items.isEmpty {
                Text("Add your first show in Discover")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    section("Today", today)
                    section("This Week", thisWeek)
                    section("Later", later)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Dashboard")
    }

    @ViewBuilder
    private func section(_ name: String, _ items: [UpcomingItem]) -> some View {
        if !items.isEmpty {
            Section(name) {
                ForEach(items) { item in
                    DashboardRowView(item: item)
                }
            }
        }
    }
}
