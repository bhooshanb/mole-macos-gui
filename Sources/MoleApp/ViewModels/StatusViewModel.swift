import SwiftUI

/// Consumes `mo status --watch --interval Ns` NDJSON from a single warm
/// collector process, throttles UI updates, and tracks sample staleness.
@MainActor
final class StatusViewModel: ObservableObject {
    @Published var snapshot: MetricsSnapshot?
    @Published var connectionState: ConnectionState = .idle
    @Published var isStale = false
    @Published var lastError: MoleUserError?

    /// Bounded rolling series for graphs (rendered, not fabricated).
    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var rxHistory: [Double] = []
    @Published var txHistory: [Double] = []
    @Published var diskReadHistory: [Double] = []
    @Published var diskWriteHistory: [Double] = []

    enum ConnectionState: Equatable {
        case idle, connecting, live, failed(String)
    }

    private let client: MoleClient
    private var watchTask: Task<Void, Never>?
    private let maxHistory = 60

    init(client: MoleClient) {
        self.client = client
    }

    var primaryDisk: DiskStatus? {
        snapshot?.disks?.first { !($0.external ?? false) } ?? snapshot?.disks?.first
    }

    var primaryBattery: BatteryStatus? { snapshot?.batteries?.first }

    var primaryGPU: GPUStatus? { snapshot?.gpu?.first }

    var healthColor: Color {
        switch snapshot?.healthScore ?? 0 {
        case 80...: return MoleTheme.healthy
        case 55..<80: return MoleTheme.caution
        default: return MoleTheme.danger
        }
    }

    // MARK: Lifecycle

    func startMonitoring() {
        guard watchTask == nil else { return }
        connectionState = .connecting
        lastError = nil
        watchTask = Task { [weak self] in
            guard let self else { return }
            do {
                // One-shot snapshot first so the UI paints immediately.
                if let initial = try? await client.statusSnapshot() {
                    self.apply(initial)
                    connectionState = .live
                }
                let interval = MolePreferences.shared.statusWatchInterval
                let stream = try client.statusWatch(interval: interval)
                for try await snapshot in stream {
                    guard !Task.isCancelled else { break }
                    self.apply(snapshot)
                    if connectionState != .live { connectionState = .live }
                }
                // Stream ended cleanly (CLI exited) — reconnect with backoff.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !Task.isCancelled {
                    self.watchTask = nil
                    self.startMonitoring()
                }
            } catch is CancellationError {
                // Paused intentionally.
            } catch {
                connectionState = .failed(error.localizedDescription)
                lastError = MoleUserError(kind: .scanFailed(error.localizedDescription))
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !Task.isCancelled {
                    self.watchTask = nil
                    self.startMonitoring()
                }
            }
        }
    }

    func pauseMonitoring() {
        watchTask?.cancel()
        watchTask = nil
    }

    func restartMonitoring() {
        pauseMonitoring()
        startMonitoring()
    }

    // MARK: Sample application

    private func apply(_ snapshot: MetricsSnapshot) {
        self.snapshot = snapshot

        // Staleness: honor Mole's process_stale semantics; never fabricate.
        isStale = snapshot.processStale ?? false

        func push(_ series: inout [Double], _ value: Double?) {
            guard let value else { return }
            series.append(value)
            if series.count > maxHistory {
                series.removeFirst(series.count - maxHistory)
            }
        }

        withAnimation(.linear(duration: 0.3)) {
            push(&cpuHistory, snapshot.cpu?.usage)
            push(&memoryHistory, snapshot.memory?.usedPercent)
            let rx = snapshot.network?.compactMap(\.rxRateMbs).reduce(0, +)
            let tx = snapshot.network?.compactMap(\.txRateMbs).reduce(0, +)
            push(&rxHistory, rx)
            push(&txHistory, tx)
            push(&diskReadHistory, snapshot.diskIO?.readRate)
            push(&diskWriteHistory, snapshot.diskIO?.writeRate)
        }
    }

    // MARK: Derived display values

    var totalRxRate: Double {
        snapshot?.network?.compactMap(\.rxRateMbs).reduce(0, +) ?? 0
    }

    var totalTxRate: Double {
        snapshot?.network?.compactMap(\.txRateMbs).reduce(0, +) ?? 0
    }

    var formattedRxRate: String { rateText(totalRxRate) }
    var formattedTxRate: String { rateText(totalTxRate) }

    var formattedReadRate: String {
        rateText(snapshot?.diskIO?.readRate ?? 0)
    }

    var formattedWriteRate: String {
        rateText(snapshot?.diskIO?.writeRate ?? 0)
    }

    var memoryUsedText: String {
        bytesText(snapshot?.memory?.used)
    }

    var memoryTotalText: String {
        bytesText(snapshot?.memory?.total)
    }

    var diskUsedText: String { bytesText(primaryDisk?.used) }
    var diskTotalText: String { bytesText(primaryDisk?.total) }

    var batteryTempText: String {
        guard let temp = snapshot?.thermal?.batteryTemp, temp > 0 else { return "—" }
        return String(format: "%.0f°C", temp)
    }

    var cpuTempText: String {
        guard let temp = snapshot?.thermal?.cpuTemp, temp > 0 else { return "—" }
        return String(format: "%.0f°C", temp)
    }

    var gpuTempText: String {
        guard let temp = snapshot?.thermal?.gpuTemp, temp > 0 else { return "—" }
        return String(format: "%.0f°C", temp)
    }

    var fanText: String {
        guard let speed = snapshot?.thermal?.fanSpeed else { return "—" }
        return speed > 0 ? "\(speed) RPM" : "—"
    }

    var fanCountText: String {
        guard let count = snapshot?.thermal?.fanCount, count > 0 else { return "—" }
        return "\(count) fan\(count == 1 ? "" : "s")"
    }

    var zombieText: String {
        guard let count = snapshot?.zombieCount else { return "—" }
        return "\(count)"
    }

    private func rateText(_ mbps: Double) -> String {
        if mbps >= 1 {
            return String(format: "%.1f MB/s", mbps)
        }
        return String(format: "%.0f KB/s", mbps * 1024)
    }
}

/// Live metric card used across the Status screen.
struct MetricCard<Content: View>: View {
    let title: String
    var accessibilitySummary: String?
    @ViewBuilder var content: Content

    var body: some View {
        MoleCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MoleTheme.textTertiary)
                    .tracking(0.5)
                content
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilitySummary ?? "")
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    var valueColor: Color = MoleTheme.textPrimary

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(MoleTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(valueColor)
        }
        .accessibilityElement(children: .combine)
    }
}
