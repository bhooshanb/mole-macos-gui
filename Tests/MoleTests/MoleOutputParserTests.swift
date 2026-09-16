import Testing
import Foundation
@testable import Mole

@Suite
struct MoleOutputParserTests {
    // Real dry-run output shape from CLI 1.53.
    @Test func cleanDryRunParsing() {
        let output = """
        Clean Your Mac

        Dry Run Mode, Preview only, no deletions

        \u{1B}[36m⚙\u{1B}[0m Apple Silicon | Free space: 34.48GB
        ➤ User essentials
          → User app cache · 20 items, 15.46GB dry
          → User app logs · 18 items, 15.4MB dry
          → Trash · would empty, 33 items

        ➤ App caches
          → Siri suggestions cache · 10 items, 123KB dry
          → Maps geo tile cache · 5 items, 57.7MB dry

        ➤ Browsers
          → Chrome cache · 1.10GB dry

        ➤ Cloud & Office
          ✓ Nothing to clean

        ======================================================================
        Dry run complete - no changes made
        Potential space: 16.72GB | Items: 86 | Categories: 7
        Free space: 34.48GB
        ======================================================================
        """
        let summary = CleanOutputParser.parse(output, dryRun: true)
        #expect(summary.dryRun)
        #expect(summary.sectionOrder == ["User essentials", "App caches", "Browsers", "Cloud & Office"])
        #expect(summary.items.contains { $0.name == "User app cache" && $0.itemCount == 20 })
        #expect(summary.items.contains { $0.name == "Chrome cache" })
        #expect(!summary.items.contains { $0.name == "Nothing to clean" })
        // The parser takes the largest size mention; the CLI's own summary
        // line "Potential space: 16.72GB" is the largest and most accurate.
        #expect(summary.totalBytes == 17_952_963_297)
        #expect(summary.items.allSatisfy { !$0.skipped })
    }

    @Test func cleanRealRunParsingWithSkips() {
        let output = """
        ➤ Developer tools
          ✓ npm cache · cleaned
          ◎ pnpm cache · skipped (pnpm busy)
          ✓ Xcode runtime volumes · removed 2, 3 in use

        ======================================================================
        Cleanup complete
        Tracked cleanup: 4.5GB | Items cleaned: 97 | Categories: 4
        ======================================================================
        """
        let summary = CleanOutputParser.parse(output, dryRun: false)
        #expect(!summary.dryRun)
        let skipped = summary.items.filter(\.skipped)
        #expect(skipped.count == 1)
        #expect(skipped.first?.skipReason == "pnpm busy")
        #expect(summary.totalBytes == Int64(4.5 * Double(1024 * 1024 * 1024)))
    }

    @Test func cleanSizeParsing() {
        #expect(CleanOutputParser.parseSizeBytes(from: "15.46GB dry") == 16_600_048_599)
        #expect(CleanOutputParser.parseSizeBytes(from: "123KB dry") == 125_952)
        #expect(CleanOutputParser.parseSizeBytes(from: "12.8MB") == 13_421_772)
        #expect(CleanOutputParser.parseSizeBytes(from: "no size here") == nil)
    }

    @Test func itemCountParsing() {
        #expect(CleanOutputParser.parseItemCount(from: "20 items, 15.46GB") == 20)
        #expect(CleanOutputParser.parseItemCount(from: "1 item") == 1)
        #expect(CleanOutputParser.parseItemCount(from: "cleaned") == nil)
    }

    // Real uninstall dry-run output from CLI 1.53.
    @Test func uninstallPlanParsing() {
        let output = """
        → DRY RUN MODE, No app files or settings will be modified

        ◎ Matched 1 app(s):
        1. RAV FileHub  80.4MB  |  Last: 2y ago

        Files to be removed:

        ◎ RAV FileHub , 80.4MB
          ✓ /Applications/RAV FileHub.app , 80.4MB

        ➤ Remove 1 app, 80.4MB  Enter confirm, ESC cancel:

        ======================================================================
        Uninstall dry run complete
        Would remove 1 app, would free 80.4MB: RAV FileHub
        ======================================================================

        [DRY RUN] Would refresh LaunchServices and update Dock entries
        """
        let plan = UninstallOutputParser.parse(output, appName: "RAV FileHub", dryRun: true)
        #expect(plan.dryRun)
        #expect(plan.files.count == 1)
        #expect(plan.files.first?.path == "/Applications/RAV FileHub.app")
        #expect(plan.files.first?.size == "80.4MB")
        #expect(plan.totalSize == "80.4MB")
        #expect(plan.summaryLine?.contains("Would remove 1 app") == true)
    }

    @Test func uninstallMultiFilePlan() {
        let output = """
        Files to be removed:
        ◎ Photoshop 2024, 12.80GB
          ✓ /Applications/Adobe Photoshop 2024/Adobe Photoshop 2024.app , 4.20GB
          ✓ ~/Library/Application Support/Adobe/Adobe Photoshop 2024 , 8.60GB
          ✓ ~/Library/Preferences/com.adobe.Photoshop.plist , 12KB
        ➤ Remove 3 files, 12.80GB  Enter confirm, ESC cancel:
        """
        let plan = UninstallOutputParser.parse(output, appName: "Photoshop 2024", dryRun: false)
        #expect(plan.files.count == 3)
        #expect(plan.files[1].path == "~/Library/Application Support/Adobe/Adobe Photoshop 2024")
    }

    // Real optimize output shape from CLI 1.53.
    @Test func optimizeParsing() {
        let output = """
        Optimize

        ⚙ System  18/32 GB RAM | 616/926 GB Disk | Uptime 6d

        ➤ DNS & Spotlight Check
          → DNS cache flushed
          → Spotlight index verified

        ➤ Finder Cache Refresh
          → QuickLook thumbnails refreshed
          → Icon services cache rebuilt

        ➤ Database Optimization
          ◎ Close these apps before database optimization: Safari

        ➤ Disk Health
          → Disk verify skipped (set MOLE_ENABLE_DISK_VERIFY=1 to enable)

        ======================================================================
        Optimization Complete
        Applied 3 optimizations
        14 unchanged | 3 skipped | 1 unavailable
        ======================================================================
        """
        let summary = OptimizeOutputParser.parse(output, dryRun: false)
        #expect(!summary.dryRun)
        #expect(summary.systemLine == "System  18/32 GB RAM | 616/926 GB Disk | Uptime 6d")
        #expect(summary.tasks.contains { $0.detail == "DNS cache flushed" && $0.outcome == .applied })
        #expect(summary.tasks.contains { task in
            if case .unavailable(let reason) = task.outcome {
                return reason?.contains("MOLE_ENABLE_DISK_VERIFY") == true
            }
            return false
        })
        // 3 applied in "DNS & Spotlight" + "Finder Cache Refresh" and the
        // Disk Health row parses as unavailable rather than applied.
        #expect(summary.appliedCount >= 3)
    }

    @Test func optimizeDryRunParsing() {
        let output = """
        ⚙ System  8/16 GB RAM | 200/500 GB Disk | Uptime 2d
        ➤ Network Cache Refresh
          → mDNSResponder restart skipped in dry-run
        ======================================================================
        Dry Run Complete, No Changes Made
        Would apply 5 optimizations
        ======================================================================
        """
        let summary = OptimizeOutputParser.parse(output, dryRun: true)
        #expect(summary.dryRun)
    }

    /// Regression: Mole exits 1 when any task fails, even in dry-run, while
    /// still printing a complete report. The app must parse that as a valid
    /// summary (with the failed outcome) rather than surfacing it as an error.
    @Test func optimizeDryRunWithFailedTaskStillParses() {
        let output = """
        ⚙ System  8/16 GB RAM | 200/500 GB Disk | Uptime 2d
        ➤ Network Cache Refresh
          → DNS cache flushed                       (applied)
        ➤ Spotlight Rebuild
          ☻ mdfind check failed                     (failed: command not available)
        ======================================================================
        Dry Run Complete, No Changes Made
        Would apply 3 optimizations | 1 failed
        ======================================================================
        """
        let summary = OptimizeOutputParser.parse(output, dryRun: true)
        #expect(summary.dryRun)
        #expect(!summary.tasks.isEmpty)
        #expect(summary.failedCount >= 1)
    }

    /// A broken run (no task lines at all, e.g. missing `bc` dependency) must
    /// NOT parse as an empty success — callers detect this via tasks.isEmpty
    /// plus exit code and surface a real error.
    @Test func optimizeBrokenRunYieldsNoTasks() {
        let output = """
        ⚙ Header only
        Missing dependency: bc
        """
        let summary = OptimizeOutputParser.parse(output, dryRun: true)
        #expect(summary.tasks.isEmpty)
    }

    @Test func ansiStripping() {
        let colored = "\u{1B}[32m✓\u{1B}[0m done"
        #expect(!CleanOutputParser.stripANSI(colored).contains("\u{1B}"))
    }
}
