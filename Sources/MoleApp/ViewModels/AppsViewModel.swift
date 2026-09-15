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
    @Published var lastError: MoleUserError?
    @Published var expandedApp: String?

    let client: MoleClient
    private var loadTask: Task<Void, Never>?

    init(client: MoleClient) {
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
            } catch MoleClient.MoleClientError.cliNotFound {
                lastError = MoleUserError(kind: .cliMissing)
                phase = .failed("Mole CLI not found")
            } catch {
                lastError = MoleUserError(kind: .scanFailed(String(describing: error)))
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

    /// Load the real dry-run plan from `mo uninstall <name> --dry-run`.
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
                showConfirmation = true
            } catch {
                phase = .loaded
                lastError = MoleUserError(kind: .scanFailed(String(describing: error)))
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
                MolePreferences.shared.cleanWatchUninstallCount += 1
                selectedApps.remove(app.uninstallName)
                apps.removeAll { $0.uninstallName == app.uninstallName }
                phase = .complete(result.summaryLine ?? "\(app.name) removed")
                planApp = nil
            } catch {
                phase = .failed(String(describing: error))
                lastError = MoleUserError(kind: .scanFailed(String(describing: error)))
            }
        }
    }

    func dismissError() {
        phase = apps.isEmpty ? .idle : .loaded
    }
}
