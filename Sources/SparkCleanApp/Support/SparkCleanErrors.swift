import Foundation

/// User-presentable error carrying what happened, why, and next steps.
struct SparkCleanUserError: Identifiable, Equatable {
    enum Kind: Equatable {
        case cliMissing
        case cliOutdated(current: String, required: String)
        case permissionDenied(path: String)
        case scanFailed(String)
        case partialScan
        case invalidPath(String)
        case volumeDisconnected(String)
        case operationCancelled
        case partiallyCompleted
        case featureUnavailable(String)
        case staleData
        case generic(String)
    }

    var kind: Kind
    var id = UUID()

    var title: String {
        switch kind {
        case .cliMissing: return "Command-line tool not found"
        case .cliOutdated: return "Command-line tool outdated"
        case .permissionDenied: return "Permission denied"
        case .scanFailed: return "Scan failed"
        case .partialScan: return "Scan partially completed"
        case .invalidPath: return "Invalid location"
        case .volumeDisconnected: return "Volume disconnected"
        case .operationCancelled: return "Operation cancelled"
        case .partiallyCompleted: return "Operation partially completed"
        case .featureUnavailable: return "Not available on this Mac"
        case .staleData: return "Monitoring data is stale"
        case .generic: return "Something went wrong"
        }
    }

    var message: String {
        switch kind {
        case .cliMissing:
            return "The command-line tool (`mo`) is not installed or cannot be executed. SparkClean uses it for cleanup operations."
        case .cliOutdated(let current, let required):
            return "Found CLI version \(current); this app needs \(required) or newer for the JSON interfaces it uses."
        case .permissionDenied(let path):
            return "macOS blocked access to \(path)."
        case .scanFailed(let reason):
            return "The scan could not finish: \(reason)"
        case .partialScan:
            return "Some locations were skipped, so results may be incomplete."
        case .invalidPath(let path):
            return "\(path) does not exist or is not readable."
        case .volumeDisconnected(let volume):
            return "\(volume) was disconnected during the operation."
        case .operationCancelled:
            return "The operation was cancelled before finishing. Nothing unexpected was changed."
        case .partiallyCompleted:
            return "The operation finished with some items skipped. Check the skip reasons below."
        case .featureUnavailable(let feature):
            return "\(feature) is not exposed by this hardware or macOS version."
        case .staleData:
            return "The latest process sample is older than the refresh interval, so values below may lag."
        case .generic(let reason):
            return reason
        }
    }

    var recoverySuggestion: String {
        switch kind {
        case .cliMissing:
            return "Install it with `brew install mole`, or set a custom path in Settings → Advanced."
        case .cliOutdated:
            return "Update with `mo update` or `brew upgrade mole`, then reopen SparkClean."
        case .permissionDenied:
            return "Grant Full Disk Access to SparkClean in System Settings → Privacy & Security, then retry."
        case .scanFailed: return "Try again, or run `mo analyze --debug` in Terminal for details."
        case .partialScan: return "Re-run the scan; skipped locations will be retried."
        case .invalidPath: return "Pick a different folder to analyze."
        case .volumeDisconnected: return "Reconnect the volume and retry."
        case .operationCancelled: return "Run the operation again when ready."
        case .partiallyCompleted: return "Review skipped items; add protections with `mo clean --whitelist` if needed."
        case .featureUnavailable: return "No action needed — the rest of the dashboard is unaffected."
        case .staleData: return "If this persists, restart the status collector from the Status screen."
        case .generic: return "Check Settings → Advanced → Open Logs for details."
        }
    }
}

/// Thin logger writing to ~/Library/Logs/SparkCleanApp/app.log for debug sessions.
enum SparkCleanLog {
    static let debug = SparkCleanPreferences.shared.debugLogging

    static func append(_ message: String) {
        guard SparkCleanPreferences.shared.debugLogging else { return }
        let logDir = NSString(string: "~/Library/Logs/SparkCleanApp").expandingTildeInPath
        let logPath = logDir + "/app.log"
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: URL(fileURLWithPath: logPath))
        }
    }
}
