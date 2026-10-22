import SwiftUI

/// Operation history backed entirely by `mo history --json`.
struct HistorySheet: View {
    @State private var report: HistoryReport?
    @State private var loading = true
    @State private var error: SparkCleanUserError?
    @Environment(\.dismiss) private var dismiss

    private let client = SparkCleanClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Operation History")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(SparkCleanTheme.textPrimary)
                Text("from mo history --json")
                    .font(.system(size: 11))
                    .foregroundStyle(SparkCleanTheme.textTertiary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            if loading {
                Spacer()
                ProgressView("Loading SparkClean history…")
                Spacer()
            } else if let error {
                ErrorStateView(error: error) { load() }
                Spacer()
            } else if let report {
                if let operations = report.logs?.operations {
                    Text(operations)
                        .font(SparkCleanTheme.mono)
                        .foregroundStyle(SparkCleanTheme.textTertiary)
                }

                SectionLabel(text: "Sessions")
                if report.sessions?.isEmpty != false {
                    Text("No SparkClean operations recorded yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(SparkCleanTheme.textTertiary)
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array((report.sessions ?? []).enumerated()), id: \.offset) { _, session in
                            HistorySessionRow(session: session)
                        }
                    }
                }

                SectionLabel(text: "Recent deletions")
                ScrollView {
                    let deletions = Array((report.deletions ?? []).prefix(60))
                    VStack(spacing: 4) {
                        ForEach(Array(deletions.enumerated()), id: \.offset) { pair in
                            deletionRow(pair.element)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 720, height: 560)
        .background(SparkCleanTheme.panel)
        .onAppear { load() }
        .accessibilityLabel("Operation history")
    }

    private func load() {
        loading = true
        error = nil
        Task {
            do {
                report = try await client.history(limit: 50)
                loading = false
            } catch SparkCleanClient.SparkCleanClientError.cliNotFound {
                error = SparkCleanUserError(kind: .cliMissing)
                loading = false
            } catch {
                self.error = SparkCleanUserError(kind: .generic(String(describing: error)))
                loading = false
            }
        }
    }

    private func deletionRow(_ deletion: HistoryDeletion) -> some View {
        HStack(alignment: .top) {
            Text(deletion.timestamp ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SparkCleanTheme.textTertiary)
                .frame(width: 130, alignment: .leading)
            Text(deletion.mode ?? "")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(deletion.status == "FAILED" ? SparkCleanTheme.danger : SparkCleanTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            Text(deletion.path ?? "")
                .font(SparkCleanTheme.mono)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(SparkCleanTheme.textSecondary)
            Spacer()
            if let kb = deletion.sizeKb, let size = kb {
                Text(bytesText(Int64(size) * 1024))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(SparkCleanTheme.textTertiary)
            }
        }
    }
}

struct HistorySessionRow: View {
    let session: HistorySession

    var body: some View {
        SparkCleanCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text((session.command ?? "command").capitalized)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SparkCleanTheme.textPrimary)
                        if let failed = session.failedTasks, failed > 0 {
                            Text("\(failed) failed")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(SparkCleanTheme.danger.opacity(0.16)))
                                .foregroundStyle(SparkCleanTheme.danger)
                        }
                    }
                    Text("\(session.startedAt ?? "") → \(session.endedAt ?? "")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SparkCleanTheme.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(session.size ?? "—")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(SparkCleanTheme.accent)
                    Text("\(session.items ?? 0) items")
                        .font(.system(size: 10))
                        .foregroundStyle(SparkCleanTheme.textSecondary)
                }
                if let actions = session.actions {
                    VStack(alignment: .trailing, spacing: 1) {
                        actionText("removed", actions.removed, SparkCleanTheme.healthy)
                        actionText("trashed", actions.trashed, SparkCleanTheme.infoBlue)
                        actionText("skipped", actions.skipped, SparkCleanTheme.caution)
                        if let failed = actions.failed, failed > 0 {
                            actionText("failed", failed, SparkCleanTheme.danger)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func actionText(_ label: String, _ count: Int?, _ color: Color) -> some View {
        Text("\(count ?? 0) \(label)")
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle((count ?? 0) > 0 ? color : SparkCleanTheme.textTertiary)
    }
}


