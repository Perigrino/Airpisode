import AppKit
import SwiftUI

/// Explains the notification pipeline in plain language: permission, scheduled count, the
/// next few requests, and the most common reasons a release has no alert.
struct NotificationDiagnosticsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var report: NotificationDiagnosticsReport?
    @State private var testSent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notification Diagnostics")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Why an alert exists — or why it does not.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if let report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(report.rows) { row in
                            rowView(row)
                        }

                        Divider()

                        Text("Next scheduled")
                            .font(.headline)
                        if report.pending.filter({ NotificationScheduler.isManagedID($0.id) }).isEmpty {
                            Text("Nothing queued.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(report.pending.filter { NotificationScheduler.isManagedID($0.id) }.prefix(8)) { alert in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "bell")
                                        .foregroundStyle(Theme.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(alert.title)
                                            .font(.callout)
                                            .lineLimit(1)
                                        Text(alert.body)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                        if let date = alert.fireDate {
                                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 300, maxHeight: 420)
            } else {
                ProgressView("Checking notification state…")
                    .frame(maxWidth: .infinity, minHeight: 160)
            }

            HStack {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Send Test Alert") {
                    Task {
                        await appState.sendTestAlert()
                        testSent = true
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        testSent = false
                    }
                }
                Spacer()
                Button("Refresh") { Task { await reload() } }
            }

            if testSent {
                Text("Test alert scheduled — it should appear in about 10 seconds.")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(20)
        .frame(width: 520, height: 560)
        .task { await reload() }
    }

    private func rowView(_ row: NotificationDiagnosticRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(row.severity == .warning ? Color.orange : Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func reload() async {
        report = await appState.notificationDiagnostics()
    }
}
