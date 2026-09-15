import Foundation

/// Typed client over the real `mo` CLI.
/// Every destructive capability maps 1:1 to a Mole command; the app never
/// invents deletion logic of its own.
struct MoleClient: Sendable {
    let runner: ProcessRunning
    var locator: MoleLocator

    init(runner: ProcessRunning = FoundationProcessRunner(),
         locator: MoleLocator = MoleLocator()) {
        self.runner = runner
        self.locator = locator
    }

    /// Current locator reflecting the user's CLI path override from Settings.
    var effectiveLocator: MoleLocator {
        var copy = locator
        let override = MolePreferences.shared.cliPathOverride
        copy.customPath = override.isEmpty ? nil : override
        return copy
    }

    enum MoleClientError: Error, Equatable {
        case cliNotFound
        case invalidOutput(String)
        case unsupported(String)
    }

    // MARK: - Discovery

    func locate() throws -> MoleLocatorResult {
        guard let found = effectiveLocator.locate() else { throw MoleClientError.cliNotFound }
        return found
    }

    /// Fetch `mo --version` output, e.g. "Mole version 1.53.0".
    func version(of found: MoleLocatorResult? = nil) async -> String? {
        let target = found ?? locator.locate()
        guard let mo = target?.url.path else { return nil }
        guard let result = try? await runner.run(mo, arguments: ["--version"], timeout: 15) else {
            return nil
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Clean

    /// `mo clean --dry-run` — previews candidates and writes them to
    /// ~/.config/mole/clean-list.txt. Non-destructive.
    func cleanDryRun() async throws -> CleanSummary {
        let mo = try locate().url.path
        let result = try await runner.run(mo, arguments: ["clean", "--dry-run"], timeout: 15 * 60)
        guard result.succeeded else {
            throw MoleClientError.invalidOutput(stderrSummary(result))
        }
        let parsed = CleanOutputParser.parse(result.stdout, dryRun: true)
        // Enrich with the per-path preview list the CLI writes alongside.
        if parsed.paths.isEmpty, let paths = Self.readCleanPreviewList() {
            var summary = parsed
            summary.paths = paths
            return summary
        }
        return parsed
    }

    /// `mo clean` — real cleanup. The CLI validates, protects, whitelists, and
    /// logs every deletion itself; the app only presents the outcome.
    func clean() async throws -> CleanSummary {
        let mo = try locate().url.path
        let result = try await runner.run(mo, arguments: ["clean"], timeout: 30 * 60)
        guard result.succeeded else {
            throw MoleClientError.invalidOutput(stderrSummary(result))
        }
        return CleanOutputParser.parse(result.stdout, dryRun: false)
    }

    /// Manage the clean whitelist: returns the current rules.
    func readWhitelist() -> [String] {
        let path = NSString(string: "~/.config/mole/whitelist").expandingTildeInPath
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Append rules to ~/.config/mole/whitelist (Mole's own protection file).
    func addToWhitelist(_ patterns: [String]) throws {
        let path = NSString(string: "~/.config/mole/whitelist").expandingTildeInPath
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let existing = Set(readWhitelist())
        let additions = patterns.filter { !existing.contains($0) }
        guard !additions.isEmpty else { return }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seekToEnd()
        let blob = Data(("\n" + additions.joined(separator: "\n") + "\n").utf8)
        try handle.write(contentsOf: blob)
    }

    // MARK: - Uninstall

    /// `mo uninstall --list` piped → JSON inventory.
    func appInventory() async throws -> [AppInventoryItem] {
        let mo = try locate().url.path
        let result = try await runner.run(mo, arguments: ["uninstall", "--list"], timeout: 5 * 60)
        guard result.succeeded else {
            throw MoleClientError.invalidOutput(stderrSummary(result))
        }
        guard let data = Self.firstJSONArray(in: result.stdout) else {
            if result.stdout.contains("No applications found") { return [] }
            throw MoleClientError.invalidOutput("uninstall --list did not return JSON")
        }
        return try MoleJSON.decode([AppInventoryItem].self, from: data)
    }

    /// `mo uninstall <name> --dry-run` — the real per-app file plan.
    /// The plan text is parsed from the CLI's own output; nothing is invented.
    func uninstallPlan(app: AppInventoryItem) async throws -> UninstallPlan {
        let mo = try locate().url.path
        let result = try await runner.runWithStdin(
            mo,
            arguments: ["uninstall", app.uninstallName, "--dry-run"],
            stdin: Data("y\n".utf8),
            timeout: 10 * 60)
        guard result.succeeded else {
            throw MoleClientError.invalidOutput(stderrSummary(result))
        }
        return UninstallOutputParser.parse(
            result.stdout, appName: app.name, dryRun: true)
    }

    /// `mo uninstall <name>` — real uninstall through Mole (Trash by default).
    /// Mole asks two interactive confirmations; both are answered "y" because
    /// the app has already shown the plan and required explicit user consent.
    func uninstall(app: AppInventoryItem) async throws -> UninstallPlan {
        let mo = try locate().url.path
        let result = try await runner.runWithStdin(
            mo,
            arguments: ["uninstall", app.uninstallName],
            stdin: Data("y\n".utf8),
            timeout: 15 * 60)
        guard result.succeeded else {
            throw MoleClientError.invalidOutput(stderrSummary(result))
        }
        return UninstallOutputParser.parse(result.stdout, appName: app.name, dryRun: false)
    }

    // MARK: - Optimize

    /// `mo optimize --dry-run` — expand the task list without changes.
    func optimizeDryRun() async throws -> OptimizeSummary {
        let mo = try locate().url.path
        let result = try await runner.run(mo, arguments: ["optimize", "--dry-run"], timeout: 15 * 60)
        guard result.succeeded else {
            throw MoleClientError.invalidOutput(stderrSummary(result))
        }
        return OptimizeOutputParser.parse(result.stdout, dryRun: true)
    }

    /// `mo optimize` — run maintenance. Sudo-needed tasks are skipped by the
    /// CLI itself when it cannot prompt; the app surfaces those skips.
    func optimize() async throws -> OptimizeSummary {
        let mo = try locate().url.path
        let result = try await runner.run(mo, arguments: ["optimize"], timeout: 30 * 60)
        guard result.succeeded else {
            throw MoleClientError.invalidOutput(stderrSummary(result))
        }
        return OptimizeOutputParser.parse(result.stdout, dryRun: false)
    }

    // MARK: - Analyze

    /// `mo analyze --json [path]` — the flag must precede the path.
    /// Tilde paths are expanded because Mole resolves paths literally.
    func analyze(path: String?) async throws -> AnalyzeReport {
        let mo = try locate().url.path
        var arguments = ["analyze", "--json"]
        if let path, !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            arguments.append(expanded)
        }
        let result = try await runner.run(mo, arguments: arguments, timeout: 20 * 60)
        guard result.succeeded else {
            throw MoleClientError.invalidOutput(stderrSummary(result))
        }
        if let report = try? MoleJSON.decode(AnalyzeReport.self, from: result.outputData) {
            return report
        }
        // Mole's analyze exits 0 even when the scan fails (e.g. missing path),
        // so a decode failure with stderr text means the scan itself failed.
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            throw MoleClientError.invalidOutput(stderr)
        }
        throw MoleClientError.invalidOutput("analyze did not return valid JSON")
    }

    // MARK: - Status

    /// One-shot snapshot: `mo status --json`.
    func statusSnapshot() async throws -> MetricsSnapshot {
        let mo = try locate().url.path
        let result = try await runner.run(mo, arguments: ["status", "--json"], timeout: 60)
        guard result.succeeded else {
            throw MoleClientError.invalidOutput(stderrSummary(result))
        }
        guard let snapshot = try? MoleJSON.decode(MetricsSnapshot.self, from: result.outputData) else {
            throw MoleClientError.invalidOutput("status did not return valid JSON")
        }
        return snapshot
    }

    /// NDJSON stream from the CLI's warm collector: `mo status --watch`.
    func statusWatch(interval: String = "2s") throws -> AsyncThrowingStream<MetricsSnapshot, Error> {
        let mo = try locate().url.path
        let stream = runner.streamLines(mo, arguments: ["status", "--watch", "--interval", interval])
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in stream {
                        if Task.isCancelled { break }
                        guard !line.isEmpty else { continue }
                        if let snapshot = try? MoleJSON.decode(MetricsSnapshot.self, from: Data(line.utf8)) {
                            continuation.yield(snapshot)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - History

    /// `mo history --json --limit N`.
    func history(limit: Int = 50) async throws -> HistoryReport {
        let mo = try locate().url.path
        let clampedLimit = max(1, min(limit, 200))
        let result = try await runner.run(
            mo, arguments: ["history", "--json", "--limit", "\(clampedLimit)"], timeout: 60)
        guard result.succeeded else {
            throw MoleClientError.invalidOutput(stderrSummary(result))
        }
        return try MoleJSON.decode(HistoryReport.self, from: result.outputData)
    }

    // MARK: - Homebrew updates
    // Mole delegates cask updates to Homebrew; surface the same source of truth.

    /// Casks with available updates via `brew outdated --cask --json=v2`.
    /// HOMEBREW_NO_AUTO_UPDATE keeps brew from refreshing its whole catalog
    /// (the classic multi-minute hang inside GUI apps).
    func outdatedCasks() async throws -> [HomebrewCaskUpdate] {
        guard let brew = Self.findBrew() else { return [] }
        let result = try await runner.run(
            brew, arguments: ["outdated", "--cask", "--json=v2"],
            workingDirectory: nil, timeout: 120,
            environment: ["HOMEBREW_NO_AUTO_UPDATE": "1"])
        guard result.succeeded else {
            throw MoleClientError.invalidOutput(stderrSummary(result))
        }
        guard let report = try? MoleJSON.decode(HomebrewOutdatedReport.self, from: result.outputData) else {
            throw MoleClientError.invalidOutput("brew outdated returned unparseable JSON")
        }
        return report.casks ?? []
    }

    /// All installed casks (name + version) for context in the Updates pane.
    func installedCasks() async throws -> [String] {
        guard let brew = Self.findBrew() else { return [] }
        let result = try await runner.run(
            brew, arguments: ["list", "--cask"],
            workingDirectory: nil, timeout: 60,
            environment: ["HOMEBREW_NO_AUTO_UPDATE": "1"])
        guard result.succeeded else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// `brew upgrade --cask <name>`; runs Homebrew itself, no reimplementation.
    /// HOMEBREW_NO_AUTO_UPDATE avoids the long catalog refresh that otherwise
    /// stalls GUI-invoked brew runs.
    func upgradeCask(named name: String) async throws -> ProcessResult {
        guard let brew = Self.findBrew() else {
            throw MoleClientError.cliNotFound
        }
        return try await runner.run(
            brew, arguments: ["upgrade", "--cask", name],
            workingDirectory: nil, timeout: 30 * 60,
            environment: ["HOMEBREW_NO_AUTO_UPDATE": "1"])
    }

    /// Streaming variant: yields brew's stdout/stderr lines live while the
    /// upgrade runs, so the UI can show the real CLI output. Returns the exit
    /// status; environment mirrors upgradeCask.
    func upgradeCaskStream(named name: String) throws -> AsyncThrowingStream<String, Error> {
        guard let brew = Self.findBrew() else {
            throw MoleClientError.cliNotFound
        }
        return runner.streamLines(
            brew, arguments: ["upgrade", "--cask", name],
            environment: ["HOMEBREW_NO_AUTO_UPDATE": "1"])
    }

    /// Locate the brew executable without shelling out to a login shell.
    static func findBrew() -> String? {
        let candidates = [
            "/opt/homebrew/bin/brew", // Apple Silicon
            "/usr/local/bin/brew", // Intel
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Startup (launch agents)

    /// User launch agents: parsed plists from ~/Library/LaunchAgents.
    static func userLaunchAgents() -> [LaunchAgentInfo] {
        let dir = NSString(string: "~/Library/LaunchAgents").expandingTildeInPath
        return launchAgents(inDirectory: dir)
    }

    /// Third-party system daemons (/Library/LaunchDaemons) are shown read-only
    /// with a note; they require administrator rights to modify.
    static func systemLaunchAgents() -> [LaunchAgentInfo] {
        return launchAgents(inDirectory: "/Library/LaunchAgents")
    }

    private static func launchAgents(inDirectory dir: String) -> [LaunchAgentInfo] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        return files
            .filter { $0.hasSuffix(".plist") }
            .sorted()
            .compactMap { file -> LaunchAgentInfo? in
                let path = dir + "/" + file
                guard let data = fm.contents(atPath: path),
                      let plist = try? PropertyListSerialization.propertyList(
                        from: data, options: [], format: nil) as? [String: Any]
                else {
                    return LaunchAgentInfo(path: path, label: (file as NSString).deletingPathExtension,
                                           program: nil, disabled: false)
                }
                let label = (plist["Label"] as? String) ?? (file as NSString).deletingPathExtension
                let program = (plist["Program"] as? String)
                    ?? ((plist["ProgramArguments"] as? [String])?.first)
                let disabled = (plist["Disabled"] as? Bool) ?? false
                return LaunchAgentInfo(path: path, label: label, program: program, disabled: disabled)
            }
    }

    // MARK: - Helpers

    private func stderrSummary(_ result: ProcessResult) -> String {
        let text = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return String(text.prefix(400)) }
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? "Mole exited with code \(result.exitCode)" : String(out.prefix(400))
    }

    /// Extract the first JSON array or object from mixed output.
    static func firstJSONArray(in text: String) -> Data? {
        guard let start = text.firstIndex(where: { $0 == "[" || $0 == "{" }) else { return nil }
        return Data(String(text[start...]).utf8)
    }

    /// Read the dry-run preview list Mole writes to ~/.config/mole/clean-list.txt.
    /// Format: "path  # size" lines after the comment header.
    static func readCleanPreviewList() -> [String]? {
        let path = NSString(string: "~/.config/mole/clean-list.txt").expandingTildeInPath
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let paths = raw.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            return trimmed.components(separatedBy: "  # ").first.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return paths
    }
}
