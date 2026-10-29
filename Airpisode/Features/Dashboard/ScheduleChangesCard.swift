import SwiftUI

/// Small "what changed" card shown after a refresh finds a moved or newly announced release.
/// The detail lives here; the banner is only a nudge to open To Watch.
struct ScheduleChangesCard: View {
    @EnvironmentObject private var appState: AppState
    let records: [ScheduleChangeRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Label(
                    records.count == 1 ? "Release change" : "\(records.count) release changes",
                    systemImage: "calendar.badge.exclamationmark"
                )
                .font(.headline)

                Spacer()

                Button("Mark Read") { appState.markScheduleChangesRead() }
                    .controlSize(.small)
                    .help("Dismiss these change notices")
            }

            VStack(spacing: 0) {
                ForEach(records.prefix(3)) { record in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(record.titleName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(record.label)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(dateText(record))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 5)
                    .accessibilityElement(children: .combine)

                    if record.id != records.prefix(3).last?.id {
                        Divider()
                    }
                }
            }

            if records.count > 3 {
                Text("\(records.count - 3) more in the original notice")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground(cornerRadius: Theme.Radius.l))
        .appear()
    }

    private func dateText(_ record: ScheduleChangeRecord) -> String {
        let newDate = record.newDate.map { DateText.upcoming($0, includeTime: true) } ?? "TBA"
        switch record.kind {
        case .dateChanged:
            let old = record.oldDate.map { DateText.airing($0) } ?? "TBA"
            return "\(old) → \(newDate)"
        case .newRelease:
            return newDate
        }
    }
}
