import SwiftUI

/// Backs the Updates and Startup sub-tabs with real system data:
/// Homebrew casks for updates, launch agents + login items for startup.
@MainActor
final class UpdatesStartupViewModel: ObservableObject {
    // MARK: Updates

    @Published var updatesPhase: Phase = .idle
    @Published var outdatedCasks: [HomebrewCaskUpdate] = []
    @Published var installedCaskNames: [String] = []
    @Published var brewMissing = false
    @Published var upgradingCask: String?
    @Published var lastUpgradeResult: String?

    // MARK: Startup

    @Published var startupPhase: Phase = .idle
    @Published var userAgents: [LaunchAgentInfo] = []
    @Published var systemAgents: [LaunchAgentInfo] = []
    @Published var loginItems: [String] = []
    @Published var loginItemsUnavailable = false

    enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    private let client: MoleClient
    private var upgradeTasks: [String: Task<Void, Never>] = [:]

    init(client: MoleClient) {
        self.client = client
    }

    // MARK: Loading

    func loadUpdatesIfNeeded() {
        guard updatesPhase == .idle else { return }
        loadUpdates()
    }

    func loadUpdates() {
        updatesPhase = .loading
        lastUpgradeResult = nil
        Task { [weak self] in
            guard let self else { return }
            guard MoleClient.findBrew() != nil else {
                brewMissing = true
                outdatedCasks = []
                updatesPhase = .loaded
                return
            }
            brewMissing = false
            do {
                async let outdated = client.outdatedCasks()
                async let installed = client.installedCasks()
                let (outdatedList, installedList) = try await (outdated, installed)
                outdatedCasks = outdatedList
                installedCaskNames = installedList
                updatesPhase = .loaded
            } catch {
                outdatedCasks = []
                updatesPhase = .failed(String(describing: error))
            }
        }
    }

    /// `brew upgrade --cask <name>`; the result is surfaced verbatim.
    func upgrade(_ cask: HomebrewCaskUpdate) {
        guard upgradeTasks[cask.name] == nil else { return }
        upgradingCask = cask.name
        upgradeTasks[cask.name] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.upgradeTasks[cask.name] = nil
                self.upgradingCask = nil
            }
            do {
                let result = try await client.upgradeCask(named: cask.name)
                if result.succeeded {
                    MolePreferences.shared.cleanWatchOptimizeCount += 1
                    lastUpgradeResult = "Updated \(cask.name) to \(cask.currentVersion ?? "latest")"
                    self.loadUpdates()
                } else {
                    lastUpgradeResult = "brew upgrade failed for \(cask.name): \(result.stderr.isEmpty ? "exit \(result.exitCode)" : String(result.stderr.prefix(200)))"
                }
            } catch {
                lastUpgradeResult = "Could not run brew: \(error.localizedDescription)"
            }
        }
    }

    func loadStartupIfNeeded() {
        guard startupPhase == .idle else { return }
        loadStartup()
    }

    func loadStartup() {
        startupPhase = .loading
        Task { [weak self] in
            guard let self else { return }
            // Launch agents are parsed natively — fast and no TCC prompt.
            userAgents = MoleClient.userLaunchAgents()
            systemAgents = MoleClient.systemLaunchAgents()
            // Login items need AppleScript (System Events); may be denied.
            loginItems = await Self.readLoginItems()
            loginItemsUnavailable = loginItems.isEmpty && Self.loginItemsDenied
            startupPhase = .loaded
        }
    }

    private static var loginItemsDenied = false

    /// Reads classic login items via System Events. Automation permission is
    /// requested once; denial is surfaced instead of silently showing empty.
    private static func readLoginItems() async -> [String] {
        let source = """
        tell application "System Events" to get the name of every login item
        """
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                guard let output = osascript(source, error: &error) else {
                    Task { @MainActor in
                        Self.loginItemsDenied = true
                    }
                    continuation.resume(returning: [])
                    return
                }
                let items = output
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                Task { @MainActor in
                    Self.loginItemsDenied = false
                }
                continuation.resume(returning: items)
            }
        }
    }

    private nonisolated static func osascript(_ source: String, error: inout NSDictionary?) -> String? {
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&error)
        return result?.stringValue
    }
}
