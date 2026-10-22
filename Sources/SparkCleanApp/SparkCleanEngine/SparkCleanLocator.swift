import Foundation

/// Describes where the `mo` CLI was found and how recent it is.
struct SparkCleanLocatorResult: Equatable, Sendable {
    var url: URL
    var version: String?
    var source: DiscoverySource

    enum DiscoverySource: String, Equatable, Sendable {
        case appBundleOverride = "app-bundle-override"
        case usrLocalBin = "/usr/local/bin"
        case optHomebrewBin = "/opt/homebrew/bin"
        case localBin = "~/.local/bin"
        case path = "PATH"
        case repositoryCheckout = "repository-checkout"
    }
}

enum SparkCleanLocatorError: Error, Equatable {
    case notFound
}

/// Locates the real `mo` executable. The app never bundles the CLI; it relies
/// on a Homebrew (or other) installation.
/// Order: explicit user override → Homebrew/known install paths →
/// repository checkout → user PATH.
struct SparkCleanLocator {
    /// Override set from Settings (Advanced → Mole CLI path).
    var customPath: String?

    static let wellKnownPaths: [String] = [
        "/usr/local/bin/mo",
        "/opt/homebrew/bin/mo",
        NSString(string: "~/.local/bin/mo").expandingTildeInPath,
    ]

    func locate() -> SparkCleanLocatorResult? {
        // 1. User override always wins.
        if let customPath, !customPath.isEmpty {
            let expanded = NSString(string: customPath).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return SparkCleanLocatorResult(
                    url: URL(fileURLWithPath: expanded), version: nil,
                    source: .appBundleOverride)
            }
        }

        // 2. Well-known locations (Homebrew's /usr/local and /opt/homebrew first).
        for path in Self.wellKnownPaths where FileManager.default.isExecutableFile(atPath: path) {
            return SparkCleanLocatorResult(
                url: URL(fileURLWithPath: path), version: nil, source: .init(rawValue: path) ?? .path)
        }

        // 3. Repository checkout (development).
        let devCandidates = [
            NSString(string: "~/Documents/molemac/mole-cli/mole").expandingTildeInPath,
            NSString(string: "~/Mole/mole").expandingTildeInPath,
            NSString(string: "~/Projects/Mole/mole").expandingTildeInPath,
        ]
        for path in devCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return SparkCleanLocatorResult(
                url: URL(fileURLWithPath: path), version: nil, source: .repositoryCheckout)
        }

        // 4. PATH lookup.
        if let fromPATH = Self.findInPATH() {
            return SparkCleanLocatorResult(url: fromPATH, version: nil, source: .path)
        }

        return nil
    }

    static func findInPATH() -> URL? {
        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let candidates = ["/usr/local/bin", "/opt/homebrew/bin",
                          NSString(string: "~/.local/bin").expandingTildeInPath] + searchPaths
        for dir in candidates {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent("mo")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
