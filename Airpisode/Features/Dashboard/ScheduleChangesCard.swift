import SwiftUI

/// Small "what changed" card shown after a refresh finds a moved or newly announced release.
/// The detail lives here; the banner is only a nudge to open To Watch.
struct ScheduleChangesCard: View {
    @EnvironmentObject private var appState: AppState
    let records: [ScheduleChangeRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(records.count == 1 ? "Release change" : "\(records.count) release changes",
                      systemImage: "calendar.badge.exclamationmark")
                    .font(.headline)
                Spacer()
                Button("Mark read") { appState.markScheduleChangesRead() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }

            ForEach(records.prefix(3)) { record in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(record.titleName)
                        .font(.callout)
                        .fontWeight(.medium)
                    Text(record.label)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(dateText(record))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if records.count > 3 {
                Text("+\(records.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.chip))
        .appear()
    }

    private func dateText(_ record: ScheduleChangeRecord) -> String {
        let newDate = record.newDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "TBA"
        switch record.kind {
        case .dateChanged:
            let old = record.oldDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "TBA"
            return "\(old) → \(newDate)"
        case .newRelease:
            return newDate
        }
    }
}
