import Testing
import Foundation
@testable import SparkClean

@Suite
struct TreemapLayoutTests {
    private func node(_ name: String, _ size: Int64) -> AnalyzeNode {
        AnalyzeNode(
            name: name, path: "/tmp/\(name)", size: size, isDir: true,
            insight: false, cleanable: false, lastAccess: nil, parentPath: nil)
    }

    @Test func tilesStayInsideBounds() {
        let entries = [
            node("A", 500), node("B", 300), node("C", 150),
            node("D", 40), node("E", 10),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let tiles = TreemapLayout.squarify(entries: entries, in: bounds)
        #expect(tiles.count == 5)
        for tile in tiles {
            #expect(bounds.contains(tile.rect))
        }
    }

    @Test func emptyAndZeroInputs() {
        #expect(TreemapLayout.squarify(entries: [], in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
        #expect(TreemapLayout.squarify(entries: [node("A", 0)], in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
        #expect(TreemapLayout.squarify(entries: [node("A", 10)], in: CGRect(x: 0, y: 0, width: 0, height: 0)).isEmpty)
    }

    @Test func worstAspectRatio() {
        let square = TreemapLayout.worstAspect(rowArea: 100, side: 10, count: 1)
        #expect(abs(square - 1) < 0.001)
        #expect(TreemapLayout.worstAspect(rowArea: 0, side: 10, count: 1) == .infinity)
    }

    @Test func largestItemGetsLargestTile() {
        let entries = [node("Big", 900), node("Small", 100)]
        let tiles = TreemapLayout.squarify(entries: entries, in: CGRect(x: 0, y: 0, width: 500, height: 500))
        #expect(tiles.count == 2)
        let big = tiles.first { $0.node.name == "Big" }!
        let small = tiles.first { $0.node.name == "Small" }!
        #expect(big.rect.width * big.rect.height > small.rect.width * small.rect.height)
        let totalArea = big.rect.width * big.rect.height + small.rect.width * small.rect.height
        let bigShare = big.rect.width * big.rect.height / totalArea
        #expect(abs(bigShare - 0.9) < 0.05)
    }
}

@Suite
struct SparkCleanLocatorTests {
    @Test func locatorFindsAnExecutableWhenInstalled() {
        let locator = SparkCleanLocator(customPath: nil)
        if let result = locator.locate() {
            #expect(FileManager.default.isExecutableFile(atPath: result.url.path))
        }
        #expect(SparkCleanLocator.wellKnownPaths.contains("/usr/local/bin/mo"))
        #expect(SparkCleanLocator.wellKnownPaths.contains("/opt/homebrew/bin/mo"))
    }

    @Test func firstJSONArrayExtraction() {
        // Mole emits any warnings first and ends output with the JSON body.
        let mixed = "warning text\n" + "[{\"a\": 1}]"
        let data = SparkCleanClient.firstJSONArray(in: mixed)
        #expect(data != nil)
        if let data {
            #expect((try? JSONSerialization.jsonObject(with: data)) != nil)
        }
    }
}

@Suite
struct CleanPreviewListTests {
    @Test func parsePreviewListFormat() throws {
        let content = """
        # Mole Cleanup Preview - 2026-09-15
        # How to protect files:
        #   /Users/*/Library/Caches/com.example.app

        /private/var/log/old.asl  # 1.9MB
        /Users/x/Library/Caches/thing  # size unknown
        """
        let paths = content.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            return trimmed.components(separatedBy: "  # ").first.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        #expect(paths == ["/private/var/log/old.asl", "/Users/x/Library/Caches/thing"])
    }
}

@Suite
struct SparkCleanUserErrorTests {
    @Test func errorTitlesAndRecovery() {
        let missing = SparkCleanUserError(kind: .cliMissing)
        #expect(missing.title == "Command-line tool not found")
        #expect(missing.recoverySuggestion.contains("brew install mole"))

        let permission = SparkCleanUserError(kind: .permissionDenied(path: "/private/var"))
        #expect(permission.message.contains("/private/var"))
        #expect(permission.recoverySuggestion.contains("Full Disk Access"))

        let stale = SparkCleanUserError(kind: .staleData)
        #expect(!stale.message.isEmpty)
    }

    @Test func equality() {
        #expect(SparkCleanUserError(kind: .cliMissing).kind == SparkCleanUserError(kind: .cliMissing).kind)
        #expect(SparkCleanUserError(kind: .cliMissing).kind != SparkCleanUserError(kind: .staleData).kind)
    }
}
