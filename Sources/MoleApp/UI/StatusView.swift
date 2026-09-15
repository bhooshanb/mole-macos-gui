import SwiftUI

struct StatusView: View {
    @ObservedObject var viewModel: StatusViewModel
    @ObservedObject private var prefs = MolePreferences.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if viewModel.isStale {
                    staleNotice
                }
                if case .failed(let message) = viewModel.connectionState {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(MoleTheme.caution)
                        Text("Status stream failed: \(message)")
                            .font(.system(size: 12))
                            .foregroundStyle(MoleTheme.textSecondary)
                        Button("Retry") { viewModel.restartMonitoring() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(MoleTheme.card))
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    cpuCard
                    memoryCard
                    diskCard
                    networkCard
                    gpuCard
                    powerCard
                    fanCard
                    zombieCard
                }

                processesCard
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(MoleTheme.background)
        .accessibilityLabel("Status dashboard")
        // Apply interval / process-monitoring changes to the live stream.
        .onChange(of: prefs.statusWatchInterval) { _, _ in
            viewModel.restartMonitoring()
        }
        .onChange(of: prefs.statusProcessMonitoring) { _, _ in
            viewModel.restartMonitoring()
        }
    }

    // MARK: Header

    private var header: some View {
        MoleCard {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .strokeBorder(MoleTheme.border, lineWidth: 6)
                        .frame(width: 76, height: 76)
                    Circle()
                        .trim(from: 0, to: CGFloat(viewModel.snapshot?.healthScore ?? 0) / 100)
                        .stroke(viewModel.healthColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 76, height: 76)
                        .rotationEffect(.degrees(-90))
                    Text("\(viewModel.snapshot?.healthScore ?? 0)")
                        .font(MoleTheme.metric(24))
                        .foregroundStyle(viewModel.healthColor)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Health score \(viewModel.snapshot?.healthScore ?? 0) of 100")
                .accessibilityValue(viewModel.snapshot?.healthScoreMsg ?? "")

                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.snapshot?.hardware?.model ?? "Mac")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MoleTheme.textPrimary)
                    HStack(spacing: 10) {
                        headerChip(viewModel.snapshot?.hardware?.cpuModel)
                        headerChip(viewModel.snapshot?.hardware?.totalRAM)
                        headerChip(viewModel.snapshot?.hardware?.osVersion)
                    }
                    if let msg = viewModel.snapshot?.healthScoreMsg {
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundStyle(MoleTheme.textSecondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.connectionState == .live ? MoleTheme.healthy : MoleTheme.caution)
                            .frame(width: 7, height: 7)
                        Text(viewModel.connectionState == .live ? "Live" : "Connecting…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MoleTheme.textSecondary)
                    }
                    if let uptime = viewModel.snapshot?.uptime {
                        Text("Uptime \(uptime)")
                            .font(.system(size: 11))
                            .foregroundStyle(MoleTheme.textTertiary)
                    }
                    if let collected = viewModel.snapshot?.collectedAt {
                        Text("Updated \(collected.formatted(date: .omitted, time: .standard))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(MoleTheme.textTertiary)
                    }
                }
            }
        }
    }

    private func headerChip(_ text: String?) -> some View {
        Text(text ?? "—")
            .font(.system(size: 11))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .foregroundStyle(MoleTheme.textSecondary)
    }

    private var staleNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(MoleTheme.caution)
            Text("Process data is stale — the last process sample is being reused. Values will refresh automatically.")
                .font(.system(size: 11))
                .foregroundStyle(MoleTheme.textSecondary)
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(MoleTheme.caution.opacity(0.08)))
        .accessibilityLabel("Process monitoring data is stale")
    }

    // MARK: Cards

    private var cpuCard: some View {
        MetricCard(
            title: "CPU",
            accessibilitySummary: cpuAccessibility)
        {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: "%.1f%%", viewModel.snapshot?.cpu?.usage ?? 0))
                        .font(MoleTheme.metric(26))
                        .foregroundStyle(MoleTheme.infoBlue)
                    CapacityBar(
                        fraction: (viewModel.snapshot?.cpu?.usage ?? 0) / 100,
                        color: MoleTheme.infoBlue)
                    MetricRow(
                        label: "Load",
                        value: loadText)
                }
                Spacer()
                // Per-core bars
                VStack(spacing: 3) {
                    ForEach(
                        Array((viewModel.snapshot?.cpu?.perCore ?? []).prefix(8).enumerated()),
                        id: \.offset
                    ) { index, usage in
                        HStack(spacing: 5) {
                            Text("\(index + 1)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(MoleTheme.textTertiary)
                                .frame(width: 10, alignment: .trailing)
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 70, height: 4)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(MoleTheme.infoBlue)
                                        .frame(width: max(2, 70 * min(1, usage / 100)))
                                }
                        }
                    }
                }
                .accessibilityHidden(true)
            }
            if !viewModel.cpuHistory.isEmpty {
                Sparkline(values: viewModel.cpuHistory, color: MoleTheme.infoBlue)
                    .frame(height: 28)
            }
        }
    }

    private var loadText: String {
        guard let cpu = viewModel.snapshot?.cpu else { return "—" }
        return String(format: "%.2f / %.2f / %.2f", cpu.load1 ?? 0, cpu.load5 ?? 0, cpu.load15 ?? 0)
    }

    private var cpuAccessibility: String {
        "Usage \(String(format: "%.0f", viewModel.snapshot?.cpu?.usage ?? 0)) percent. Load \(loadText). Temperature \(viewModel.cpuTempText)."
    }

    private var memoryCard: some View {
        MetricCard(
            title: "Memory",
            accessibilitySummary: memoryAccessibility)
        {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(String(format: "%.1f%%", viewModel.snapshot?.memory?.usedPercent ?? 0)) used")
                    .font(MoleTheme.metric(26))
                    .foregroundStyle(MoleTheme.infoBlue)
                CapacityBar(
                    fraction: (viewModel.snapshot?.memory?.usedPercent ?? 0) / 100,
                    color: MoleTheme.infoBlue)
                MetricRow(label: "Used", value: "\(viewModel.memoryUsedText) / \(viewModel.memoryTotalText)")
                MetricRow(label: "Available", value: bytesText(viewModel.snapshot?.memory?.available))
                MetricRow(label: "Swap", value: swapText)
                if let pressure = viewModel.snapshot?.memory?.pressure, !pressure.isEmpty {
                    MetricRow(
                        label: "Pressure",
                        value: pressure,
                        valueColor: pressure == "normal" ? MoleTheme.healthy : MoleTheme.caution)
                }
            }
        }
    }

    private var swapText: String {
        guard let swap = viewModel.snapshot?.memory else { return "—" }
        guard let used = swap.swapUsed, used > 0 else { return "None" }
        return "\(bytesText(used)) of \(bytesText(swap.swapTotal))"
    }

    private var memoryAccessibility: String {
        "Memory \(String(format: "%.0f", viewModel.snapshot?.memory?.usedPercent ?? 0)) percent used of \(viewModel.memoryTotalText). \(bytesText(viewModel.snapshot?.memory?.available)) available."
    }

    private var diskCard: some View {
        MetricCard(
            title: "Disk",
            accessibilitySummary: diskAccessibility)
        {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(String(format: "%.1f%%", viewModel.primaryDisk?.usedPercent ?? 0)) used")
                    .font(MoleTheme.metric(26))
                    .foregroundStyle(capacityColor(viewModel.primaryDisk?.usedPercent ?? 0))
                CapacityBar(
                    fraction: (viewModel.primaryDisk?.usedPercent ?? 0) / 100,
                    color: MoleTheme.infoBlue)
                MetricRow(label: "Used", value: "\(viewModel.diskUsedText) / \(viewModel.diskTotalText)")
                MetricRow(label: "Read", value: viewModel.formattedReadRate)
                MetricRow(label: "Write", value: viewModel.formattedWriteRate)
                if let smart = viewModel.primaryDisk?.smartStatus, !smart.isEmpty {
                    MetricRow(
                        label: "SMART",
                        value: smart,
                        valueColor: smart.lowercased() == "verified" ? MoleTheme.healthy : MoleTheme.caution)
                }
                if !viewModel.diskReadHistory.isEmpty || !viewModel.diskWriteHistory.isEmpty {
                    HStack(spacing: 8) {
                        Sparkline(values: viewModel.diskReadHistory, color: MoleTheme.healthy)
                        Sparkline(values: viewModel.diskWriteHistory, color: MoleTheme.infoBlue)
                    }
                    .frame(height: 26)
                }
            }
        }
    }

    private var diskAccessibility: String {
        "Disk \(String(format: "%.0f", viewModel.primaryDisk?.usedPercent ?? 0)) percent used. \(viewModel.diskUsedText) used of \(viewModel.diskTotalText)."
    }

    private var networkCard: some View {
        MetricCard(
            title: "Network",
            accessibilitySummary: "Download \(viewModel.formattedRxRate), upload \(viewModel.formattedTxRate)")
        {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(viewModel.formattedRxRate, systemImage: "arrow.down")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(MoleTheme.healthy)
                        Text("down")
                            .font(.system(size: 10))
                            .foregroundStyle(MoleTheme.textTertiary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Label(viewModel.formattedTxRate, systemImage: "arrow.up")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(MoleTheme.infoBlue)
                        Text("up")
                            .font(.system(size: 10))
                            .foregroundStyle(MoleTheme.textTertiary)
                    }
                    Spacer()
                    if let proxy = viewModel.snapshot?.proxy, proxy.enabled == true {
                        Text("Proxy: \(proxy.type ?? "?")")
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(MoleTheme.infoBlue.opacity(0.14)))
                            .foregroundStyle(MoleTheme.infoBlue)
                    }
                }
                if !viewModel.rxHistory.isEmpty {
                    Sparkline(values: viewModel.rxHistory, color: MoleTheme.healthy)
                        .frame(height: 30)
                }
                if !viewModel.txHistory.isEmpty {
                    Sparkline(values: viewModel.txHistory, color: MoleTheme.infoBlue)
                        .frame(height: 30)
                }
                ForEach(Array((viewModel.snapshot?.network ?? []).prefix(2)), id: \.name) {
                    if let name = $0.name {
                        MetricRow(label: name, value: $0.ip?.isEmpty == false ? $0.ip! : "—")
                    }
                }
            }
        }
    }

    private var gpuCard: some View {
        MetricCard(
            title: "GPU",
            accessibilitySummary: gpuAccessibility)
        {
            VStack(alignment: .leading, spacing: 8) {
                if let gpu = viewModel.primaryGPU {
                    Text(gpuUsageText(gpu))
                        .font(MoleTheme.metric(26))
                        .foregroundStyle(MoleTheme.infoBlue)
                    if let name = gpu.name {
                        Text(name)
                            .font(MoleTheme.mono)
                            .lineLimit(1)
                            .foregroundStyle(MoleTheme.textTertiary)
                    }
                    MetricRow(label: "Cores", value: gpu.coreCount.map { "\($0)" } ?? "—")
                    if let used = gpu.memoryUsed, used > 0 {
                        MetricRow(
                            label: "Memory",
                            value: "\(bytesText(Int64(used))) / \(bytesText(Int64(gpu.memoryTotal ?? 0)))")
                    }
                    MetricRow(label: "Temp", value: viewModel.gpuTempText)
                    if let note = gpu.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 10))
                            .foregroundStyle(MoleTheme.textTertiary)
                    }
                } else {
                    Text("No GPU reported")
                        .font(.system(size: 12))
                        .foregroundStyle(MoleTheme.textTertiary)
                }
            }
        }
    }

    /// Mole reports usage -1 when the value cannot be measured; show that honestly.
    private func gpuUsageText(_ gpu: GPUStatus) -> String {
        guard let usage = gpu.usage, usage >= 0 else { return "—" }
        return String(format: "%.0f%%", usage)
    }

    private var gpuAccessibility: String {
        let usage = viewModel.primaryGPU.flatMap { $0.usage }.flatMap { $0 >= 0 ? String(format: "%.0f percent", $0) : nil } ?? "unavailable"
        return "GPU usage \(usage). Temperature \(viewModel.gpuTempText)."
    }

    private var powerCard: some View {
        MetricCard(
            title: "Power",
            accessibilitySummary: powerAccessibility)
        {
            VStack(alignment: .leading, spacing: 8) {
                if let battery = viewModel.primaryBattery {
                    HStack(spacing: 8) {
                        Image(systemName: batteryIcon(battery))
                            .foregroundStyle(batteryColor(battery))
                            .font(.system(size: 18))
                        Text(String(format: "%.0f%%", battery.percent ?? 0))
                            .font(MoleTheme.metric(26))
                            .foregroundStyle(MoleTheme.textPrimary)
                        Text(battery.status ?? "")
                            .font(.system(size: 11))
                            .foregroundStyle(MoleTheme.textSecondary)
                    }
                    CapacityBar(
                        fraction: (battery.percent ?? 0) / 100,
                        color: batteryColor(battery))
                    MetricRow(
                        label: "Health",
                        value: [battery.health, battery.capacity.map { "\($0)%" }].compactMap { $0 }
                            .joined(separator: " · "))
                    MetricRow(label: "Cycles", value: battery.cycleCount.map { "\($0)" } ?? "—")
                    MetricRow(label: "Temp", value: viewModel.batteryTempText)
                } else {
                    Text("No battery detected (desktop Mac)")
                        .font(.system(size: 12))
                        .foregroundStyle(MoleTheme.textTertiary)
                    if let power = viewModel.snapshot?.thermal {
                        MetricRow(
                            label: "System",
                            value: power.systemPower.map { String(format: "%.1f W", $0) } ?? "—")
                        MetricRow(
                            label: "Adapter",
                            value: power.adapterPower.map { String(format: "%.0f W", $0) } ?? "—")
                    }
                }
            }
        }
    }

    private var powerAccessibility: String {
        guard let battery = viewModel.primaryBattery else { return "Desktop Mac, no battery" }
        return "Battery \(String(format: "%.0f", battery.percent ?? 0)) percent, \(battery.status ?? "unknown"). Health \(battery.health ?? "unknown"), \(battery.cycleCount ?? 0) cycles."
    }

    private var fanCard: some View {
        MetricCard(
            title: "Fans",
            accessibilitySummary: "Fans \(viewModel.fanCountText), speed \(viewModel.fanText)")
        {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.fanText)
                    .font(MoleTheme.metric(26))
                    .foregroundStyle(MoleTheme.textPrimary)
                MetricRow(label: "Count", value: viewModel.fanCountText)
                if let count = viewModel.snapshot?.thermal?.fanCount, count == 0 {
                    Text("This Mac does not expose fan sensors to Mole.")
                        .font(.system(size: 11))
                        .foregroundStyle(MoleTheme.textTertiary)
                }
            }
        }
    }

    private var zombieCard: some View {
        MetricCard(
            title: "Processes",
            accessibilitySummary: "\(viewModel.snapshot?.procs ?? 0) processes, \(viewModel.zombieText) zombies")
        {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(viewModel.snapshot?.procs ?? 0)")
                    .font(MoleTheme.metric(26))
                    .foregroundStyle(MoleTheme.textPrimary)
                MetricRow(label: "Zombies", value: viewModel.zombieText)
                ForEach(viewModel.snapshot?.zombieParents ?? [], id: \.pid) { parent in
                    HStack {
                        Text(parent.name ?? "pid \(String(parent.pid))")
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                        Text("×\(parent.count ?? 0)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(MoleTheme.caution)
                    }
                }
                if viewModel.snapshot?.zombieParentsComplete == false {
                    Text("Zombie attribution incomplete")
                        .font(.system(size: 10))
                        .foregroundStyle(MoleTheme.textTertiary)
                }
            }
        }
    }

    private var processesCard: some View {
        MetricCard(
            title: "Top Processes",
            accessibilitySummary: "Top processes by CPU usage")
        {
            VStack(spacing: 0) {
                HStack {
                    Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
                    Text("PID").frame(width: 70, alignment: .trailing)
                    Text("CPU").frame(width: 64, alignment: .trailing)
                    Text("MEM").frame(width: 72, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MoleTheme.textTertiary)
                .padding(.bottom, 6)

                if viewModel.snapshot?.processStale == true {
                    // Rows shown below are from the reused sample; the badge above explains.
                }
                ForEach(viewModel.snapshot?.topProcesses ?? [], id: \.pid) { process in
                    HStack {
                        Text(process.name ?? "?")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(process.pid)")
                            .frame(width: 70, alignment: .trailing)
                        Text(String(format: "%.1f%%", process.cpu ?? 0))
                            .frame(width: 64, alignment: .trailing)
                        Text(process.memoryBytes.map { bytesText($0) } ?? "—")
                            .frame(width: 72, alignment: .trailing)
                    }
                    .font(MoleTheme.mono)
                    .foregroundStyle(MoleTheme.textSecondary)
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(process.name ?? "process"), PID \(process.pid), CPU \(String(format: "%.0f", process.cpu ?? 0)) percent, memory \(process.memoryBytes.map { bytesText($0) } ?? "unknown")")
                }
            }
        }
    }

    // MARK: Helpers

    private func capacityColor(_ fraction: Double) -> Color {
        if fraction >= 90 { return MoleTheme.danger }
        if fraction >= 75 { return MoleTheme.caution }
        return MoleTheme.infoBlue
    }

    private func batteryIcon(_ battery: BatteryStatus) -> String {
        let percent = battery.percent ?? 0
        let charging = (battery.status ?? "").lowercased().contains("charg")
        if charging { return "battery.100.bolt" }
        if percent > 80 { return "battery.100" }
        if percent > 40 { return "battery.50" }
        return "battery.25"
    }

    private func batteryColor(_ battery: BatteryStatus) -> Color {
        let percent = battery.percent ?? 0
        if percent <= 20 { return MoleTheme.danger }
        if percent <= 40 { return MoleTheme.caution }
        return MoleTheme.healthy
    }
}
