import SwiftUI

@MainActor
final class AppsViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case planning
        case cleaning
        case complete(String)
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var apps: [AppInventoryItem] = []
    @Published var selectedApps: Set<String> = [] // by uninstall_name
    @Published var searchText = ""
    @Published var plan: UninstallPlan?
    @Published var planApp: AppInventoryItem?
    @Published var showConfirmation = false
    @Published var lastError: SparkCleanUserError?
    @Published var expandedApp: String?

    let client: SparkCleanClient
    private var loadTask: Task<Void, Never>?

    init(client: SparkCleanClient) {
        self.client = client
    }

    var filteredApps: [AppInventoryItem] {
        guard !searchText.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }

    var selectedItems: [AppInventoryItem] {
        apps.filter { selectedApps.contains($0.uninstallName) }
    }

    var selectedCount: Int { selectedItems.count }

    func loadIfNeeded() {
        guard phase == .idle, apps.isEmpty else { return }
        load()
    }

    func load() {
        loadTask?.cancel()
        phase = .loading
        lastError = nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let inventory = try await client.appInventory()
                guard !Task.isCancelled else { return }
                apps = inventory
                phase = inventory.isEmpty ? .loaded : .loaded
            } catch SparkCleanClient.SparkCleanClientError.cliNotFound {
                lastError = SparkCleanUserError(kind: .cliMissing)
                phase = .failed("Command-line tool not found")
            } catch {
                lastError = SparkCleanUserError(kind: .scanFailed(String(describing: error)))
                phase = .failed(String(describing: error))
            }
        }
    }

    func toggleSelection(_ app: AppInventoryItem) {
        if selectedApps.contains(app.uninstallName) {
            selectedApps.remove(app.uninstallName)
        } else {
            selectedApps.insert(app.uninstallName)
        }
    }

    /// Load the real dry-run plan from `mo uninstall <name> --dry-run`, then
    /// confirm (unless disabled in Settings). The plan is always fetched — it
    /// is what performs the uninstall through Mole.
    func requestRemove() {
        guard let first = selectedItems.first else { return }
        planApp = first
        phase = .planning
        Task { [weak self] in
            guard let self else { return }
            do {
                let fetched = try await client.uninstallPlan(app: first)
                plan = fetched
                phase = .loaded
                if SparkCleanPreferences.shared.confirmBeforeUninstall {
                    showConfirmation = true
                } else {
                    performUninstall()
                }
            } catch {
                phase = .loaded
                lastError = SparkCleanUserError(kind: .scanFailed(String(describing: error)))
            }
        }
    }

    /// Confirmed uninstall via the real `mo uninstall <name>`.
    func performUninstall() {
        guard let app = planApp else { return }
        showConfirmation = false
        phase = .cleaning
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await client.uninstall(app: app)
                SparkCleanPreferences.shared.cleanWatchUninstallCount += 1
                selectedApps.remove(app.uninstallName)
                apps.removeAll { $0.uninstallName == app.uninstallName }
                phase = .complete(result.summaryLine ?? "\(app.name) removed")
                planApp = nil
            } catch {
                phase = .failed(String(describing: error))
                lastError = SparkCleanUserError(kind: .scanFailed(String(describing: error)))
            }
        }
    }

    func dismissError() {
        phase = apps.isEmpty ? .idle : .loaded
    }
}
