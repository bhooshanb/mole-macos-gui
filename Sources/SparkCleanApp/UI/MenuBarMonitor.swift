import SwiftUI
import Combine

/// Menu bar mini monitor. Implemented with a self-managed NSStatusItem so
/// visibility can be toggled live from Settings (SceneBuilder cannot branch
/// scenes). The panel content is the same SwiftUI MenuBarPanel.
@MainActor
final class MenuBarStatusItemController: ObservableObject {
    static let shared = MenuBarStatusItemController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellable: AnyCancellable?

    func install(appModel: AppViewModel) {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "externaldrive.badge.timemachine",
                                    accessibilityDescription: "SparkClean monitor")
        // Respect the current setting immediately at install time.
        item.isVisible = SparkCleanPreferences.shared.menuBarEnabled
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 316, height: 560)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarPanel(appModel: appModel))
        item.button?.target = self
        item.button?.action = #selector(togglePanel(_:))
        self.statusItem = item
        self.popover = popover

        cancellable = SparkCleanPreferences.shared.menuBarEnabledPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.statusItem?.isVisible = enabled
                if !enabled { self?.popover?.performClose(nil) }
            }
    }

    @objc private func togglePanel(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else if let popover {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }

    func remove() {
        popover?.performClose(nil)
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        cancellable = nil
    }
}

/// Menu bar scene hosting the compact SparkClean monitor. Installation happens in
/// ContentView's onAppear (a Settings-scene onAppear only fires when the user
/// opens Settings, which left the icon missing at launch).
struct MenuBarScene: Scene {
    let appModel: AppViewModel

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - Panel

/// Compact floating panel shown from the menu bar, redesigned around a
/// dense card grid: health header, CPU/GPU, Memory/Disk, Network/Fan,
/// battery, top processes, and Clean Watch — all real `mo status` data.
struct MenuBarPanel: View {
    let appModel: AppViewModel
    @StateObject private var model = MenuBarMonitorModel()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    if let snapshot = model.snapshot {
                        statGrid(snapshot)
                        batteryCard(snapshot)
                        processesCard(snapshot)
                    } else if model.loadFailed {
                        errorState
                    } else {
                        loadingState
                    }
                    footer
                }
                .padding(12)
            }

            // Quick Clean flow overlays the panel while active.
            if model.quickCleanPhase != .idle {
                QuickCleanFlow(model: model, appModel: appModel)
                    .transition(.opacity)
            }
        }
        .frame(width: 316, height: 560)
        .background(SparkCleanTheme.panel)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SparkleMark()
                    .frame(width: 26, height: 18)
                Text("SparkClean")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.healthColor)
                        .frame(width: 8, height: 8)
                    Text("\(model.snapshot?.healthScore ?? 0)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(model.healthColor)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Health score \(model.snapshot?.healthScore ?? 0)")
            }

            // System tags: only tags with a real value are shown.
            if let snapshot = model.snapshot {
                FlowingTags(tags: systemTags(snapshot))
                diskTag(snapshot)
            }
        }
    }

    private func systemTags(_ snapshot: MetricsSnapshot) -> [String] {
        var tags: [String] = []
        if let cpu = Self.displayable(snapshot.hardware?.cpuModel) { tags.append(cpu) }
        if let ram = Self.displayable(snapshot.hardware?.totalRAM) { tags.append(ram) }
        if let os = Self.displayable(snapshot.hardware?.osVersion) { tags.append(os) }
        if let up = snapshot.uptime { tags.append("up \(up)") }
        if let gpu = Self.gpuName(snapshot.gpu?.first), !gpu.isEmpty { tags.append(gpu) }
        if snapshot.proxy?.enabled == true {
            let type = Self.displayable(snapshot.proxy?.type) ?? "proxy"
            tags.append(type)
        }
        return tags
    }

    private func diskTag(_ snapshot: MetricsSnapshot) -> some View {
        if let disk = Self.displayable(snapshot.hardware?.diskSize) {
            return AnyView(
                Text(disk)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(SparkCleanTheme.fillSubtle))
                    .foregroundStyle(SparkCleanTheme.textSecondary)
            )
        }
        return AnyView(EmptyView())
    }

    private static func gpuName(_ gpu: GPUStatus?) -> String? {
        guard let raw = gpu?.name, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func displayable(_ value: String?) -> String? {
        guard let raw = value else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return nil }
        return cleaned
    }

    // MARK: Stat grid

    private func statGrid(_ snapshot: MetricsSnapshot) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                cpuCard(snapshot)
                gpuCard(snapshot)
            }
            HStack(spacing: 8) {
                memoryCard(snapshot)
                diskCard(snapshot)
            }
            HStack(spacing: 8) {
                networkCard(snapshot)
                fanCard(snapshot)
            }
        }
    }

    private func cpuCard(_ snapshot: MetricsSnapshot) -> some View {
        let usage = snapshot.cpu?.usage ?? 0
        let temp = snapshot.thermal?.cpuTemp ?? 0
        return PanelMetricCard(
            icon: "cpu", title: "CPU", badge: temp > 0 ? "\(Int(temp))°C" : nil,
            badgeColor: tempColor(temp), value: Int(usage.rounded()), unit: "%",
            series: model.cpuHistory,
            caption: caption(idle: usage < 5, extra: loadText(snapshot)))
    }

    private func gpuCard(_ snapshot: MetricsSnapshot) -> some View {
        let gpu = snapshot.gpu?.first
        let isUsable = gpu != nil && (gpu?.usage ?? -1) >= 0
        let usage = gpu?.usage ?? 0
        let temp = snapshot.thermal?.gpuTemp ?? 0
        return PanelMetricCard(
            icon: "display", title: "GPU", badge: temp > 0 ? "\(Int(temp))°C" : nil,
            badgeColor: tempColor(temp),
            value: isUsable ? Int(usage.rounded()) : nil,
            unit: isUsable ? "%" : nil,
            series: isUsable ? model.gpuHistory : [],
            caption: caption(
                idle: isUsable ? (usage < 2) : false,
                extra: gpuCaption(gpu)))
    }

    private func gpuCaption(_ gpu: GPUStatus?) -> String? {
        guard let gpu else { return nil }
        if gpu.coreCount != nil {
            let cores = gpu.coreCount.map { "\($0) cores" } ?? nil
            return cores
        }
        return gpu.note
    }

    private func memoryCard(_ snapshot: MetricsSnapshot) -> some View {
        let mem = snapshot.memory
        let pct = mem?.usedPercent ?? 0
        let pressure = mem?.pressure ?? ""
        let swap = mem?.swapUsed ?? 0
        return PanelMetricCard(
            icon: "memorychip", title: "MEM",
            badge: pressure.isEmpty ? nil : "PRS \(pressure)",
            badgeColor: SparkCleanTheme.caution,
            value: Int(pct.rounded()), unit: "%",
            progress: pct / 100, progressColor: pct >= 85 ? SparkCleanTheme.danger : SparkCleanTheme.caution,
            series: model.memoryHistory,
            caption: swap > 0 ? "\(bytesText(swap)) swap" : "0 swap")
    }

    private func diskCard(_ snapshot: MetricsSnapshot) -> some View {
        let disk = snapshot.disks?.first { !($0.external ?? false) } ?? snapshot.disks?.first
        let pct = disk?.usedPercent ?? 0
        let total = disk?.total ?? 0
        let free = max(0, total - (disk?.used ?? 0))
        return PanelMetricCard(
            icon: "internaldrive", title: "Disk",
            badge: total > 0 ? bytesText(total) : nil, badgeColor: SparkCleanTheme.infoBlue,
            value: Int(pct.rounded()), unit: "%",
            progress: pct / 100,
            progressColor: pct >= 90 ? SparkCleanTheme.danger : SparkCleanTheme.infoBlue,
            caption: "\(bytesText(free)) free")
    }

    private func networkCard(_ snapshot: MetricsSnapshot) -> some View {
        let rx = snapshot.network?.compactMap(\.rxRateMbs).reduce(0, +) ?? 0
        let tx = snapshot.network?.compactMap(\.txRateMbs).reduce(0, +) ?? 0
        let iface = snapshot.network?.first { ($0.rxRateMbs ?? 0) > 0 || ($0.txRateMbs ?? 0) > 0 }?.name
            ?? snapshot.network?.first?.name
        return PanelMetricCard(
            icon: "network", title: "Network",
            badge: iface.map { String($0.prefix(6)) }, badgeColor: SparkCleanTheme.infoBlue,
            value: nil, unit: nil, series: model.networkHistory,
            caption: "↑\(rateText(tx)) ↓\(rateText(rx))")
    }

    private func fanCard(_ snapshot: MetricsSnapshot) -> some View {
        let rpm = snapshot.thermal?.fanSpeed ?? 0
        let count = snapshot.thermal?.fanCount ?? 0
        return PanelMetricCard(
            icon: "fan", title: "FAN",
            badge: nil, badgeColor: SparkCleanTheme.infoBlue,
            value: rpm, unit: "RPM",
            caption: count > 1 ? "\(count) fans" : (rpm == 0 ? "Idle" : "Managed by macOS"))
    }

    // MARK: Battery

    private func batteryCard(_ snapshot: MetricsSnapshot) -> some View {
        guard let battery = snapshot.batteries?.first else { return AnyView(EmptyView()) }
        let pct = battery.percent ?? 0
        let charging = (battery.status ?? "").lowercased().contains("charg")
        let color: Color = pct >= 30 ? SparkCleanTheme.healthy : SparkCleanTheme.danger
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "battery.75percent")
                        .font(.system(size: 10))
                        .foregroundStyle(color)
                    Text("BATTERY")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SparkCleanTheme.textSecondary)
                    Spacer()
                    if let health = battery.health {
                        Text("\(health) health")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(SparkCleanTheme.healthy.opacity(0.14)))
                            .foregroundStyle(SparkCleanTheme.healthy)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(Int(pct))%")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(SparkCleanTheme.textPrimary)
                    Text(charging ? "Plugged In" : (battery.status ?? "On Battery"))
                        .font(.system(size: 11))
                        .foregroundStyle(SparkCleanTheme.textSecondary)
                    if let cycles = battery.cycleCount {
                        Spacer()
                        Text("\(cycles) cycles")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(SparkCleanTheme.textTertiary)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SparkCleanTheme.cardRadius).fill(SparkCleanTheme.card))
            .overlay(RoundedRectangle(cornerRadius: SparkCleanTheme.cardRadius).strokeBorder(SparkCleanTheme.border))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Battery \(Int(pct)) percent, \(battery.status ?? ""), health \(battery.health ?? "unknown")"))
    }

    // MARK: Processes

    private func processesCard(_ snapshot: MetricsSnapshot) -> some View {
        let procs = snapshot.topProcesses?.prefix(4) ?? []
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("TOP PROCESSES")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SparkCleanTheme.textSecondary)
                Spacer()
                if snapshot.processStale == true {
                    Text("stale")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(SparkCleanTheme.textTertiary)
                }
            }
            if procs.isEmpty {
                Text("No process data")
                    .font(.system(size: 11))
                    .foregroundStyle(SparkCleanTheme.textTertiary)
            } else {
                HStack {
                    Spacer()
                    Text("CPU").font(.system(size: 9)).foregroundStyle(SparkCleanTheme.textTertiary)
                        .frame(width: 44, alignment: .trailing)
                    Text("Memory").font(.system(size: 9)).foregroundStyle(SparkCleanTheme.textTertiary)
                        .frame(width: 62, alignment: .trailing)
                }
                ForEach(procs, id: \.pid) { proc in
                    HStack(spacing: 6) {
                        Text(proc.name ?? "?")
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .foregroundStyle(SparkCleanTheme.textPrimary)
                        Spacer()
                        Text(String(format: "%.1f%%", proc.cpu ?? 0))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(SparkCleanTheme.textSecondary)
                            .frame(width: 44, alignment: .trailing)
                        Text(proc.memoryBytes.map { bytesText($0) } ?? "—")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(SparkCleanTheme.textSecondary)
                            .frame(width: 62, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(proc.name ?? "process"), CPU \(String(format: "%.1f", proc.cpu ?? 0)) percent, memory \(proc.memoryBytes.map { bytesText($0) } ?? "unknown")")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: SparkCleanTheme.cardRadius).fill(SparkCleanTheme.card))
        .overlay(RoundedRectangle(cornerRadius: SparkCleanTheme.cardRadius).strokeBorder(SparkCleanTheme.border))
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Spacer()
                Button {
                    model.setMonitoring(!model.enabled)
                } label: {
                    Label(model.enabled ? "On" : "Off", systemImage: "hare")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(model.enabled ? SparkCleanTheme.accent.opacity(0.22) : SparkCleanTheme.fillSubtle))
                        .foregroundStyle(model.enabled ? SparkCleanTheme.accent : SparkCleanTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.enabled ? "Monitoring on, turn off" : "Monitoring off, turn on")

                Button {
                    model.startQuickClean()
                } label: {
                    Label("Quick Clean", systemImage: "wind")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(SparkCleanTheme.accent.opacity(0.22)))
                        .foregroundStyle(SparkCleanTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(model.quickCleanPhase != .idle)
                .accessibilityLabel("Quick clean: preview and run SparkClean safe cleanup")

                Button { MainWindow.activate() } label: {
                    Label("Open", systemImage: "macwindow")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(SparkCleanTheme.fillSelected))
                        .foregroundStyle(SparkCleanTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }

            // Re-read preferences whenever Wipe bumps the generation.
            cleanWatchSummary
                .id(model.cleanWatchGeneration)
        }
    }

    private var cleanWatchSummary: some View {
        let prefs = SparkCleanPreferences.shared
        return VStack(alignment: .leading, spacing: 5) {
            Text("✦ CLEAN WATCH")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(SparkCleanTheme.textSecondary)
            HStack(spacing: 0) {
                summaryStat(bytesText(prefs.cleanWatchTotalBytes), "Cleaned")
                Spacer()
                summaryStat("\(prefs.cleanWatchUninstallCount)", "Uninstalled")
                Spacer()
                summaryStat("\(prefs.cleanWatchOptimizeCount)", "Optimized")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func summaryStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(SparkCleanTheme.textPrimary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(SparkCleanTheme.textTertiary)
        }
    }

    // MARK: States

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Collecting status…")
                .font(.system(size: 12))
                .foregroundStyle(SparkCleanTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 30)
    }

    private var errorState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Couldn't reach the command-line tool")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SparkCleanTheme.textPrimary)
            Text("Make sure `mo` is installed, then reopen the panel.")
                .font(.system(size: 11))
                .foregroundStyle(SparkCleanTheme.textSecondary)
            Button("Retry") { model.retry() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 20)
    }

    // MARK: Helpers

    private func caption(idle: Bool, extra: String?) -> String {
        let prefix = idle ? "idle" : "active"
        if let extra, !extra.isEmpty { return "\(prefix) · \(extra)" }
        return prefix
    }

    private func loadText(_ snapshot: MetricsSnapshot) -> String? {
        guard let load = snapshot.cpu?.load1, let cores = snapshot.cpu?.coreCount, cores > 0 else { return nil }
        return String(format: "Load %.1f/%d", load, cores)
    }



    private func tempColor(_ t: Double) -> Color {
        switch t {
        case ..<50: return SparkCleanTheme.healthy
        case ..<70: return SparkCleanTheme.caution
        default: return SparkCleanTheme.danger
        }
    }

    private func rateText(_ mbps: Double) -> String {
        mbps >= 1 ? String(format: "%.1fM", mbps) : String(format: "%.0fK", mbps * 1024)
    }
}

// MARK: - Quick Clean

/// States of the panel's Quick Clean flow: dry-run preview → user
/// confirmation → real clean → result.
enum QuickCleanPhase: Equatable {
    case idle
    case previewing
    case confirming
    case cleaning
    case done
    case failed(String)
}

/// Overlay that drives Quick Clean inside the menu bar panel: shows the
/// dry-run preview from the real `mo clean --dry-run`, asks for explicit
/// confirmation, then runs `mo clean` with a progress indicator and a final
/// summary. No deletion logic lives here — everything goes through SparkCleanClient.
struct QuickCleanFlow: View {
    @ObservedObject var model: MenuBarMonitorModel
    let appModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch model.quickCleanPhase {
            case .previewing:
                stateRow(icon: "magnifyingglass", text: "Scanning for cleanable files…", spinning: true)
                ProgressView(value: 0.35).tint(SparkCleanTheme.accent)

            case .confirming:
                confirmStep

            case .cleaning:
                stateRow(icon: "wind", text: "Cleaning…", spinning: true)
                ProgressView(value: model.quickCleanProgress).tint(SparkCleanTheme.accent)
                if let line = model.quickCleanStatusLine {
                    Text(line)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SparkCleanTheme.textTertiary)
                        .lineLimit(1)
                }
                Button("Cancel") { model.cancelQuickClean() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(SparkCleanTheme.healthy)
                    .frame(maxWidth: .infinity)
                Text("Cleaning complete")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                quickCleanResultSummary
                Button("Done") { model.dismissQuickClean() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(SparkCleanTheme.accent)
                    .frame(maxWidth: .infinity)

            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(SparkCleanTheme.caution)
                    .frame(maxWidth: .infinity)
                Text("Quick Clean failed")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                Text(message)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(SparkCleanTheme.textSecondary)
                    .lineLimit(4)
                HStack {
                    Button("Retry") { model.startQuickClean() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Spacer()
                    Button("Close") { model.dismissQuickClean() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(SparkCleanTheme.accent)
                }

            case .idle:
                EmptyView()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: SparkCleanTheme.largeRadius).fill(SparkCleanTheme.panel))
        .overlay(RoundedRectangle(cornerRadius: SparkCleanTheme.largeRadius).strokeBorder(SparkCleanTheme.border))
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ready to clean", systemImage: "wind")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SparkCleanTheme.textPrimary)

            if let preview = model.quickCleanPreview {
                Text("\(bytesText(preview.totalBytes ?? 0)) in \(preview.itemCount) items")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(SparkCleanTheme.textPrimary)
                Text("across \(preview.categoryCount) categories")
                    .font(.system(size: 11))
                    .foregroundStyle(SparkCleanTheme.textSecondary)

                // First few categories as a plan summary.
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(preview.items.filter { !$0.skipped }.prefix(4)) { item in
                        HStack {
                            Text(item.name)
                                .font(.system(size: 10))
                                .foregroundStyle(SparkCleanTheme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text(item.estimatedBytes.map { bytesText($0) } ?? "—")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(SparkCleanTheme.textTertiary)
                        }
                    }
                    if preview.categoryCount > 4 {
                        Text("+ \(preview.categoryCount - 4) more categories")
                            .font(.system(size: 9))
                            .foregroundStyle(SparkCleanTheme.textTertiary)
                    }
                }

                Text("The command-line tool removes files — caches only, with protected locations respected. This cannot be undone for non-Trash items.")
                    .font(.system(size: 9))
                    .foregroundStyle(SparkCleanTheme.textTertiary)

                HStack {
                    Button("Cancel") { model.dismissQuickClean() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Spacer()
                    Button("Clean \(bytesText(preview.totalBytes ?? 0))") {
                        model.confirmQuickClean()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(SparkCleanTheme.accent)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Preparing preview…")
                    .font(.system(size: 11))
                    .foregroundStyle(SparkCleanTheme.textSecondary)
            }
        }
    }

    private var quickCleanResultSummary: some View {
        let result = model.quickCleanResult
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(bytesText(result?.totalBytes ?? 0)) recovered")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(SparkCleanTheme.textPrimary)
            Text("\(result?.itemCount ?? 0) items · \(result?.categoryCount ?? 0) categories")
                .font(.system(size: 10))
                .foregroundStyle(SparkCleanTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func stateRow(icon: String, text: String, spinning: Bool) -> some View {
        HStack(spacing: 8) {
            if spinning {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: icon)
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SparkCleanTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Card building blocks

/// Compact panel-specific stat card (Status's generic MetricCard doesn't fit
/// the dense grid). One stat card: icon+title row with a colored badge, a big
/// value, a sparkline or capacity bar, and a caption line.
private struct PanelMetricCard: View {
    let icon: String
    let title: String
    let badge: String?
    let badgeColor: Color
    let value: Int?
    let unit: String?
    var progress: Double?
    var progressColor: Color = .clear
    var series: [Double] = []
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(badgeColor)
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SparkCleanTheme.textSecondary)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Capsule().fill(badgeColor.opacity(0.14)))
                        .foregroundStyle(badgeColor)
                        .lineLimit(1)
                }
            }
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(value)")
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundStyle(SparkCleanTheme.textPrimary)
                    Text(unit ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(SparkCleanTheme.textTertiary)
                }
            }
            if let progress {
                CapacityBar(fraction: progress, color: progressColor, height: 5)
            } else if series.count > 1 {
                Sparkline(values: series, color: badgeColor)
                    .frame(height: 22)
            }
            Text(caption)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SparkCleanTheme.textTertiary)
                .lineLimit(1)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: SparkCleanTheme.cardRadius).fill(SparkCleanTheme.card))
        .overlay(RoundedRectangle(cornerRadius: SparkCleanTheme.cardRadius).strokeBorder(SparkCleanTheme.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value.map { "\($0)\(unit ?? "")" } ?? ""), \(caption)")
    }
}

/// Wrapping row of small monospace tags.
private struct FlowingTags: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(SparkCleanTheme.fillSubtle))
                        .foregroundStyle(SparkCleanTheme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Model

/// Lightweight collector for the menu bar: one-shot snapshots on a slow timer,
/// no persistent watch process unless enabled. Retains rolling history for the
/// card sparklines.
@MainActor
final class MenuBarMonitorModel: ObservableObject {
    @Published var snapshot: MetricsSnapshot?
    @Published var loadFailed = false
    @Published var cpuHistory: [Double] = []
    @Published var gpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var networkHistory: [Double] = []
    @Published var enabled: Bool = SparkCleanPreferences.shared.menuBarEnabled {
        didSet { SparkCleanPreferences.shared.menuBarEnabled = enabled }
    }

    private let client = SparkCleanClient()
    private let historyLimit = 40

    var healthColor: Color {
        switch snapshot?.healthScore ?? 0 {
        case 80...: return SparkCleanTheme.healthy
        case 55..<80: return SparkCleanTheme.caution
        default: return SparkCleanTheme.danger
        }
    }

    @Published var cleanWatchGeneration = 0

    func start() {
        if enabled {
            refresh()
            startPolling()
        }
    }

    func stop() {
        stopPolling()
    }

    func retry() {
        loadFailed = false
        refresh()
        startPolling()
    }

    private func refresh() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.client.statusSnapshot()
                self.snapshot = snapshot
                self.loadFailed = false
                self.appendHistory(snapshot)
            } catch {
                // Keep the last good snapshot visible; only flag on repeated
                // absence of data.
                if self.snapshot == nil { self.loadFailed = true }
            }
        }
    }

    private func appendHistory(_ snapshot: MetricsSnapshot) {
        append(&cpuHistory, snapshot.cpu?.usage ?? 0)
        append(&gpuHistory, snapshot.gpu?.first?.usage ?? 0)
        append(&memoryHistory, snapshot.memory?.usedPercent ?? 0)
        let rx = snapshot.network?.compactMap(\.rxRateMbs).reduce(0, +) ?? 0
        let tx = snapshot.network?.compactMap(\.txRateMbs).reduce(0, +) ?? 0
        append(&networkHistory, rx + tx)
    }

    private func append(_ array: inout [Double], _ value: Double) {
        array.append(value)
        if array.count > historyLimit { array.removeFirst(array.count - historyLimit) }
    }

    /// Wipes the Clean Watch counters and bumps a generation token so every
    /// observing view re-reads preferences immediately (UserDefaults alone
    /// would not trigger a re-render).
    func resetHistory() {
        let prefs = SparkCleanPreferences.shared
        prefs.cleanWatchTotalBytes = 0
        prefs.cleanWatchSessionCount = 0
        prefs.cleanWatchUninstallCount = 0
        prefs.cleanWatchOptimizeCount = 0
        cleanWatchGeneration += 1
    }

    /// Whether the collector should poll. The toggle stops the 5s timer and
    /// the in-flight snapshot task, not just the preference.
    private var pollTask: Task<Void, Never>?

    func setMonitoring(_ on: Bool) {
        enabled = on
        if on {
            refresh()
            startPolling()
        } else {
            stopPolling()
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                self.refresh()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Quick Clean

    /// Dry-run summary awaiting confirmation.
    @Published var quickCleanPreview: CleanSummary?
    /// Result of the real clean run.
    @Published var quickCleanResult: CleanSummary?
    @Published var quickCleanPhase: QuickCleanPhase = .idle
    @Published var quickCleanProgress: Double = 0
    @Published var quickCleanStatusLine: String?

    private var quickCleanTask: Task<Void, Never>?

    /// Kicks off the Quick Clean flow: dry-run first, nothing is deleted
    /// until the user explicitly confirms in the UI.
    func startQuickClean() {
        guard quickCleanPhase == .idle || quickCleanPhase == .done || quickCleanPhase == .failed("")
            || isFailure else { return }
        quickCleanPreview = nil
        quickCleanResult = nil
        quickCleanProgress = 0
        quickCleanStatusLine = nil
        quickCleanPhase = .previewing
        quickCleanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let preview = try await self.client.cleanDryRun()
                guard !Task.isCancelled else { return }
                self.quickCleanPreview = preview
                self.quickCleanPhase = .confirming
            } catch is CancellationError {
                self.quickCleanPhase = .idle
            } catch {
                self.quickCleanPhase = .failed(String(describing: error))
            }
        }
    }

    private var isFailure: Bool {
        if case .failed = quickCleanPhase { return true }
        return false
    }

    /// User confirmed: run the real clean after the preview.
    func confirmQuickClean() {
        guard quickCleanPhase == .confirming else { return }
        quickCleanPhase = .cleaning
        quickCleanProgress = 0
        quickCleanStatusLine = nil
        quickCleanTask = Task { [weak self] in
            guard let self else { return }
            // Indeterminate-safe progress: ease toward 90% while the CLI runs,
            // then snap to 100% on completion.
            let progressTask = Task { [weak self] in
                while let self, !Task.isCancelled, self.quickCleanPhase == .cleaning {
                    if self.quickCleanProgress < 0.9 {
                        withAnimation(.linear(duration: 0.5)) {
                            self.quickCleanProgress = min(0.9, self.quickCleanProgress + 0.03)
                        }
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            do {
                let result = try await self.client.clean()
                progressTask.cancel()
                guard !Task.isCancelled else { return }
                withAnimation {
                    self.quickCleanResult = result
                    self.quickCleanProgress = 1
                    self.quickCleanPhase = .done
                }
                // Feed the Clean Watch counters exactly like the main window.
                SparkCleanPreferences.shared.cleanWatchSessionCount += 1
                if let bytes = result.totalBytes {
                    SparkCleanPreferences.shared.cleanWatchTotalBytes += bytes
                }
                self.refresh() // refresh stat cards (disk free may have changed)
            } catch is CancellationError {
                progressTask.cancel()
                self.quickCleanPhase = .idle
            } catch {
                progressTask.cancel()
                self.quickCleanPhase = .failed(String(describing: error))
            }
        }
    }

    func cancelQuickClean() {
        quickCleanTask?.cancel()
        quickCleanTask = nil
        quickCleanPhase = .idle
    }

    func dismissQuickClean() {
        quickCleanTask?.cancel()
        quickCleanTask = nil
        quickCleanPhase = .idle
    }
}
