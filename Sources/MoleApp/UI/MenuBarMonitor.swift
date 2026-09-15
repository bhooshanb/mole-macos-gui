import SwiftUI

/// Menu bar scene hosting the compact Mole monitor.
struct MenuBarScene: Scene {
    let appModel: AppViewModel

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(appModel: appModel)
        } label: {
            Image(systemName: "externaldrive.badge.timemachine")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Compact floating panel shown from the menu bar. Independent of the main
/// window: starts its own status collector when opened.
struct MenuBarPanel: View {
    let appModel: AppViewModel
    @StateObject private var model = MenuBarMonitorModel()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider().overlay(MoleTheme.border)

            if let snapshot = model.snapshot {
                menuRows(snapshot)
                Divider().overlay(MoleTheme.border)
                topProcesses(snapshot)
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Collecting status…")
                        .font(.system(size: 12))
                        .foregroundStyle(MoleTheme.textSecondary)
                }
            }

            cleanWatchSummary

            Divider().overlay(MoleTheme.border)

            HStack {
                Toggle("Monitoring", isOn: $model.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11))
                Spacer()
                Button("Wipe") { model.resetHistory() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                Button("Open Mole") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(MoleTheme.accent)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(MoleTheme.panel)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            MoleSilhouette()
                .frame(width: 26, height: 18)
            Text("Mole")
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
    }

    private func menuRows(_ snapshot: MetricsSnapshot) -> some View {
        VStack(spacing: 6) {
            miniRow("CPU", value: String(format: "%.0f%%", snapshot.cpu?.usage ?? 0),
                    fraction: (snapshot.cpu?.usage ?? 0) / 100, color: MoleTheme.infoBlue)
            miniRow("GPU",
                    value: (snapshot.gpu?.first?.usage).flatMap { $0 >= 0 ? String(format: "%.0f%%", $0) : nil } ?? "—",
                    fraction: 0, color: MoleTheme.infoBlue)
            miniRow("Memory", value: String(format: "%.0f%%", snapshot.memory?.usedPercent ?? 0),
                    fraction: (snapshot.memory?.usedPercent ?? 0) / 100, color: MoleTheme.infoBlue)
            let disk = snapshot.disks?.first { !($0.external ?? false) } ?? snapshot.disks?.first
            miniRow("Disk", value: String(format: "%.0f%%", disk?.usedPercent ?? 0),
                    fraction: (disk?.usedPercent ?? 0) / 100,
                    color: (disk?.usedPercent ?? 0) >= 85 ? MoleTheme.danger : MoleTheme.infoBlue)
            let rx = snapshot.network?.compactMap(\.rxRateMbs).reduce(0, +) ?? 0
            let tx = snapshot.network?.compactMap(\.txRateMbs).reduce(0, +) ?? 0
            HStack {
                Text("Network")
                    .font(.system(size: 11))
                    .foregroundStyle(MoleTheme.textSecondary)
                Spacer()
                Text("↓\(rateText(rx)) ↑\(rateText(tx))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(MoleTheme.textPrimary)
            }
            if let battery = snapshot.batteries?.first {
                HStack {
                    Text("Battery")
                        .font(.system(size: 11))
                        .foregroundStyle(MoleTheme.textSecondary)
                    Spacer()
                    Text(String(format: "%.0f%% · %d cycles", battery.percent ?? 0, battery.cycleCount ?? 0))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(MoleTheme.textPrimary)
                }
            }
            HStack {
                Text("Fan")
                    .font(.system(size: 11))
                    .foregroundStyle(MoleTheme.textSecondary)
                Spacer()
                Text(snapshot.thermal?.fanSpeed.map { $0 > 0 ? "\($0) RPM" : "—" } ?? "—")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(MoleTheme.textPrimary)
            }
        }
    }

    private func miniRow(_ label: String, value: String, fraction: Double, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(MoleTheme.textSecondary)
                .frame(width: 52, alignment: .leading)
            CapacityBar(fraction: fraction, color: color, height: 4)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(MoleTheme.textPrimary)
                .frame(width: 38, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    private func topProcesses(_ snapshot: MetricsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Top processes")
            ForEach(snapshot.topProcesses?.prefix(3) ?? [], id: \.pid) { process in
                HStack {
                    Text(process.name ?? "?")
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .foregroundStyle(MoleTheme.textPrimary)
                    Spacer()
                    Text(String(format: "%.0f%%", process.cpu ?? 0))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(MoleTheme.textSecondary)
                }
            }
        }
    }

    private var cleanWatchSummary: some View {
        let prefs = MolePreferences.shared
        return VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Clean Watch")
            HStack(spacing: 12) {
                summaryStat(bytesText(prefs.cleanWatchTotalBytes), "cleaned")
                summaryStat("\(prefs.cleanWatchUninstallCount)", "uninstalled")
                summaryStat("\(prefs.cleanWatchOptimizeCount)", "optimizations")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func summaryStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(MoleTheme.textPrimary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(MoleTheme.textTertiary)
        }
    }

    private func rateText(_ mbps: Double) -> String {
        mbps >= 1 ? String(format: "%.1fM", mbps) : String(format: "%.0fK", mbps * 1024)
    }
}

/// Lightweight collector for the menu bar: one-shot snapshots on a slow timer,
/// no persistent watch process unless enabled.
@MainActor
final class MenuBarMonitorModel: ObservableObject {
    @Published var snapshot: MetricsSnapshot?
    @Published var enabled: Bool = MolePreferences.shared.menuBarEnabled {
        didSet { MolePreferences.shared.menuBarEnabled = enabled }
    }

    private let client = MoleClient()
    private var timer: Timer?

    var healthColor: Color {
        switch snapshot?.healthScore ?? 0 {
        case 80...: return MoleTheme.healthy
        case 55..<80: return MoleTheme.caution
        default: return MoleTheme.danger
        }
    }

    func start() {
        refresh()
        // Low-power: refresh every 5s while the panel is open only.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        Task { [weak self] in
            guard let self else { return }
            if let snapshot = try? await self.client.statusSnapshot() {
                self.snapshot = snapshot
            }
        }
    }

    func resetHistory() {
        let prefs = MolePreferences.shared
        prefs.cleanWatchTotalBytes = 0
        prefs.cleanWatchSessionCount = 0
        prefs.cleanWatchUninstallCount = 0
        prefs.cleanWatchOptimizeCount = 0
    }
}
