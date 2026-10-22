import SwiftUI

struct CleanView: View {
    @ObservedObject var viewModel: CleanViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch viewModel.phase {
                case .idle:
                    CleanIdleView(viewModel: viewModel)
                case .scanning:
                    CleanScanningView(viewModel: viewModel)
                case .results:
                    CleanResultsView(viewModel: viewModel)
                case .cleaning:
                    CleanScanningView(viewModel: viewModel, isCleaning: true)
                case .complete:
                    CleanCompleteView(viewModel: viewModel)
                case .failed(let reason):
                    CleanFailedView(viewModel: viewModel, reason: reason)
                }
            }
            // Separate node from the confirmation sheet below: SwiftUI only
            // reliably presents one sheet per view node.
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [SparkCleanTheme.warmPanel, SparkCleanTheme.background],
                startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
        .accessibilityLabel("Clean dashboard")
        .sheet(isPresented: $viewModel.showConfirmation) {
            CleanConfirmationSheet(viewModel: viewModel)
        }
    }
}

// MARK: - Idle hero

struct CleanIdleView: View {
    @ObservedObject var viewModel: CleanViewModel

    var body: some View {
        VStack(spacing: 28) {
            SparkCleanOrb()
                .frame(width: 220, height: 220)
                .padding(.top, 30)

            Text(bytesText(viewModel.reclaimableBytes))
                .font(SparkCleanTheme.metric(56))
                .foregroundStyle(SparkCleanTheme.textPrimary)
                .contentTransition(.numericText())
                .accessibilityLabel("Reclaimable space estimate unavailable until first scan")

            Text("Reclaimable space")
                .font(.system(size: 15))
                .foregroundStyle(SparkCleanTheme.textSecondary)

            HStack(spacing: 8) {
                ForEach(viewModel.subtitleParts, id: \.self) { part in
                    Text(part)
                        .font(.system(size: 12))
                        .foregroundStyle(SparkCleanTheme.textTertiary)
                    if part != viewModel.subtitleParts.last {
                        Circle().fill(SparkCleanTheme.textTertiary).frame(width: 3, height: 3)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Categories: \(viewModel.subtitleParts.joined(separator: ", "))")

            Button {
                viewModel.startScan()
            } label: {
                Text("Scan for Cleanup")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(SparkCleanTheme.accent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityHint("Runs mo clean --dry-run to preview what can be removed")

            Text("SparkClean previews first — nothing is removed until you confirm.")
                .font(.system(size: 12))
                .foregroundStyle(SparkCleanTheme.textTertiary)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Scanning / cleaning progress

struct CleanScanningView: View {
    @ObservedObject var viewModel: CleanViewModel
    var isCleaning = false

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                SparkCleanOrb(isPulsing: true)
                    .frame(width: 200, height: 200)

                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 260)
                    .tint(SparkCleanTheme.accent)
                    .offset(y: 88)
                    .accessibilityLabel(isCleaning ? "Cleaning progress" : "Scan progress")
                    .accessibilityValue("\(Int(viewModel.progress * 100)) percent")
            }
            .padding(.top, 60)

            VStack(spacing: 10) {
                Text(isCleaning ? "Cleaning your Mac" : "Scanning your Mac")
                    .font(SparkCleanTheme.metric(30))
                    .foregroundStyle(SparkCleanTheme.textPrimary)
                Text("\(Int(viewModel.progress * 100))%")
                    .font(SparkCleanTheme.metric(22, weight: .medium))
                    .foregroundStyle(SparkCleanTheme.textSecondary)
                    .contentTransition(.numericText())
                Text(isCleaning
                    ? "SparkClean is validating and removing the confirmed items"
                    : "Checking caches, logs, leftovers, and trash via mo clean --dry-run")
                    .font(.system(size: 13))
                    .foregroundStyle(SparkCleanTheme.textTertiary)
            }

            if !isCleaning {
                Button("Cancel") { viewModel.cancelScan() }
                    .buttonStyle(.plain)
                    .foregroundStyle(SparkCleanTheme.textSecondary)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 60)
    }
}

// MARK: - Results

struct CleanResultsView: View {
    @ObservedObject var viewModel: CleanViewModel

    var body: some View {
        VStack(spacing: 18) {
            CleanResultsHeader(viewModel: viewModel)

            if let summary = viewModel.summary {
                let grouped = Dictionary(grouping: summary.items, by: \.section)
                ForEach(summary.sectionOrder, id: \.self) { section in
                    if let items = grouped[section] {
                        CleanSectionCard(
                            section: section,
                            items: items,
                            viewModel: viewModel)
                    }
                }
            }

            CleanBottomBar(viewModel: viewModel)
                .padding(.top, 8)
        }
    }
}

struct CleanResultsHeader: View {
    @ObservedObject var viewModel: CleanViewModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(bytesText(viewModel.summary?.totalBytes))
                    .font(SparkCleanTheme.metric(38))
                    .foregroundStyle(SparkCleanTheme.textPrimary)
                Text("Potential space · \(viewModel.summary?.itemCount ?? 0) items")
                    .font(.system(size: 13))
                    .foregroundStyle(SparkCleanTheme.textSecondary)
            }
            Spacer()
            Button("Scan Again") { viewModel.startScan() }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(SparkCleanTheme.textSecondary)
        }
        .accessibilityElement(children: .contain)
    }
}

struct CleanSectionCard: View {
    let section: String
    let items: [CleanCategoryItem]
    @ObservedObject var viewModel: CleanViewModel

    private var isExpanded: Bool { viewModel.expandedSections.contains(section) }
    private var sectionBytes: Int64 {
        items.compactMap(\.estimatedBytes).reduce(0, +)
    }

    var body: some View {
        SparkCleanCard(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    viewModel.toggleExpanded(section)
                } label: {
                    HStack {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SparkCleanTheme.textTertiary)
                            .frame(width: 14)
                        Text(section)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SparkCleanTheme.textPrimary)
                        Spacer()
                        Text(bytesText(sectionBytes))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(SparkCleanTheme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(section) category")
                .accessibilityValue("\(bytesText(sectionBytes)), \(items.count) items")
                .accessibilityHint(isExpanded ? "Collapse details" : "Expand details")

                if isExpanded {
                    Divider().overlay(SparkCleanTheme.border)
                    ForEach(items) { item in
                        CleanItemRow(item: item, viewModel: viewModel)
                        if item.id != items.last?.id {
                            Divider().overlay(SparkCleanTheme.border.opacity(0.5))
                                .padding(.leading, 46)
                        }
                    }
                }
            }
        }
    }
}

struct CleanItemRow: View {
    let item: CleanCategoryItem
    @ObservedObject var viewModel: CleanViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(item.skipped ? SparkCleanTheme.textTertiary : SparkCleanTheme.textPrimary)
                    if item.skipped {
                        Text("Skipped")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(SparkCleanTheme.caution.opacity(0.18)))
                            .foregroundStyle(SparkCleanTheme.caution)
                    }
                }
                if let reason = item.skipReason {
                    Text("Reason: \(reason)")
                        .font(.system(size: 11))
                        .foregroundStyle(SparkCleanTheme.textTertiary)
                }
            }
            Spacer()
            Text(item.detail)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(SparkCleanTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

struct CleanBottomBar: View {
    @ObservedObject var viewModel: CleanViewModel

    var body: some View {
        HStack(spacing: 12) {
            Spacer()

            Text("\(viewModel.selectedItems.count) of \(viewModel.selectableIDs.count) categories selected · \(bytesText(viewModel.selectedBytes))")
                .font(.system(size: 13))
                .foregroundStyle(SparkCleanTheme.textSecondary)

            Button("Clean") {
                viewModel.requestClean()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(SparkCleanTheme.accent)
            .disabled(viewModel.selectedItems.isEmpty)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Opens a confirmation before SparkClean removes the selected categories")
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Confirmation sheet

struct CleanConfirmationSheet: View {
    @ObservedObject var viewModel: CleanViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SparkCleanTheme.caution)
                Text("Confirm Cleanup")
                    .font(.system(size: 17, weight: .bold))
            }

            Text("SparkClean will remove the selected categories using its validated cleanup engine. Deletions are permanent for caches; uninstall operations route through the Trash.")
                .font(.system(size: 13))
                .foregroundStyle(SparkCleanTheme.textSecondary)

            SparkCleanCard {
                VStack(alignment: .leading, spacing: 10) {
                    summaryRow("Total size", bytesText(viewModel.selectedBytes))
                    summaryRow("Categories", "\(viewModel.selectedItems.count)")
                    summaryRow("Items", "\(viewModel.summary?.itemCount ?? 0)")
                    let skipped = viewModel.summary?.items.filter(\.skipped).count ?? 0
                    if skipped > 0 {
                        summaryRow("Protected / skipped", "\(skipped)")
                    }
                }
            }

            if !viewModel.selectedCategories.isEmpty {
                SectionLabel(text: "Will be cleaned")
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.selectedCategories) { item in
                            HStack {
                                Text(item.name)
                                    .font(.system(size: 12))
                                Spacer()
                                Text(item.detail)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(SparkCleanTheme.textTertiary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 140)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Clean \(bytesText(viewModel.selectedBytes))", role: .destructive) {
                    dismiss()
                    viewModel.performClean()
                }
                .buttonStyle(.borderedProminent)
                .tint(SparkCleanTheme.danger)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 520)
        .background(SparkCleanTheme.panel)
        .accessibilityLabel("Cleanup confirmation")
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(SparkCleanTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(SparkCleanTheme.textPrimary)
        }
    }
}

// MARK: - Complete

struct CleanCompleteView: View {
    @ObservedObject var viewModel: CleanViewModel

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                Circle()
                    .fill(SparkCleanTheme.healthy.opacity(0.12))
                    .frame(width: 150, height: 150)
                Image(systemName: "checkmark")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(SparkCleanTheme.healthy)
            }
            .padding(.top, 46)
            .accessibilityHidden(true)

            Text("Cleaning Complete")
                .font(SparkCleanTheme.metric(32))
                .foregroundStyle(SparkCleanTheme.textPrimary)

            let result = viewModel.cleanResult
            Text(bytesText(result?.totalBytes))
                .font(SparkCleanTheme.metric(54))
                .foregroundStyle(SparkCleanTheme.healthy)
                .contentTransition(.numericText())

            Text("recovered")
                .font(.system(size: 15))
                .foregroundStyle(SparkCleanTheme.textSecondary)

            let skipped = result?.items.filter(\.skipped).count ?? 0
            Text("\(result?.itemCount ?? 0) items cleaned · \(result?.categoryCount ?? 0) categories · \(skipped) skipped")
                .font(.system(size: 13))
                .foregroundStyle(SparkCleanTheme.textTertiary)

            if let free = result?.freeSpace {
                Text("Free space: \(free)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(SparkCleanTheme.textTertiary)
            }

            Button("Done") { viewModel.resetToIdle() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(SparkCleanTheme.accent)
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cleaning complete, \(bytesText(viewModel.cleanResult?.totalBytes)) recovered")
    }
}

// MARK: - Failure

struct CleanFailedView: View {
    @ObservedObject var viewModel: CleanViewModel
    let reason: String

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "xmark.octagon")
                .font(.system(size: 48))
                .foregroundStyle(SparkCleanTheme.danger)
                .padding(.top, 80)
            Text("Cleanup Failed")
                .font(SparkCleanTheme.metric(26))
            Text(reason)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(SparkCleanTheme.textSecondary)
                .frame(maxWidth: 560)
                .multilineTextAlignment(.center)
            Text(viewModel.lastError?.recoverySuggestion ?? "")
                .font(.system(size: 13))
                .foregroundStyle(SparkCleanTheme.textSecondary)
            HStack {
                Button("Try Again") { viewModel.startScan() }
                Button("Back") { viewModel.resetToIdle() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - SparkClean orb visual

/// The large central animated SparkClean visual for the Clean screen.
/// The glow breathes via opacity only — no scaling — so surrounding content
/// never appears to shift or oscillate.
struct SparkCleanOrb: View {
    var isPulsing = false
    @State private var glowUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [SparkCleanTheme.accent.opacity(0.22), .clear],
                        center: .center, startRadius: 10, endRadius: 110))
                .opacity(glowUp ? 0.9 : 0.55)

            Circle()
                .strokeBorder(SparkCleanTheme.border, lineWidth: 1)
                .padding(10) // adapt to whatever frame the parent provides

            VStack(spacing: 12) {
                SparkleMark(color: SparkCleanTheme.accent)
                    .frame(width: 110, height: 76)
                Text("SPARKCLEAN")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(4)
                    .foregroundStyle(SparkCleanTheme.textTertiary)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: isPulsing ? 1.8 : 3.0).repeatForever(autoreverses: true)) {
                glowUp = true
            }
        }
        .accessibilityHidden(true)
    }
}
