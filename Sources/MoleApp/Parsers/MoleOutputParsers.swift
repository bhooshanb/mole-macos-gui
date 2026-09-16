import Foundation

// MARK: - Clean

/// One cleanup row as reported by `mo clean` / `mo clean --dry-run`.
struct CleanCategoryItem: Equatable, Identifiable, Sendable {
    var id: String { name }
    var name: String
    var section: String
    var detail: String
    var estimatedBytes: Int64?
    var itemCount: Int?
    var skipped: Bool
    var skipReason: String?
}

struct CleanSummary: Equatable, Sendable {
    var dryRun: Bool
    var sectionOrder: [String]
    var items: [CleanCategoryItem]
    var totalBytes: Int64?
    var itemCount: Int
    var categoryCount: Int
    var cancelled: Bool
    var paths: [String] = []
    var freeSpace: String?
    var headLine: String?

    var selectedBytes: Int64? { totalBytes }
}

enum CleanOutputParser {
    /// Parse `mo clean` / `mo clean --dry-run` output.
    /// Shape (verified against CLI 1.53):
    ///   ⚙ Apple Silicon | Free space: 34.48GB
    /// ➤ User essentials
    ///   → User app cache · 20 items, 15.46GB dry        (dry-run)
    ///   → Trash · would empty, 33 items
    ///   ✓ User app cache · 18 items, 2.4GB              (real run)
    ///   ◎ pnpm cache · skipped (pnpm busy)              (skipped)
    ///   ✓ Nothing to clean
    /// ======================================================================
    /// Cleanup complete / Dry run complete - no changes made
    /// Potential space: 12.5GB | Items: 97 | Categories: 4
    static func parse(_ output: String, dryRun: Bool) -> CleanSummary {
        var sectionOrder: [String] = []
        var items: [CleanCategoryItem] = []
        var currentSection = "General"
        var totalBytes: Int64?
        var itemCount = 0
        var cancelled = false
        var freeSpace: String?
        var headLine: String?

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let plain = stripANSI(line).trimmingCharacters(in: .whitespaces)

            if plain.isEmpty { continue }

            if plain.contains("Free space:") {
                freeSpace = plain.components(separatedBy: "Free space:").last?
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            if plain.hasPrefix("⚙") || plain.hasPrefix("◎ Whitelist") || plain.hasPrefix("✓ Whitelist") {
                continue
            }

            if plain.hasPrefix("➤") {
                currentSection = plain.dropFirst(1).trimmingCharacters(in: .whitespaces)
                if !sectionOrder.contains(currentSection) { sectionOrder.append(currentSection) }
                continue
            }

            // Summary block markers.
            if plain.contains("Cleanup complete") || plain.contains("Dry run complete")
                || plain.contains("cleanup cancelled") || plain.contains("Cleanup cancelled")
                || plain.contains("cleanup incomplete") || plain.contains("Cleanup incomplete")
                || plain.contains("Dry run cancelled") || plain.contains("Dry run interrupted")
                || plain.contains("interrupted") {
                if plain.contains("cancelled") || plain.contains("interrupted") || plain.contains("incomplete") {
                    cancelled = true
                }
                continue
            }

            if plain.contains("Potential space:") || plain.contains("Tracked cleanup:") {
                totalBytes = parseSizeBytes(from: plain)
                if let itemsToken = plain.components(separatedBy: "Items:").dropFirst().first {
                    itemCount = Int(itemsToken.trimmingCharacters(in: .whitespaces)
                        .prefix { $0.isNumber }) ?? 0
                }
                continue
            }

            if plain.contains("Free space:") || plain.hasPrefix("=") || plain.hasPrefix("#") {
                continue
            }

            // Detail rows.
            guard plain.hasPrefix("→") || plain.hasPrefix("✓") || plain.hasPrefix("◎")
                || plain.hasPrefix("⚠") || plain.hasPrefix("✗") || plain.hasPrefix("●")
                || plain.hasPrefix("✱") || plain.hasPrefix("⚠") || plain.hasPrefix("-") else {
                // Unrecognized content line inside a section — keep it as detail context.
                continue
            }

            if plain.contains("Nothing to clean") { continue }

            let skipped = plain.hasPrefix("◎") || plain.hasPrefix("⚠") || plain.hasPrefix("✗")
            let body = String(plain.dropFirst(1)).trimmingCharacters(in: .whitespaces)

            var skipReason: String?
            if skipped, let open = body.firstIndex(of: "("), body.hasSuffix(")") {
                skipReason = String(body[body.index(after: open)..<body.index(before: body.endIndex)])
            }

            let (name, detail) = splitCleanRow(body)
            let bytes = parseSizeBytes(from: detail)
            let count = parseItemCount(from: detail)

            itemCount += skipped ? 0 : (count ?? 0)
            items.append(CleanCategoryItem(
                name: name, section: currentSection, detail: detail,
                estimatedBytes: bytes, itemCount: count,
                skipped: skipped, skipReason: skipReason))
        }

        if headLine == nil { headLine = nil }

        let categories = Set(items.map(\.name)).count
        return CleanSummary(
            dryRun: dryRun, sectionOrder: sectionOrder, items: items,
            totalBytes: totalBytes, itemCount: itemCount, categoryCount: categories,
            cancelled: cancelled, freeSpace: freeSpace, headLine: headLine)
    }

    /// "User app cache · 20 items, 15.46GB dry" → ("User app cache", "20 items, 15.46GB dry")
    static func splitCleanRow(_ body: String) -> (String, String) {
        guard let separator = body.range(of: " · ") else {
            return (body, "")
        }
        let name = String(body[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
        let detail = String(body[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (name, detail)
    }

    /// Pull the largest byte figure from strings like "20 items, 15.46GB dry".
    static func parseSizeBytes(from text: String) -> Int64? {
        let pattern = "([0-9]+(?:\\.[0-9]+)?)\\s*(KB|MB|GB|TB|B)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var best: (value: Double, multiplier: Int64)?
        for match in regex.matches(in: text, range: range) {
            guard let valueRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[valueRange]) else { continue }
            let unit = text[unitRange].uppercased()
            let multiplier: Int64
            switch unit {
            case "B": multiplier = 1
            case "KB": multiplier = 1_024
            case "MB": multiplier = 1_024 * 1_024
            case "GB": multiplier = 1_024 * 1_024 * 1_024
            case "TB": multiplier = 1_024 * 1_024 * 1_024 * 1_024
            default: multiplier = 1
            }
            let candidate = value * Double(multiplier)
            if best == nil || candidate > best!.value {
                best = (candidate, multiplier)
            }
        }
        guard let best else { return nil }
        return Int64(best.value)
    }

    static func parseItemCount(from text: String) -> Int? {
        let pattern = "([0-9]+)\\s+items?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[range])
    }

    static func stripANSI(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*[A-Za-z]") else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text, options: [], range: NSRange(text.startIndex..., in: text),
            withTemplate: "")
    }
}

// MARK: - Uninstall

struct UninstallPlanFile: Equatable, Identifiable, Sendable {
    var id: String { path }
    var path: String
    var size: String?
}

struct UninstallPlan: Equatable, Sendable {
    var appName: String
    var dryRun: Bool
    var files: [UninstallPlanFile]
    var totalSize: String?
    var heading: String?
    var summaryLine: String?
}

enum UninstallOutputParser {
    /// Parse `mo uninstall <app> [--dry-run]` output. Verified shape:
    ///   ◎ Matched 1 app(s):
    ///   1. RAV FileHub  80.4MB  |  Last: 2y ago
    ///   Files to be removed:
    ///   ◎ RAV FileHub , 80.4MB
    ///     ✓ /Applications/RAV FileHub.app , 80.4MB
    ///   ➤ Remove 1 app, 80.4MB  Enter confirm, ESC cancel:
    ///   ======================================================================
    ///   Uninstall dry run complete
    ///   Would remove 1 app, would free 80.4MB: RAV FileHub
    static func parse(_ output: String, appName: String, dryRun: Bool) -> UninstallPlan {
        func normalizeSize(_ raw: String?) -> String? {
            guard var value = raw else { return nil }
            value = value.trimmingCharacters(in: .whitespaces)
            while value.hasSuffix(":") || value.hasSuffix(",") {
                value = String(value.dropLast()).trimmingCharacters(in: .whitespaces)
            }
            return value.isEmpty ? nil : value
        }
        let plain = CleanOutputParser.stripANSI(output)
        var files: [UninstallPlanFile] = []
        var totalSize: String?
        var heading: String?
        var summaryLine: String?
        var insideFiles = false

        for rawLine in plain.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("=") { continue }

            if line.hasPrefix("Files to be removed") {
                insideFiles = true
                continue
            }

            if line.hasPrefix("Uninstall dry run complete")
                || line.hasPrefix("Uninstall complete") {
                insideFiles = false
                continue
            }

            if line.hasPrefix("Would remove") || line.hasPrefix("Removed") {
                summaryLine = line
                // "Would remove 1 app, would free 80.4MB: RAV FileHub" →
                // take only the numeric+unit token pair after "free".
                if let free = line.components(separatedBy: "free").dropFirst().first {
                    let tokens = free.trimmingCharacters(in: .whitespaces)
                        .split(separator: " ")
                        .prefix(2)
                    if tokens.count == 2, tokens[0].allSatisfy(\.isNumber) || Double(tokens[0]) != nil {
                        totalSize = "\(tokens[0]) \(tokens[1])"
                    }
                }
                continue
            }

            // "✓ /path , 80.4MB" or "✓ /path"
            if line.hasPrefix("✓"), insideFiles {
                var body = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                var size: String?
                if let comma = body.range(of: " , ") {
                    size = normalizeSize(String(body[comma.upperBound...]))
                    body = String(body[..<comma.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                files.append(UninstallPlanFile(path: body, size: size))
                continue
            }

            if heading == nil, line.hasPrefix("◎"),
               line.contains(appName) || line.contains("app") {
                heading = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }

        // A plan with no summary line still carries the total from the
        // "➤ Remove N app(s), X" confirm line. It appears as "Remove 1 app, 80.4MB"
        // (number-first) or "Remove 3 files, 12.80GB".
        if totalSize == nil, let removeLine = plain.split(separator: "\n")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.hasPrefix("➤ Remove") }) {
            // Grab the last "N unit" token pair before "Enter confirm".
            let body = removeLine.components(separatedBy: "Enter confirm").first ?? removeLine
            let tokens = body.split(separator: " ").map(String.init)
            for index in stride(from: tokens.count - 2, through: 1, by: -1) {
                let candidate = tokens[index]
                let unit = tokens[index + 1]
                let hasNumeric = candidate.first?.isNumber == true
                let isUnit = ["B", "KB", "MB", "GB", "TB"].contains {
                    unit.hasPrefix($0) || unit.hasSuffix($0)
                }
                if hasNumeric, isUnit {
                    totalSize = "\(candidate) \(unit)"
                    break
                }
            }
        }

        return UninstallPlan(
            appName: appName, dryRun: dryRun, files: files,
            totalSize: normalizeSize(totalSize) ?? files.compactMap(\.size).last,
            heading: heading, summaryLine: summaryLine)
    }
}

// MARK: - Optimize

struct OptimizeTask: Equatable, Identifiable, Sendable {
    var id: String { name }
    var name: String
    var detail: String?
    var outcome: OptimizeOutcome
}

enum OptimizeOutcome: Equatable, Sendable {
    case applied
    case unchanged
    case skipped(reason: String?)
    case unavailable(reason: String?)
    case attention(message: String?)
    case failed(reason: String?)
    case pending
}

struct OptimizeSummary: Equatable, Sendable {
    var dryRun: Bool
    var tasks: [OptimizeTask]
    var appliedCount: Int
    var unchangedCount: Int
    var skippedCount: Int
    var unavailableCount: Int
    var failedCount: Int
    var cancelled: Bool
    var systemLine: String?
}

enum OptimizeOutputParser {
    /// Parse `mo optimize` output. Verified shape:
    ///   ⚙ System  18/32 GB RAM | 616/926 GB Disk | Uptime 6d
    ///   ➤ DNS & Spotlight Check
    ///     → DNS cache flushed                       (applied)
    ///     ◎ Close these apps before...              (skipped w/ reason)
    ///     → Disk verify skipped (set MOLE_ENABLE... (unavailable/skip w/ reason)
    ///   ======================================================================
    ///   Optimization Complete
    ///   Applied 3 optimizations
    ///   14 unchanged | 3 skipped | 1 unavailable
    static func parse(_ output: String, dryRun: Bool) -> OptimizeSummary {
        let plain = CleanOutputParser.stripANSI(output)
        var tasks: [OptimizeTask] = []
        var currentName: String?
        var systemLine: String?
        var cancelled = false
        var inSummary = false

        var appliedCount = 0
        var unchangedCount = 0
        var skippedCount = 0
        var unavailableCount = 0
        var failedCount = 0

        for rawLine in plain.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("=") { continue }

            if line.hasPrefix("⚙") {
                systemLine = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }

            if line.hasPrefix("Optimization Complete") || line.hasPrefix("Dry Run Complete") {
                inSummary = true
                continue
            }
            if line.contains("cancelled") || line.contains("interrupted") {
                cancelled = true
                continue
            }
            if inSummary { continue }

            if line.hasPrefix("➤") {
                currentName = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }

            guard line.hasPrefix("→") || line.hasPrefix("◎") || line.hasPrefix("✓")
                || line.hasPrefix("⚠") || line.hasPrefix("✗") || line.hasPrefix("!")
                || line.hasPrefix("☻") else {
                continue
            }

            let symbol = line.first!
            var body = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            var reason: String?
            if let open = body.firstIndex(of: "("), body.hasSuffix(")") {
                reason = String(body[body.index(after: open)..<body.index(before: body.endIndex)])
            }

            var outcome: OptimizeOutcome
            switch symbol {
            case "→":
                if body.lowercased().contains("skipped") {
                    outcome = reason != nil ? .unavailable(reason: reason) : .skipped(reason: nil)
                    if reason != nil { unavailableCount += 1 } else { skippedCount += 1 }
                } else {
                    outcome = .applied
                    appliedCount += 1
                }
            case "◎", "✗":
                outcome = .skipped(reason: reason)
                skippedCount += 1
            case "☻":
                // Mole's ICON_ERROR — a task whose execution failed
                // (lib/core/base.sh: ICON_ERROR="☻").
                outcome = .failed(reason: reason ?? body)
                failedCount += 1
            case "⚠":
                outcome = .attention(message: body)
                failedCount += 1
            case "!":
                outcome = .failed(reason: body)
                failedCount += 1
            default:
                outcome = .unchanged
                unchangedCount += 1
            }

            if body.lowercased().contains("unavailable") && !isUnavailableAssigned(outcome) {
                outcome = .unavailable(reason: reason)
                unavailableCount += 1
                skippedCount = max(0, skippedCount - 1)
            }

            let name = currentName ?? "Optimization"
            if body.lowercased().hasPrefix("skipped") { body = "" }
            tasks.append(OptimizeTask(name: name, detail: body.isEmpty ? nil : body, outcome: outcome))
        }

        return OptimizeSummary(
            dryRun: dryRun, tasks: tasks,
            appliedCount: appliedCount, unchangedCount: unchangedCount,
            skippedCount: skippedCount, unavailableCount: unavailableCount,
            failedCount: failedCount, cancelled: cancelled, systemLine: systemLine)
    }

    /// Whether the outcome already encodes unavailability.
    private static func isUnavailableAssigned(_ outcome: OptimizeOutcome) -> Bool {
        if case .unavailable = outcome { return true }
        return false
    }
}
