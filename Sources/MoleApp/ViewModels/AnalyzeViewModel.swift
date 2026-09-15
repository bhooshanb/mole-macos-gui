import SwiftUI

/// One node in the analyze tree, derived from Mole's `analyze --json` entries.
struct AnalyzeNode: Identifiable, Equatable {
    var id: String { path }
    var name: String
    var path: String
    var size: Int64
    var isDir: Bool
    var insight: Bool
    var cleanable: Bool
    var lastAccess: String?
    var parentPath: String?
}

@MainActor
final class AnalyzeViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case loaded
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var currentPath: String = ""
    @Published var isOverview = true
    @Published var nodes: [AnalyzeNode] = []
    @Published var largeFiles: [AnalyzeFileEntry] = []
    @Published var totalSize: Int64 = 0
    @Published var totalFiles: Int64 = 0
    @Published var breadcrumbs: [(String, String)] = [] // (name, path)
    @Published var selectedNode: AnalyzeNode?
    @Published var lastError: MoleUserError?
    @Published var showTrashConfirmation = false

    /// Sort mode for the right-hand list.
    @Published var sortMode: SortMode = .size

    enum SortMode: String, CaseIterable, Identifiable {
        case size = "Size"
        case name = "Name"
        var id: String { rawValue }
    }

    static let quickLocations: [(String, String?)] = [
        ("Overview", nil),
        ("Home", "~"),
        ("Library", "~/Library"),
        ("Applications", "/Applications"),
        ("Downloads", "~/Downloads"),
        ("Volumes", "/Volumes"),
    ]

    private let client: MoleClient
    private var scanTask: Task<Void, Never>?

    init(client: MoleClient) {
        self.client = client
    }

    var sortedNodes: [AnalyzeNode] {
        switch sortMode {
        case .size: return nodes.sorted { $0.size > $1.size }
        case .name: return nodes.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
    }

    func loadOverviewIfNeeded() {
        guard phase == .idle, nodes.isEmpty else { return }
        scan(path: nil)
    }

    /// Scan via `mo analyze --json [path]`. Nil path = machine overview.
    /// External volumes require an explicit path (matching Mole's own rule);
    /// the Volumes quick location provides it.
    func scan(path: String?) {
        scanTask?.cancel()
        phase = .scanning
        lastError = nil
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let report = try await client.analyze(path: path)
                guard !Task.isCancelled else { return }
                let parent = path ?? ""
                let mapped = report.entries.map { entry in
                    AnalyzeNode(
                        name: entry.name, path: entry.path, size: entry.size,
                        isDir: entry.isDir, insight: entry.insight ?? false,
                        cleanable: entry.cleanable ?? false,
                        lastAccess: entry.lastAccess, parentPath: parent)
                }
                withAnimation(.easeOut(duration: 0.25)) {
                    nodes = mapped
                    largeFiles = report.largeFiles ?? []
                    totalSize = report.totalSize
                    totalFiles = report.totalFiles ?? 0
                    currentPath = report.path
                    isOverview = report.overview
                    updateBreadcrumbs(for: report)
                    selectedNode = nil
                    phase = .loaded
                }
            } catch is CancellationError {
                phase = nodes.isEmpty ? .idle : .loaded
            } catch {
                lastError = MoleUserError(kind: .scanFailed(String(describing: error)))
                phase = .failed(String(describing: error))
            }
        }
    }

    func drillDown(_ node: AnalyzeNode) {
        guard node.isDir else { return }
        scan(path: node.path)
    }

    func popToBreadcrumb(_ path: String) {
        if path.isEmpty {
            scan(path: nil)
        } else {
            scan(path: path)
        }
    }

    private func updateBreadcrumbs(for report: AnalyzeReport) {
        var crumbs: [(String, String)] = []
        crumbs.append(("Overview", ""))
        if !report.overview {
            let expanded = NSString(string: report.path).expandingTildeInPath
            var partial = ""
            for component in expanded.split(separator: "/") {
                partial += "/" + component
                crumbs.append((String(component), partial))
            }
        }
        breadcrumbs = crumbs
    }

    // MARK: Actions on selected items

    func revealInFinder(_ node: AnalyzeNode) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
    }

    func quickLook(_ node: AnalyzeNode) {
        // QLPreviewPanel is managed by the view; signal selection.
        selectedNode = node
        NotificationCenter.default.post(name: .moleRequestQuickLook, object: node.path)
    }

    /// Moves the item to Trash via Finder (recoverable), after confirmation.
    /// Mole's analyze TUI itself moves to Trash after confirmation; the app
    /// matches that semantic through NSWorkspace instead of raw deletion.
    func trashConfirmed(_ node: AnalyzeNode) {
        let target = URL(fileURLWithPath: node.path)
        NSWorkspace.shared.recycle([target]) { results, error in
            Task { @MainActor in
                if let error {
                    self.lastError = MoleUserError(kind: .generic(error.localizedDescription))
                } else {
                    self.scan(path: self.currentPath == "~" ? "~" : self.currentPath)
                }
            }
        }
    }

    func requestTrash(_ node: AnalyzeNode) {
        selectedNode = node
        showTrashConfirmation = true
    }
}

extension Notification.Name {
    static let moleRequestQuickLook = Notification.Name("moleRequestQuickLook")
}
