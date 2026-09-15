import Foundation

/// Installs the Mole CLI when onboarding detects it missing.
/// Uses Homebrew when available (matching Mole's own recommended path),
/// otherwise the official install script — both are Mole/Homebrew's own
/// tooling, the app does not reimplement installation logic.
@MainActor
final class MoleInstaller: ObservableObject {
    enum InstallPhase: Equatable {
        case idle
        case checking
        case installing
        case installed
        case failed(String)
    }

    struct ProgressLine: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    @Published private(set) var phase: InstallPhase = .idle
    @Published private(set) var outputLines: [ProgressLine] = []
    @Published private(set) var method: Method?

    enum Method: String {
        case homebrew
        case installScript

        var label: String {
            switch self {
            case .homebrew: return "Homebrew"
            case .installScript: return "Official install script"
            }
        }
    }

    private let runner: ProcessRunning
    private var installTask: Task<Void, Never>?

    init(runner: ProcessRunning = FoundationProcessRunner()) {
        self.runner = runner
    }

    var isBusy: Bool { phase == .checking || phase == .installing }

    /// Look for the CLI again after an install attempt.
    func recheck() {
        guard !isBusy else { return }
        phase = MoleLocator().locate() != nil ? .installed : .idle
    }

    /// Installs the CLI via Homebrew if present, else the official script.
    /// Streams live output into `outputLines` for the onboarding UI.
    func install() {
        guard !isBusy else { return }
        outputLines = []
        installTask = Task { [weak self] in
            guard let self else { return }
            phase = .installing
            do {
                if let brew = MoleClient.findBrew() {
                    method = .homebrew
                    append("Using Homebrew: \(brew)")
                    try await runInstaller(brew, ["install", "mole"])
                } else {
                    method = .installScript
                    append("Homebrew not found; using the official install script")
                    // The script pipes to bash; run it through /bin/bash with
                    // a PATH that includes ~/.local/bin for post-install use.
                    try await runInstaller(
                        "/bin/bash",
                        ["-c",
                         "curl -fsSL https://raw.githubusercontent.com/tw93/mole/main/install.sh | bash"],
                        extraPATH: NSString(string: "~/.local/bin").expandingTildeInPath)
                }
                guard !Task.isCancelled else { return }
                // Verify the result rather than trusting the exit code.
                if MoleLocator().locate() != nil {
                    append("✓ Mole CLI installed successfully")
                    phase = .installed
                } else {
                    append("✗ Installer finished but the `mo` binary was not found in PATH")
                    phase = .failed("Install completed but `mo` was not found. Try restarting your terminal or reinstalling.")
                }
            } catch is CancellationError {
                phase = .idle
            } catch {
                append("✗ \(String(describing: error))")
                phase = .failed(String(describing: error))
            }
        }
    }

    func cancel() {
        installTask?.cancel()
        installTask = nil
        phase = .idle
    }

    // MARK: - Execution

    private func runInstaller(_ exe: String, _ args: [String], extraPATH: String? = nil) async throws {
        var env = ProcessEnvironment.base
        if let extraPATH {
            env["PATH"] = extraPATH + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        }
        let stream = runner.streamLines(exe, arguments: args, environment: env)
        for try await line in stream {
            guard !Task.isCancelled else { break }
            append(line)
        }
    }

    private func append(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        outputLines.append(ProgressLine(text: trimmed))
        if outputLines.count > 200 {
            outputLines.removeFirst(outputLines.count - 200)
        }
    }
}
