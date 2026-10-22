import SwiftUI

/// First-run experience: detect the CLI, install it if missing, explain
/// capabilities, configure the menu bar monitor, finish setup.
struct WelcomeView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var cliStatus: CLICheckResult?
    @State private var menuBarEnabled = SparkCleanPreferences.shared.menuBarEnabled
    @StateObject private var installer = SparkCleanInstaller()

    struct CLICheckResult {
        var found: Bool
        var version: String?
        var path: String?
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: intro
                case 1: detection
                default: finish
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(SparkCleanTheme.border)

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                if step < 2 {
                    Button(step == 0 ? "Get Started" : "Continue") { advance() }
                        .buttonStyle(.borderedProminent)
                        .tint(SparkCleanTheme.accent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(step == 1 && cliStatus?.found != true)
                } else {
                    Button("Finish") {
                        SparkCleanPreferences.shared.menuBarEnabled = menuBarEnabled
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SparkCleanTheme.accent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(SparkCleanTheme.panel.opacity(0.5))
        }
        .frame(width: 520, height: 480)
        .background(
            LinearGradient(colors: [SparkCleanTheme.warmPanel, SparkCleanTheme.panel],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var intro: some View {
        VStack(spacing: 18) {
            Spacer()
            SparkCleanOrb(animate: false)
                .frame(width: 160, height: 160)
            Text("Welcome to SparkClean")
                .font(SparkCleanTheme.metric(30))
                .foregroundStyle(SparkCleanTheme.textPrimary)
            Text("Clean, optimize, analyze, and monitor your Mac.")
                .font(.system(size: 14))
                .foregroundStyle(SparkCleanTheme.textSecondary)
            VStack(alignment: .leading, spacing: 8) {
                featureRow("sparkles", "Clean", "Preview and remove caches, logs, and trash — always dry-run first.")
                featureRow("app.badge.minus", "Apps", "Uninstall applications with file-accurate plans.")
                featureRow("gauge.with.needle", "Optimize", "Refresh caches and services with skip reasons you can read.")
                featureRow("chart.pie", "Analyze", "Treemap of what's eating your disk, powered by mo analyze --json.")
                featureRow("waveform.path.ecg", "Status", "Live health dashboard streamed from the CLI collector.")
            }
            Spacer()
        }
    }

    private func featureRow(_ icon: String, _ title: String, _ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(SparkCleanTheme.accent)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 70, alignment: .leading)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(SparkCleanTheme.textSecondary)
            Spacer()
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var detection: some View {
        VStack(spacing: 16) {
            Spacer()
            if let status = cliStatus {
                if status.found {
                    detectedView(status)
                } else {
                    missingCLIView
                }
            } else {
                Text("Detecting command-line tool…")
                    .font(.system(size: 12))
                    .foregroundStyle(SparkCleanTheme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func detectedView(_ status: CLICheckResult) -> some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 44))
            .foregroundStyle(SparkCleanTheme.healthy)
        Text("Command-line tool detected")
            .font(.system(size: 18, weight: .bold))
        if let version = status.version {
            Text(version)
                .font(SparkCleanTheme.mono)
                .foregroundStyle(SparkCleanTheme.textSecondary)
        }
        if let path = status.path {
            Text(path)
                .font(SparkCleanTheme.mono)
                .foregroundStyle(SparkCleanTheme.textTertiary)
        }
        Text("SparkClean will run the real `mo` commands under the hood. Nothing is deleted without your confirmation, and every cleanup starts as a dry-run preview.")
            .font(.system(size: 12))
            .foregroundStyle(SparkCleanTheme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 400)
    }

    /// Missing CLI: offer a one-click install with live progress.
    private var missingCLIView: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.dotted")
                .font(.system(size: 44))
                .foregroundStyle(SparkCleanTheme.caution)
            Text("Command-line tool not found")
                .font(.system(size: 18, weight: .bold))

            switch installer.phase {
            case .idle:
                Text("SparkClean.app needs its command-line utility. Install it now — Homebrew is used when available, otherwise the official install script runs.")
                    .font(.system(size: 12))
                    .foregroundStyle(SparkCleanTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                Button("Install command-line utility") { installer.install() }
                    .buttonStyle(.borderedProminent)
                    .tint(SparkCleanTheme.accent)
                Text("")
                    .font(.system(size: 11))
                    .foregroundStyle(SparkCleanTheme.textTertiary)

            case .installing:
                Text("Installing via \(installer.method?.label ?? "installer")…")
                    .font(.system(size: 12))
                    .foregroundStyle(SparkCleanTheme.textSecondary)
                InstallerOutputLog(lines: installer.outputLines)

            case .failed(let reason):
                Label("Install failed", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SparkCleanTheme.caution)
                Text(reason)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SparkCleanTheme.textTertiary)
                    .lineLimit(4)
                    .frame(maxWidth: 420)
                InstallerOutputLog(lines: installer.outputLines)
                HStack(spacing: 10) {
                    Button("Retry") { installer.install() }
                        .buttonStyle(.borderedProminent)
                        .tint(SparkCleanTheme.accent)
                    Button("Check again") { recheckCLI() }
                        .buttonStyle(.bordered)
                }

            case .installed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(SparkCleanTheme.healthy)
                Text("Command-line utility installed")
                    .font(.system(size: 15, weight: .semibold))
                Button("Continue") { advance() }
                    .buttonStyle(.borderedProminent)
                    .tint(SparkCleanTheme.accent)

            case .checking:
                Text("Checking…")
                    .font(.system(size: 12))
                    .foregroundStyle(SparkCleanTheme.textSecondary)
            }
        }
    }

    private func recheckCLI() {
        Task { @MainActor in
            let client = SparkCleanClient()
            do {
                let found = try client.locate()
                let version = await client.version(of: found)
                cliStatus = CLICheckResult(found: true, version: version, path: found.url.path)
                installer.recheck()
            } catch {
                cliStatus = CLICheckResult(found: false, version: nil, path: nil)
            }
        }
    }

    /// Live installer output log with auto-scroll.
    struct InstallerOutputLog: View {
        let lines: [SparkCleanInstaller.ProgressLine]

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { line in
                            Text(line.text)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(SparkCleanTheme.textSecondary)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 130)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SparkCleanTheme.border))
                .onChange(of: lines.count) { _, _ in
                    if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .accessibilityLabel("Installer output log")
            }
        }
    }

    private var finish: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "menubar.dock.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(SparkCleanTheme.accent)
            Text("Menu bar monitor")
                .font(.system(size: 18, weight: .bold))
            Text("Keep a compact CPU / memory / disk / network readout in your menu bar, independent of the main window.")
                .font(.system(size: 12))
                .foregroundStyle(SparkCleanTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Toggle("Enable menu bar monitor", isOn: $menuBarEnabled)
                .toggleStyle(.switch)
            Spacer()
        }
    }

    private func advance() {
        if step == 0 {
            step = 1
            recheckCLI()
        } else {
            step += 1
        }
    }
}
