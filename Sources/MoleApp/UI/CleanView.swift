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
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [MoleTheme.warmPanel, MoleTheme.background],
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
            MoleOrb()
                .frame(width: 220, height: 220)
                .padding(.top, 30)

            Text(bytesText(viewModel.reclaimableBytes))
                .font(MoleTheme.metric(56))
                .foregroundStyle(MoleTheme.textPrimary)
                .contentTransition(.numericText())
                .accessibilityLabel("Reclaimable space estimate unavailable until first scan")

            Text("Reclaimable space")
                .font(.system(size: 15))
                .foregroundStyle(MoleTheme.textSecondary)

            HStack(spacing: 8) {
                ForEach(viewModel.subtitleParts, id: \.self) { part in
                    Text(part)
                        .font(.system(size: 12))
                        .foregroundStyle(MoleTheme.textTertiary)
                    if part != viewModel.subtitleParts.last {
                        Circle().fill(MoleTheme.textTertiary).frame(width: 3, height: 3)
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
                    .background(Capsule().fill(MoleTheme.accent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityHint("Runs mo clean --dry-run to preview what can be removed")

            Text("Mole previews first — nothing is removed until you confirm.")
                .font(.system(size: 12))
                .foregroundStyle(MoleTheme.textTertiary)
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
                MoleOrb(isPulsing: true)
                    .frame(width: 200, height: 200)

                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 260)
                    .tint(MoleTheme.accent)
                    .offset(y: 88)
                    .accessibilityLabel(isCleaning ? "Cleaning progress" : "Scan progress")
                    .accessibilityValue("\(Int(viewModel.progress * 100)) percent")
            }
            .padding(.top, 60)

            VStack(spacing: 10) {
                Text(isCleaning ? "Cleaning your Mac" : "Scanning your Mac")
                    .font(MoleTheme.metric(30))
                    .foregroundStyle(MoleTheme.textPrimary)
                Text("\(Int(viewModel.progress * 100))%")
                    .font(MoleTheme.metric(22, weight: .medium))
                    .foregroundStyle(MoleTheme.textSecondary)
                    .contentTransition(.numericText())
                Text(isCleaning
                    ? "Mole is validating and removing the confirmed items"
                    : "Checking caches, logs, leftovers, and trash via mo clean --dry-run")
                    .font(.system(size: 13))
                    .foregroundStyle(MoleTheme.textTertiary)
            }

            if !isCleaning {
                Button("Cancel") { viewModel.cancelScan() }
                    .buttonStyle(.plain)
                    .foregroundStyle(MoleTheme.textSecondary)
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
                    .font(MoleTheme.metric(38))
                    .foregroundStyle(MoleTheme.textPrimary)
                Text("Potential space · \(viewModel.summary?.itemCount ?? 0) items")
                    .font(.system(size: 13))
                    .foregroundStyle(MoleTheme.textSecondary)
            }
            Spacer()
            HStack(spacing: 10) {
                Button("Select All") { viewModel.selectAll() }
                Button("Deselect All") { viewModel.deselectAll() }
                Button("Scan Again") { viewModel.startScan() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(MoleTheme.textSecondary)
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
        MoleCard(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    viewModel.toggleExpanded(section)
                } label: {
                    HStack {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MoleTheme.textTertiary)
                            .frame(width: 14)
                        Text(section)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MoleTheme.textPrimary)
                        Spacer()
                        Text(bytesText(sectionBytes))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(MoleTheme.accent)
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
                    Divider().overlay(MoleTheme.border)
                    ForEach(items) { item in
                        CleanItemRow(item: item, viewModel: viewModel)
                        if item.id != items.last?.id {
                            Divider().overlay(MoleTheme.border.opacity(0.5))
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

    private var isSelected: Bool {
        viewModel.selectedItems.contains(item.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { isSelected },
                set: { on in
                    if on {
                        viewModel.selectedItems.insert(item.id)
                    } else {
                        viewModel.selectedItems.remove(item.id)
                    }
                }
            )) {
                EmptyView()
            }
            .labelsHidden()
            .disabled(item.skipped)
            .accessibilityLabel("Include \(item.name)")
            .accessibilityValue(item.skipped ? "Skipped" : (isSelected ? "Selected" : "Not selected"))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(item.skipped ? MoleTheme.textTertiary : MoleTheme.textPrimary)
                    if item.skipped {
                        Text("Skipped")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(MoleTheme.caution.opacity(0.18)))
                            .foregroundStyle(MoleTheme.caution)
                    }
                }
                if let reason = item.skipReason {
                    Text("Reason: \(reason)")
                        .font(.system(size: 11))
                        .foregroundStyle(MoleTheme.textTertiary)
                }
            }

            Spacer()

            Text(item.detail)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(MoleTheme.textSecondary)
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
                .foregroundStyle(MoleTheme.textSecondary)

            Button("Clean") {
                viewModel.requestClean()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(MoleTheme.accent)
            .disabled(viewModel.selectedItems.isEmpty)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Opens a confirmation before Mole removes the selected categories")
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
                    .foregroundStyle(MoleTheme.caution)
                Text("Confirm Cleanup")
                    .font(.system(size: 17, weight: .bold))
            }

            Text("Mole will remove the selected categories using its validated cleanup engine. Deletions are permanent for caches; uninstall operations route through the Trash.")
                .font(.system(size: 13))
                .foregroundStyle(MoleTheme.textSecondary)

            MoleCard {
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
                                    .foregroundStyle(MoleTheme.textTertiary)
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
                .tint(MoleTheme.danger)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 520)
        .background(MoleTheme.panel)
        .accessibilityLabel("Cleanup confirmation")
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(MoleTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(MoleTheme.textPrimary)
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
                    .fill(MoleTheme.healthy.opacity(0.12))
                    .frame(width: 150, height: 150)
                Image(systemName: "checkmark")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(MoleTheme.healthy)
            }
            .padding(.top, 46)
            .accessibilityHidden(true)

            Text("Cleaning Complete")
                .font(MoleTheme.metric(32))
                .foregroundStyle(MoleTheme.textPrimary)

            let result = viewModel.cleanResult
            Text(bytesText(result?.totalBytes))
                .font(MoleTheme.metric(54))
                .foregroundStyle(MoleTheme.healthy)
                .contentTransition(.numericText())

            Text("recovered")
                .font(.system(size: 15))
                .foregroundStyle(MoleTheme.textSecondary)

            let skipped = result?.items.filter(\.skipped).count ?? 0
            Text("\(result?.itemCount ?? 0) items cleaned · \(result?.categoryCount ?? 0) categories · \(skipped) skipped")
                .font(.system(size: 13))
                .foregroundStyle(MoleTheme.textTertiary)

            if let free = result?.freeSpace {
                Text("Free space: \(free)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(MoleTheme.textTertiary)
            }

            Button("Done") { viewModel.resetToIdle() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(MoleTheme.accent)
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
                .foregroundStyle(MoleTheme.danger)
                .padding(.top, 80)
            Text("Cleanup Failed")
                .font(MoleTheme.metric(26))
            Text(reason)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(MoleTheme.textSecondary)
                .frame(maxWidth: 560)
                .multilineTextAlignment(.center)
            Text(viewModel.lastError?.recoverySuggestion ?? "")
                .font(.system(size: 13))
                .foregroundStyle(MoleTheme.textSecondary)
            HStack {
                Button("Try Again") { viewModel.startScan() }
                Button("Back") { viewModel.resetToIdle() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Mole orb visual

/// The large central animated Mole visual for the Clean screen.
/// The glow breathes via opacity only — no scaling — so surrounding content
/// never appears to shift or oscillate.
struct MoleOrb: View {
    var isPulsing = false
    @State private var glowUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [MoleTheme.accent.opacity(0.22), .clear],
                        center: .center, startRadius: 10, endRadius: 110))
                .opacity(glowUp ? 0.9 : 0.55)

            Circle()
                .strokeBorder(MoleTheme.border, lineWidth: 1)
                .padding(10) // adapt to whatever frame the parent provides

            VStack(spacing: 12) {
                MoleSilhouette(color: MoleTheme.accent)
                    .frame(width: 110, height: 76)
                Text("MOLE")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(4)
                    .foregroundStyle(MoleTheme.textTertiary)
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
