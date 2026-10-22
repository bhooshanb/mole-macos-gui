import SwiftUI

@MainActor
final class OptimizeViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case previewing
        case previewed
        case running
        case complete
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var preview: OptimizeSummary?
    @Published var result: OptimizeSummary?
    @Published var completedTaskNames: Set<String> = []
    @Published var lastError: SparkCleanUserError?
    /// Presented when the actual optimize run is attempted without an
    /// activated license — the dry-run preview stays free.

    private let client: SparkCleanClient
    private var task: Task<Void, Never>?

    init(client: SparkCleanClient) {
        self.client = client
    }

    var displaySummary: OptimizeSummary? {
        phase == .running || phase == .complete ? (result ?? preview) : preview
    }

    /// Ordered task list for the progress UI. During a real run the CLI lists
    /// tasks as it goes, so we mirror preview order and mark outcomes live.
    var orderedTasks: [OptimizeTask] {
        displaySummary?.tasks ?? []
    }

    func requestOptimize() {
        guard phase == .idle || phase == .previewed || phase == .complete || phase == .failed("") else {
            return
        }
        phase = .previewing
        lastError = nil
        completedTaskNames = []
        task = Task { [weak self] in
            guard let self else { return }
            do {
                // Always preview first (dry-run), then run for real so the UI
                // can show the exact task list before any change happens.
                let dryRun = try await client.optimizeDryRun()
                guard !Task.isCancelled else { return }
                withAnimation { self.preview = dryRun }
                phase = .previewed
            } catch is CancellationError {
                phase = .idle
            } catch {
                lastError = SparkCleanUserError(kind: .scanFailed(String(describing: error)))
                phase = .failed(String(describing: error))
            }
        }
    }

    func performOptimize() {
        // GPL-covered maintenance is available without purchase or activation.
        phase = .running
        completedTaskNames = []
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await client.optimize()
                guard !Task.isCancelled else { return }
                withAnimation {
                    self.result = summary
                    self.completedTaskNames = Set(summary.tasks.map(\.name))
                    self.phase = .complete
                }
                SparkCleanPreferences.shared.cleanWatchOptimizeCount += 1
            } catch is CancellationError {
                phase = .previewed
            } catch {
                lastError = SparkCleanUserError(kind: .scanFailed(String(describing: error)))
                phase = .failed(String(describing: error))
            }
        }
    }

    func reset() {
        task?.cancel()
        phase = .idle
        preview = nil
        result = nil
        completedTaskNames = []
    }
}
