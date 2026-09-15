import SwiftUI

/// Operation history backed entirely by `mo history --json`.
struct HistorySheet: View {
    @State private var report: HistoryReport?
    @State private var loading = true
    @State private var error: MoleUserError?
    @Environment(\.dismiss) private var dismiss

    private let client = MoleClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Operation History")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(MoleTheme.textPrimary)
                Text("from mo history --json")
                    .font(.system(size: 11))
                    .foregroundStyle(MoleTheme.textTertiary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            if loading {
                Spacer()
                ProgressView("Loading Mole history…")
                Spacer()
            } else if let error {
                ErrorStateView(error: error) { load() }
                Spacer()
            } else if let report {
                if let operations = report.logs?.operations {
                    Text(operations)
                        .font(MoleTheme.mono)
                        .foregroundStyle(MoleTheme.textTertiary)
                }

                SectionLabel(text: "Sessions")
                if report.sessions?.isEmpty != false {
                    Text("No Mole operations recorded yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(MoleTheme.textTertiary)
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
        .background(MoleTheme.panel)
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
            } catch MoleClient.MoleClientError.cliNotFound {
                error = MoleUserError(kind: .cliMissing)
                loading = false
            } catch {
                self.error = MoleUserError(kind: .generic(String(describing: error)))
                loading = false
            }
        }
    }

    private func deletionRow(_ deletion: HistoryDeletion) -> some View {
        HStack(alignment: .top) {
            Text(deletion.timestamp ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MoleTheme.textTertiary)
                .frame(width: 130, alignment: .leading)
            Text(deletion.mode ?? "")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(deletion.status == "FAILED" ? MoleTheme.danger : MoleTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            Text(deletion.path ?? "")
                .font(MoleTheme.mono)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(MoleTheme.textSecondary)
            Spacer()
            if let kb = deletion.sizeKb, let size = kb {
                Text(bytesText(Int64(size) * 1024))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(MoleTheme.textTertiary)
            }
        }
    }
}

struct HistorySessionRow: View {
    let session: HistorySession

    var body: some View {
        MoleCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text((session.command ?? "command").capitalized)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MoleTheme.textPrimary)
                        if let failed = session.failedTasks, failed > 0 {
                            Text("\(failed) failed")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(MoleTheme.danger.opacity(0.16)))
                                .foregroundStyle(MoleTheme.danger)
                        }
                    }
                    Text("\(session.startedAt ?? "") → \(session.endedAt ?? "")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MoleTheme.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(session.size ?? "—")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(MoleTheme.accent)
                    Text("\(session.items ?? 0) items")
                        .font(.system(size: 10))
                        .foregroundStyle(MoleTheme.textSecondary)
                }
                if let actions = session.actions {
                    VStack(alignment: .trailing, spacing: 1) {
                        actionText("removed", actions.removed, MoleTheme.healthy)
                        actionText("trashed", actions.trashed, MoleTheme.infoBlue)
                        actionText("skipped", actions.skipped, MoleTheme.caution)
                        if let failed = actions.failed, failed > 0 {
                            actionText("failed", failed, MoleTheme.danger)
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
            .foregroundStyle((count ?? 0) > 0 ? color : MoleTheme.textTertiary)
    }
}


