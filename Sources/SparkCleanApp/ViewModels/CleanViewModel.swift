import SwiftUI

/// Drives the Clean dashboard: idle → scanning → results → cleaning → done.
/// Scanning runs `mo clean --dry-run`; cleaning runs the real `mo clean`.
@MainActor
final class CleanViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case cleaning
        case complete
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var summary: CleanSummary?
    @Published var selectedItems: Set<String> = []
    @Published var expandedSections: Set<String> = []
    @Published var progress: Double = 0
    @Published var statusLine: String = ""
    @Published var lastError: SparkCleanUserError?
    @Published var cleanResult: CleanSummary?
    @Published var showConfirmation = false
    /// Presented when an actual (non dry-run) clean is attempted without an
    /// activated license — previews stay free, real runs require PRO.
    @Published var cliAvailable: Bool?

    private let client: SparkCleanClient
    private var scanTask: Task<Void, Never>?
    private var progressTimer: Timer?

    init(client: SparkCleanClient) {
        self.client = client
    }

    // MARK: Derived values

    var selectedCategories: [CleanCategoryItem] {
        guard let summary else { return [] }
        return summary.items.filter { selectedItems.contains($0.id) }
    }

    /// Total size of currently selectable (non-skipped) candidates.
    var reclaimableBytes: Int64? {
        guard let summary else { return nil }
        return summary.items
            .filter { !$0.skipped }
            .compactMap(\.estimatedBytes)
            .reduce(0, +)
    }

    var selectedBytes: Int64? {
        guard let summary else { return nil }
        let selected = summary.items.filter { selectedItems.contains($0.id) }
        let bytes = selected.compactMap(\.estimatedBytes).reduce(0, +)
        return bytes
    }

    var selectableIDs: Set<String> {
        Set(summary?.items.filter { !$0.skipped }.map(\.id) ?? [])
    }

    var allSelected: Bool {
        !selectableIDs.isEmpty && selectedItems == selectableIDs
    }

    var subtitleParts: [String] {
        guard let summary, !summary.items.isEmpty else {
            return ["Caches", "Logs", "Leftovers", "Trash"]
        }
        let names = summary.items.filter { !$0.skipped }.prefix(4).map(\.name)
        return names.isEmpty ? ["Caches", "Logs", "Leftovers", "Trash"] : names
    }

    // MARK: Actions

    func startScan() {
        guard phase != .scanning, phase != .cleaning else { return }
        scanTask?.cancel()
        phase = .scanning
        progress = 0
        statusLine = "Scanning your Mac"
        lastError = nil
        summary = nil
        cleanResult = nil
        startProgressSimulation()

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await client.cleanDryRun()
                guard !Task.isCancelled else { return }
                stopProgressSimulation()
                withAnimation(.easeOut(duration: 0.35)) {
                    self.summary = result
                    self.selectedItems = Set(result.items.filter { !$0.skipped }.map(\.id))
                    self.phase = .results
                    self.progress = 1
                }
                cliAvailable = true
            } catch is CancellationError {
                stopProgressSimulation()
                phase = .idle
            } catch SparkCleanClient.SparkCleanClientError.cliNotFound {
                stopProgressSimulation()
                cliAvailable = false
                lastError = SparkCleanUserError(kind: .cliMissing)
                phase = .idle
            } catch {
                stopProgressSimulation()
                lastError = SparkCleanUserError(kind: .scanFailed(String(describing: error)))
                phase = .failed(String(describing: error))
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        stopProgressSimulation()
        phase = .idle
    }

    /// Present the confirmation sheet (unless disabled in Settings); real
    /// deletion only happens after the user confirms the reviewed plan.
    func requestClean() {
        guard !selectedItems.isEmpty else { return }
        guard SparkCleanPreferences.shared.confirmBeforeClean else {
            performClean()
            return
        }
        showConfirmation = true
    }

    /// Confirmed clean: run the real `mo clean`. Mole revalidates every path;
    /// the app presents the CLI's own accounting.
    func performClean() {
        showConfirmation = false
        phase = .cleaning
        progress = 0
        statusLine = "Cleaning your Mac"
        startProgressSimulation(slower: true)

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await client.clean()
                guard !Task.isCancelled else { return }
                stopProgressSimulation()
                withAnimation(.easeOut(duration: 0.35)) {
                    self.cleanResult = result
                    self.phase = .complete
                    self.progress = 1
                }
                SparkCleanPreferences.shared.cleanWatchSessionCount += 1
                if let bytes = result.totalBytes {
                    SparkCleanPreferences.shared.cleanWatchTotalBytes += bytes
                }
            } catch is CancellationError {
                stopProgressSimulation()
                phase = .idle
            } catch {
                stopProgressSimulation()
                lastError = SparkCleanUserError(kind: .scanFailed(String(describing: error)))
                phase = .failed(String(describing: error))
            }
        }
    }

    func selectAll() { selectedItems = selectableIDs }
    func deselectAll() { selectedItems.removeAll() }
    func toggleExpanded(_ section: String) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }

    func resetToIdle() {
        phase = .idle
        summary = nil
        cleanResult = nil
        selectedItems.removeAll()
        progress = 0
    }

    // MARK: Progress simulation

    /// `mo clean` offers no structured progress stream, so the UI shows a
    /// decelerating pseudo-progress that never claims false completion; the
    /// real terminal state comes from the CLI result.
    private func startProgressSimulation(slower: Bool = false) {
        progressTimer?.invalidate()
        let interval: TimeInterval = slower ? 0.35 : 0.12
        let cap: Double = slower ? 0.9 : 0.85
        var current = progress
        progressTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let remaining = cap - current
                guard remaining > 0.005 else { return }
                current += remaining * 0.06
                self.progress = min(current, cap)
            }
        }
    }

    private func stopProgressSimulation() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}
