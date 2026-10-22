import Foundation

/// Describes where the `mo` CLI was found and how recent it is.
struct SparkCleanLocatorResult: Equatable, Sendable {
    var url: URL
    var version: String?
    var source: DiscoverySource

    enum DiscoverySource: String, Equatable, Sendable {
        case appBundleOverride = "app-bundle-override"
        case bundled = "bundled"
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

/// Locates the real `mo` executable.
/// Order: explicit user override → bundled copy → well-known install paths →
/// repository checkout → user PATH.
struct SparkCleanLocator {
    /// Override set from Settings (Advanced → Mole CLI path).
    var customPath: String?

    /// Bundled fallback: a copy of `mo` (with its bin/ + lib/ trees) placed in
    /// SparkClean.app/Contents/Resources/mole-cli. Optional; the installed CLI is the
    /// primary integration target.
    var bundledCLIResourceURL: URL? = {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let candidate = resources.appendingPathComponent("mole-cli/mole")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }()

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

        // 2. Bundled copy.
        if let bundledCLIResourceURL {
            return SparkCleanLocatorResult(
                url: bundledCLIResourceURL, version: nil, source: .bundled)
        }

        // 3. Well-known locations.
        for path in Self.wellKnownPaths where FileManager.default.isExecutableFile(atPath: path) {
            return SparkCleanLocatorResult(
                url: URL(fileURLWithPath: path), version: nil, source: .init(rawValue: path) ?? .path)
        }

        // 4. Repository checkout (development).
        let devCandidates = [
            NSString(string: "~/Documents/molemac/mole-cli/mole").expandingTildeInPath,
            NSString(string: "~/Mole/mole").expandingTildeInPath,
            NSString(string: "~/Projects/Mole/mole").expandingTildeInPath,
        ]
        for path in devCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return SparkCleanLocatorResult(
                url: URL(fileURLWithPath: path), version: nil, source: .repositoryCheckout)
        }

        // 5. PATH lookup.
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
