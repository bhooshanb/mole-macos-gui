import Testing
import Foundation
@testable import SparkClean

/// Integration tests against the REAL installed Mole CLI.
/// Every command exercised here is read-only: --version, --list (piped JSON),
/// status --json, history --json, and analyze --json on a tiny directory.
/// No destructive command (clean / uninstall / optimize real runs) is ever
/// executed by the test suite.
@Suite
struct LiveIntegrationTests {
    private static func client() -> SparkCleanClient { SparkCleanClient() }

    @Test func locateAndVersionRealCLI() async throws {
        let client = Self.client()
        let located = try client.locate()
        #expect(FileManager.default.isExecutableFile(atPath: located.url.path))

        let version = await client.version(of: located)
        // Mole prints "Mole version X.Y.Z".
        #expect(version?.lowercased().contains("mole version") == true)
    }

    @Test func appInventoryFromRealCLI() async throws {
        let apps = try await Self.client().appInventory()
        // On a real Mac the inventory may be empty but must decode.
        for app in apps {
            #expect(!app.name.isEmpty)
            #expect(app.path.hasSuffix(".app"))
        }
    }

    @Test func statusSnapshotFromRealCLI() async throws {
        let snapshot = try await Self.client().statusSnapshot()
        #expect(snapshot.collectedAt != Date.distantPast)
        #expect(snapshot.cpu?.logicalCpu ?? 0 > 0)
        #expect(snapshot.memory?.total ?? 0 > 0)
        // Mole omits process fields until the first process sample; never fabricate.
        if snapshot.processStale == nil {
            #expect(snapshot.zombieCount == nil)
        }
    }

    @Test func historyFromRealCLI() async throws {
        let report = try await Self.client().history(limit: 5)
        #expect(report.limit == 5)
        #expect(report.sessions != nil)
        #expect(report.deletions != nil)
    }

    @Test func analyzeTinyDirectoryFromRealCLI() async throws {
        // Analyze a small, safe directory (the system temp dir) instead of the
        // whole machine to keep the test fast. Mole reports the resolved path
        // without a trailing slash.
        let tiny = NSTemporaryDirectory()
        let report = try await Self.client().analyze(path: tiny)
        #expect(report.path == (tiny as NSString).standardizingPath)
        #expect(report.overview == false)
        #expect(report.totalSize >= 0)
    }

    @Test func analyzeExpandsTildePaths() async throws {
        // Regression: Mole resolves paths literally, so the app must expand
        // tilde paths before invoking `mo analyze --json`.
        let home = NSHomeDirectory()
        let report = try await Self.client().analyze(path: "~")
        #expect(report.path == home)
        #expect(report.overview == false)
    }

    @Test func statusWatchStreamEmitsSnapshots() async throws {
        let client = Self.client()
        let stream = try client.statusWatch(interval: "1s")
        var received = 0
        for try await snapshot in stream {
            #expect(snapshot.collectedAt != Date.distantPast)
            received += 1
            if received >= 2 { break }
        }
        #expect(received >= 2)
    }
}
