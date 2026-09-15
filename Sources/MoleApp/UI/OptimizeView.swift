import SwiftUI

struct OptimizeView: View {
    @ObservedObject var viewModel: OptimizeViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch viewModel.phase {
                case .idle:
                    OptimizeIdleView(viewModel: viewModel)
                case .previewing:
                    OptimizeWorkingView(title: "Reading task list",
                                        message: "Expanding mo optimize --dry-run to see exactly what will run")
                case .previewed:
                    OptimizePreviewView(viewModel: viewModel)
                case .running:
                    OptimizeRunningView(viewModel: viewModel)
                case .complete:
                    OptimizeCompleteView(viewModel: viewModel)
                case .failed(let reason):
                    ErrorStateView(
                        error: viewModel.lastError ?? MoleUserError(kind: .generic(reason))) {
                        viewModel.reset()
                    }
                    .padding(.top, 80)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [MoleTheme.warmPanel, MoleTheme.background],
                startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
        .accessibilityLabel("Optimize")
    }
}

struct OptimizeIdleView: View {
    @ObservedObject var viewModel: OptimizeViewModel

    var body: some View {
        VStack(spacing: 26) {
            OptimizeVisual(isRunning: false)
                .frame(width: 190, height: 190)
                .padding(.top, 30)

            Text("Deep-optimize your system")
                .font(MoleTheme.metric(30))
                .foregroundStyle(MoleTheme.textPrimary)

            Text("Refresh caches, databases, and macOS services through Mole's bounded maintenance pass. Unnecessary or unsafe tasks are skipped with a reason.")
                .font(.system(size: 13))
                .foregroundStyle(MoleTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            Button {
                viewModel.requestOptimize()
            } label: {
                Text("Preview Optimization")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(MoleTheme.accent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Shows the full task list via mo optimize --dry-run before running anything")

            Text("Nothing changes until you run the pass after previewing.")
                .font(.system(size: 12))
                .foregroundStyle(MoleTheme.textTertiary)
                .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity)
    }
}

struct OptimizePreviewView: View {
    @ObservedObject var viewModel: OptimizeViewModel

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Optimization plan")
                        .font(MoleTheme.metric(26))
                        .foregroundStyle(MoleTheme.textPrimary)
                    Text("Preview from mo optimize --dry-run · no changes made yet")
                        .font(.system(size: 12))
                        .foregroundStyle(MoleTheme.textSecondary)
                }
                Spacer()
                if let system = viewModel.preview?.systemLine {
                    Text(system)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MoleTheme.textTertiary)
                }
            }
            .padding(.top, 20)

            MoleCard {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.orderedTasks) { task in
                        OptimizeTaskRow(task: task, isRunning: false)
                    }
                }
            }

            HStack {
                Button("Back") { viewModel.reset() }
                    .buttonStyle(.bordered)
                Spacer()
                Button {
                    viewModel.performOptimize()
                } label: {
                    Text("Run \(viewModel.orderedTasks.count) Optimizations")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(MoleTheme.accent))
                        .foregroundStyle(.black.opacity(0.85))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Runs mo optimize; sudo-requiring tasks are skipped cleanly if admin access is not granted")
            }
            .padding(.bottom, 30)
        }
    }
}

struct OptimizeRunningView: View {
    @ObservedObject var viewModel: OptimizeViewModel

    var body: some View {
        VStack(spacing: 26) {
            OptimizeVisual(isRunning: true)
                .frame(width: 180, height: 180)
                .padding(.top, 40)

            Text("Deep-optimizing your system")
                .font(MoleTheme.metric(30))
                .foregroundStyle(MoleTheme.textPrimary)

            Text("Mole is applying bounded maintenance. Tasks that are unsafe right now are skipped with a reason.")
                .font(.system(size: 13))
                .foregroundStyle(MoleTheme.textSecondary)

            MoleCard {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.orderedTasks) { task in
                        OptimizeTaskRow(
                            task: task,
                            isRunning: false,
                            isDone: viewModel.completedTaskNames.contains(task.name) || viewModel.result != nil)
                    }
                }
            }
            .padding(.bottom, 30)
        }
    }
}

struct OptimizeCompleteView: View {
    @ObservedObject var viewModel: OptimizeViewModel

    private var summary: OptimizeSummary? { viewModel.result ?? viewModel.preview }

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(MoleTheme.healthy.opacity(0.12))
                    .frame(width: 130, height: 130)
                Image(systemName: "checkmark")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(MoleTheme.healthy)
            }
            .padding(.top, 40)
            .accessibilityHidden(true)

            Text(viewModel.result?.cancelled == true ? "Optimization Cancelled" : "Optimization Complete")
                .font(MoleTheme.metric(30))

            let applied = viewModel.result?.appliedCount ?? 0
            Text("\(applied) applied")
                .font(MoleTheme.metric(44))
                .foregroundStyle(MoleTheme.healthy)

            HStack(spacing: 14) {
                outcomeBadge("unchanged", viewModel.result?.unchangedCount ?? 0, MoleTheme.textSecondary)
                outcomeBadge("skipped", viewModel.result?.skippedCount ?? 0, MoleTheme.caution)
                outcomeBadge("unavailable", viewModel.result?.unavailableCount ?? 0, MoleTheme.textTertiary)
                if let failed = viewModel.result?.failedCount, failed > 0 {
                    outcomeBadge("failed", failed, MoleTheme.danger)
                }
            }
            .accessibilityElement(children: .combine)

            MoleCard {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.orderedTasks) { task in
                        OptimizeTaskRow(task: task, isRunning: false, isDone: true)
                    }
                }
            }

            Button("Done") { viewModel.reset() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(MoleTheme.accent)
                .padding(.bottom, 36)
        }
    }

    private func outcomeBadge(_ label: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Text("\(count)").font(.system(size: 14, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 12))
        }
        .foregroundStyle(count > 0 ? color : MoleTheme.textTertiary)
    }
}

struct OptimizeTaskRow: View {
    let task: OptimizeTask
    var isRunning: Bool
    var isDone: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    private var icon: (String, Color) {
        switch task.outcome {
        case .applied: return ("checkmark.circle.fill", MoleTheme.healthy)
        case .unchanged: return ("minus.circle", MoleTheme.textTertiary)
        case .skipped: return ("arrow.uturn.left.circle", MoleTheme.caution)
        case .unavailable: return ("slash.circle", MoleTheme.textTertiary)
        case .attention: return ("exclamationmark.triangle.fill", MoleTheme.caution)
        case .failed: return ("xmark.octagon.fill", MoleTheme.danger)
        case .pending:
            return (isDone ? "checkmark.circle.fill" : (isRunning ? "circle.dotted" : "circle.dashed"),
                    isDone ? MoleTheme.healthy : MoleTheme.textTertiary)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            let (symbol, tint) = icon
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(
                    isRunning && task.outcome == .pending && !reduceMotion
                        ? .linear(duration: 1.2).repeatForever(autoreverses: false)
                        : .default,
                    value: spin)
                .onAppear { spin = true }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MoleTheme.textPrimary)
                if let detail = task.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(MoleTheme.textSecondary)
                }
                if case .skipped(let reason) = task.outcome, let reason {
                    Text("Skipped: \(reason)")
                        .font(.system(size: 11))
                        .foregroundStyle(MoleTheme.caution)
                }
                if case .unavailable(let reason) = task.outcome, let reason {
                    Text("Unavailable: \(reason)")
                        .font(.system(size: 11))
                        .foregroundStyle(MoleTheme.textTertiary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.name): \(accessibilityOutcome)")
    }

    private var accessibilityOutcome: String {
        switch task.outcome {
        case .applied: return "completed"
        case .unchanged: return "no change needed"
        case .skipped: return "skipped"
        case .unavailable: return "unavailable"
        case .attention: return "needs attention"
        case .failed: return "failed"
        case .pending: return isDone ? "completed" : "waiting"
        }
    }
}

/// Central Optimize visual: concentric system rings that rotate slowly while running.
struct OptimizeVisual: View {
    var isRunning: Bool
    @State private var rotating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<3) { ring in
                Circle()
                    .strokeBorder(
                        MoleTheme.accent.opacity(0.35 - Double(ring) * 0.1),
                        lineWidth: 1.5)
                    .frame(width: 170 - CGFloat(ring * 36), height: 170 - CGFloat(ring * 36))
                    .rotationEffect(.degrees(rotating ? 360 : 0))
                    .animation(
                        isRunning && !reduceMotion
                            ? .linear(duration: Double(6 + ring * 3)).repeatForever(autoreverses: false)
                            : .default,
                        value: rotating)
            }
            VStack(spacing: 10) {
                MoleSilhouette(color: MoleTheme.accent)
                    .frame(width: 76, height: 52)
                Text(isRunning ? "MAINTAINING" : "READY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(MoleTheme.textTertiary)
            }
        }
        .onAppear { rotating = true }
        .accessibilityHidden(true)
    }
}

struct OptimizeWorkingView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            OptimizeVisual(isRunning: true)
                .frame(width: 160, height: 160)
                .padding(.top, 70)
            Text(title)
                .font(MoleTheme.metric(26))
                .foregroundStyle(MoleTheme.textPrimary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(MoleTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
