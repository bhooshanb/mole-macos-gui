import SwiftUI

struct AnalyzeView: View {
    @ObservedObject var viewModel: AnalyzeViewModel

    var body: some View {
        VStack(spacing: 0) {
            AnalyzeToolbar(viewModel: viewModel)
            Divider().overlay(MoleTheme.border)

            HSplitView {
                // Left: locations + navigation tree
                ScrollView {
                    AnalyzeSidebar(viewModel: viewModel)
                        .padding(12)
                }
                .frame(minWidth: 220, maxWidth: 280)

                // Center: treemap
                Group {
                    switch viewModel.phase {
                    case .idle, .scanning:
                        VStack(spacing: 14) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Scanning \(viewModel.isOverview ? "your Mac" : viewModel.currentPath)…")
                                .font(.system(size: 13))
                                .foregroundStyle(MoleTheme.textSecondary)
                            Button("Cancel") { viewModel.scan(path: viewModel.currentPath) }
                                .buttonStyle(.bordered)
                                .opacity(0) // scanning restart is cheap; keep UI simple
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failed(let reason):
                        ErrorStateView(
                            error: viewModel.lastError ?? MoleUserError(kind: .generic(reason))) {
                            viewModel.scan(path: viewModel.currentPath.isEmpty ? nil : viewModel.currentPath)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .loaded:
                        AnalyzeTreemapView(viewModel: viewModel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 420)

                // Right: details + largest files
                AnalyzeDetailPanel(viewModel: viewModel)
                    .frame(minWidth: 260, maxWidth: 340)
            }
        }
        .background(MoleTheme.background)
        .onAppear { viewModel.loadOverviewIfNeeded() }
        .sheet(isPresented: $viewModel.showTrashConfirmation) {
            TrashConfirmationSheet(viewModel: viewModel)
        }
        .accessibilityLabel("Analyze")
    }
}

struct AnalyzeToolbar: View {
    @ObservedObject var viewModel: AnalyzeViewModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(viewModel.breadcrumbs, id: \.1) { crumb in
                Button {
                    viewModel.popToBreadcrumb(crumb.1)
                } label: {
                    Text(crumb.0)
                        .font(.system(size: 12))
                        .foregroundStyle(
                            crumb.1 == viewModel.currentPath ? MoleTheme.textPrimary : MoleTheme.infoBlue)
                }
                .buttonStyle(.plain)
                if crumb.1 != viewModel.breadcrumbs.last?.1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(MoleTheme.textTertiary)
                }
            }
            Spacer()
            Text("\(bytesText(viewModel.totalSize)) · \(viewModel.totalFiles) files")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(MoleTheme.textSecondary)
            Picker("Sort", selection: $viewModel.sortMode) {
                ForEach(AnalyzeViewModel.SortMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .accessibilityLabel("Sort list by")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct AnalyzeSidebar: View {
    @ObservedObject var viewModel: AnalyzeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Locations")
            ForEach(AnalyzeViewModel.quickLocations, id: \.0) { location in
                let isVolumes = location.0 == "Volumes"
                let isActive = location.0 == "Overview" && viewModel.isOverview
                Button {
                    if location.0 == "Overview" {
                        viewModel.scan(path: nil)
                    } else {
                        viewModel.scan(path: location.1)
                    }
                } label: {
                    HStack {
                        Image(systemName: icon(for: location.0))
                            .frame(width: 16)
                        Text(location.0)
                        if isVolumes {
                            Text("explicit")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(MoleTheme.infoBlue.opacity(0.16)))
                                .foregroundStyle(MoleTheme.infoBlue)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isActive ? Color.white.opacity(0.1) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isActive ? MoleTheme.textPrimary : MoleTheme.textSecondary)
                .accessibilityLabel("Analyze \(location.0)")
                .accessibilityAddTraits(isActive ? [.isSelected] : [])

                if location.0 == "Overview" {
                    Divider().padding(.vertical, 4)
                }
            }

            Divider().padding(.vertical, 6)
            SectionLabel(text: "Custom folder")
            Button {
                chooseFolder()
            } label: {
                HStack {
                    Image(systemName: "folder.badge.plus").frame(width: 16)
                    Text("Choose…")
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(MoleTheme.textSecondary)
            .accessibilityLabel("Choose a folder to analyze")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.scan(path: url.path)
        }
    }

    private func icon(for name: String) -> String {
        switch name {
        case "Overview": return "macbook"
        case "Home": return "house"
        case "Library": return "books.vertical"
        case "Applications": return "square.grid.3x1.folder.badge.plus"
        case "Downloads": return "arrow.down.circle"
        case "Volumes": return "externaldrive"
        default: return "folder"
        }
    }
}

// MARK: - Treemap

/// Squarified treemap laid out in pure geometry, rendered with SwiftUI rects.
/// Children beyond the visible count collapse into a "More" tile to stay efficient.
struct AnalyzeTreemapView: View {
    @ObservedObject var viewModel: AnalyzeViewModel

    var body: some View {
        GeometryReader { geo in
            let tiles = TreemapLayout.squarify(
                entries: viewModel.sortedNodes.filter { $0.size > 0 },
                in: CGRect(origin: .zero, size: geo.size))
            ZStack {
                ForEach(tiles) { tile in
                    TreemapTile(tile: tile, viewModel: viewModel)
                }
            }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Disk usage treemap")
    }
}

struct TreemapTile: View {
    let tile: TreemapLayout.Tile
    @ObservedObject var viewModel: AnalyzeViewModel

    private var fraction: Double {
        viewModel.totalSize > 0 ? Double(tile.node.size) / Double(viewModel.totalSize) : 0
    }

    private var tint: Color {
        if tile.node.insight { return MoleTheme.caution.opacity(0.32) }
        if tile.node.cleanable { return MoleTheme.healthy.opacity(0.2) }
        return MoleTheme.infoBlue.opacity(0.1 + 0.22 * min(1, fraction * 2.2))
    }

    var body: some View {
        VStack(spacing: 2) {
            if tile.rect.height > 34 {
                Text(tile.node.name)
                    .font(.system(size: min(13, max(9, tile.rect.height / 5)), weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(MoleTheme.textPrimary)
            }
            if tile.rect.height > 52 {
                Text(bytesText(tile.node.size))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(MoleTheme.textSecondary)
            }
            if tile.rect.height > 74 && fraction > 0.005 {
                Text(String(format: "%.1f%%", fraction * 100))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(MoleTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    viewModel.selectedNode?.path == tile.node.path
                        ? MoleTheme.borderStrong : MoleTheme.border,
                    lineWidth: viewModel.selectedNode?.path == tile.node.path ? 2 : 1)
        )
        .padding(2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { viewModel.drillDown(tile.node) }
        .onTapGesture { viewModel.selectedNode = tile.node }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.node.name), \(bytesText(tile.node.size)), \(tile.node.isDir ? "folder" : "file")")
        .accessibilityHint("Double-click to open folder")
        .accessibilityAddTraits(viewModel.selectedNode?.path == tile.node.path ? .isSelected : [])
        .help(tile.node.path)
    }
}

/// Squarified treemap layout operating on normalized area fractions.
/// Classic algorithm: repeatedly lay the next row of items along the shorter
/// side, keeping the row while its worst aspect ratio improves.
enum TreemapLayout {
    struct Tile: Identifiable {
        var id: String { node.path }
        let node: AnalyzeNode
        let rect: CGRect
    }

    static func squarify(entries: [AnalyzeNode], in bounds: CGRect) -> [Tile] {
        guard !entries.isEmpty, bounds.width > 1, bounds.height > 1 else { return [] }
        let total = entries.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0 else { return [] }

        // Normalize sizes into area fractions of the bounds area.
        let area = Double(bounds.width * bounds.height)
        var queue: [(node: AnalyzeNode, area: Double)] = entries.map {
            ($0, Double($0.size) / Double(total) * area)
        }

        var tiles: [Tile] = []
        var remaining = bounds

        while !queue.isEmpty, remaining.width > 1.5, remaining.height > 1.5 {
            // Lay the strip parallel to the shorter side (Bruls et al.):
            // the strip's length equals the shorter side, its thickness is
            // rowArea / shorterSide, and items stack along the strip.
            let horizontalStrip = remaining.height > remaining.width // items laid along x
            let stripLength = horizontalStrip ? remaining.width : remaining.height

            var row: [(node: AnalyzeNode, area: Double)] = []
            var rowArea: Double = 0
            var bestWorst: Double = .infinity

            while let next = queue.first {
                let candidateArea = rowArea + next.area
                let candidateWorst = worstAspect(rowArea: candidateArea, side: Double(stripLength), count: row.count + 1)
                if row.isEmpty || candidateWorst <= bestWorst {
                    row.append(next)
                    rowArea = candidateArea
                    bestWorst = candidateWorst
                    queue.removeFirst()
                } else {
                    break
                }
            }

            guard rowArea > 0, stripLength > 0 else { break }
            let thickness = rowArea / Double(stripLength)
            let thicknessCG = CGFloat(thickness)

            var offset: CGFloat = 0
            for item in row {
                let length = CGFloat(item.area / thickness)
                let rect: CGRect
                if horizontalStrip {
                    rect = CGRect(
                        x: remaining.minX + offset, y: remaining.minY,
                        width: min(length, remaining.width - offset), height: thicknessCG)
                } else {
                    rect = CGRect(
                        x: remaining.minX, y: remaining.minY + offset,
                        width: thicknessCG, height: min(length, remaining.height - offset))
                }
                tiles.append(Tile(node: item.node, rect: rect))
                offset += length
            }

            remaining = horizontalStrip
                ? CGRect(x: remaining.minX, y: remaining.minY + thicknessCG,
                         width: remaining.width, height: max(0, remaining.height - thicknessCG))
                : CGRect(x: remaining.minX + thicknessCG, y: remaining.minY,
                         width: max(0, remaining.width - thicknessCG), height: remaining.height)
        }

        return tiles
    }

    /// Worst aspect ratio of a row of `count` equal-area items with total area
    /// `rowArea` laid into a strip of thickness `rowArea / side`.
    static func worstAspect(rowArea: Double, side: Double, count: Int) -> Double {
        guard rowArea > 0, side > 0, count > 0 else { return .infinity }
        let thickness = rowArea / side
        let itemArea = rowArea / Double(count)
        let length = itemArea / thickness
        guard thickness > 0, length > 0 else { return .infinity }
        return max(thickness / length, length / thickness)
    }
}

// MARK: - Detail panel

struct AnalyzeDetailPanel: View {
    @ObservedObject var viewModel: AnalyzeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let node = viewModel.selectedNode {
                    SectionLabel(text: "Selected")
                    MoleCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(node.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MoleTheme.textPrimary)
                            detailRow("Path", node.path)
                            detailRow("Size", bytesText(node.size))
                            if viewModel.totalSize > 0 {
                                detailRow("Share",
                                          String(format: "%.1f%% of parent",
                                                 Double(node.size) / Double(viewModel.totalSize) * 100))
                            }
                            detailRow("Type", node.isDir ? "Folder" : "File")
                            if let access = node.lastAccess {
                                detailRow("Last opened", access)
                            }
                            if node.insight {
                                Label("Mole flags this as noteworthy", systemImage: "eye")
                                    .font(.system(size: 11))
                                    .foregroundStyle(MoleTheme.caution)
                            }
                            if node.cleanable {
                                Label("Considered cleanable by Mole — use Clean", systemImage: "sparkles")
                                    .font(.system(size: 11))
                                    .foregroundStyle(MoleTheme.healthy)
                            }
                        }
                    }

                    HStack {
                        Button("Finder") { viewModel.revealInFinder(node) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("Preview") { viewModel.quickLook(node) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("Move to Trash", role: .destructive) {
                            viewModel.requestTrash(node)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(MoleTheme.danger)
                    }
                } else {
                    SectionLabel(text: "Selected item")
                    Text("Click a treemap tile or list row to inspect it.")
                        .font(.system(size: 12))
                        .foregroundStyle(MoleTheme.textTertiary)
                }

                SectionLabel(text: "Largest files")
                if viewModel.largeFiles.isEmpty {
                    Text("No large files reported at this location.")
                        .font(.system(size: 12))
                        .foregroundStyle(MoleTheme.textTertiary)
                } else {
                    ForEach(Array(viewModel.largeFiles.prefix(20).enumerated()), id: \.offset) { _, file in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .foregroundStyle(MoleTheme.textPrimary)
                                Text(file.path)
                                    .font(.system(size: 9, design: .monospaced))
                                    .lineLimit(1)
                                    .foregroundStyle(MoleTheme.textTertiary)
                            }
                            Spacer()
                            Text(bytesText(file.size))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(MoleTheme.textSecondary)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectedNode = AnalyzeNode(
                                name: file.name, path: file.path, size: file.size,
                                isDir: false, insight: false, cleanable: false,
                                lastAccess: nil, parentPath: nil)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(file.name), \(bytesText(file.size))")
                    }
                }
            }
            .padding(12)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(MoleTheme.textTertiary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(MoleTheme.mono)
                .foregroundStyle(MoleTheme.textSecondary)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

struct TrashConfirmationSheet: View {
    @ObservedObject var viewModel: AnalyzeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .foregroundStyle(MoleTheme.danger)
                Text("Move to Trash?")
                    .font(.system(size: 17, weight: .bold))
            }
            if let node = viewModel.selectedNode {
                Text("“\(node.name)” (\(bytesText(node.size))) will be moved to the Trash. You can restore it from the Trash until it is emptied.")
                    .font(.system(size: 13))
                    .foregroundStyle(MoleTheme.textSecondary)
                Text(node.path)
                    .font(MoleTheme.mono)
                    .textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash", role: .destructive) {
                    dismiss()
                    if let node = viewModel.selectedNode {
                        viewModel.trashConfirmed(node)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(MoleTheme.danger)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440, height: 220)
        .background(MoleTheme.panel)
        .accessibilityLabel("Move to Trash confirmation")
    }
}
