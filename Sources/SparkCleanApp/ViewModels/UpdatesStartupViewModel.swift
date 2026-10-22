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
    @Published var loginItems: [LoginItemInfo] = []
    @Published var loginItemsUnavailable = false
    @Published var loginItemsErrorCode = 0

    enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    private let client: SparkCleanClient
    private var upgradeTasks: [String: Task<Void, Never>] = [:]

    init(client: SparkCleanClient) {
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
            guard SparkCleanClient.findBrew() != nil else {
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

    /// `brew upgrade --cask <name>` with the CLI stream shown live in a
    /// popup sheet. The sheet binding is provided by the caller.
    func upgradeWithStream(_ cask: HomebrewCaskUpdate, showSheet: @escaping () -> Void) {
        guard upgradeTasks[cask.name] == nil else { return }
        upgradingCask = cask.name
        upgradeLog = []
        upgradeCaskName = cask.name
        upgradeFinished = false
        upgradeExitCode = nil
        showSheet()
        upgradeTasks[cask.name] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.upgradeTasks[cask.name] = nil
                self.upgradingCask = nil
            }
            do {
                let stream = try client.upgradeCaskStream(named: cask.name)
                for try await line in stream {
                    appendUpgradeLog(line)
                }
                // streamLines finishes with a nonZeroExit throw on failure;
                // reaching here means exit 0 (or clean termination).
                await MainActor.run {
                    self.upgradeExitCode = 0
                    self.upgradeFinished = true
                    SparkCleanPreferences.shared.cleanWatchOptimizeCount += 1
                    self.loadUpdates()
                }
            } catch ProcessError.nonZeroExit(let code, _) {
                await MainActor.run {
                    self.upgradeExitCode = Int(code)
                    self.upgradeFinished = true
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.upgradeExitCode = nil
                    self.upgradeFinished = true
                }
            } catch {
                appendUpgradeLog("✗ \(error.localizedDescription)")
                await MainActor.run {
                    self.upgradeExitCode = -1
                    self.upgradeFinished = true
                }
            }
        }
    }

    @Published var upgradeLog: [String] = []
    @Published var upgradeCaskName: String?
    @Published var upgradeFinished = false
    @Published var upgradeExitCode: Int?

    private func appendUpgradeLog(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.upgradeLog.append(trimmed)
            if self.upgradeLog.count > 500 {
                self.upgradeLog.removeFirst(self.upgradeLog.count - 500)
            }
        }
    }

    /// Cancel the running upgrade from the sheet.
    func cancelUpgrade() {
        if let name = upgradeCaskName {
            upgradeTasks[name]?.cancel()
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
            userAgents = SparkCleanClient.userLaunchAgents()
            systemAgents = SparkCleanClient.systemLaunchAgents()
            // Login items need AppleScript (System Events); may be denied.
            loginItems = await Self.readLoginItems()
            loginItemsUnavailable = loginItems.isEmpty && Self.loginItemsDenied
            loginItemsErrorCode = Self.loginItemsErrorCode
            startupPhase = .loaded
        }
    }

    private static var loginItemsDenied = false

    /// Reads classic login items (name + app path) via System Events.
    /// Requires NSAppleEventsUsageDescription in Info.plist; without it macOS
    /// denies the Apple Event silently with error -1743.
    private static func readLoginItems() async -> [LoginItemInfo] {
        let source = """
        tell application "System Events"
            get {name, path} of every login item
        end tell
        """
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                guard let output = osascript(source, error: &error) else {
                    // AppleScript error dict key "OSAErrorNumber"; -1743 = user
                    // / system denied the Apple Event.
                    let code = (error?["OSAErrorNumber"] as? Int) ?? 0
                    Task { @MainActor in
                        Self.loginItemsDenied = true
                        Self.loginItemsErrorCode = code
                    }
                    continuation.resume(returning: [])
                    return
                }
                // Output is a flat list: name1, name2, …, path1, path2, …
                let parts = output
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let count = parts.count / 2
                let names = Array(parts.prefix(count))
                let paths = Array(parts.suffix(count))
                let items = (0..<count).map { i in
                    LoginItemInfo(name: names[i], path: paths[i])
                }
                Task { @MainActor in
                    Self.loginItemsDenied = false
                }
                continuation.resume(returning: items)
            }
        }
    }

    private static var loginItemsErrorCode = 0

    private nonisolated static func osascript(_ source: String, error: inout NSDictionary?) -> String? {
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&error)
        return result?.stringValue
    }
}
