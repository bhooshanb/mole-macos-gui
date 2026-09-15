import SwiftUI

/// First-run experience: detect the CLI, install it if missing, explain
/// capabilities, configure the menu bar monitor, finish setup.
struct WelcomeView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var cliStatus: CLICheckResult?
    @State private var menuBarEnabled = MolePreferences.shared.menuBarEnabled
    @StateObject private var installer = MoleInstaller()

    struct CLICheckResult {
        var found: Bool
        var version: String?
        var path: String?
    }

    var body: some View {
        // Step content and the navigation bar live in separate fixed regions
        // so the buttons never shift when step content changes size (e.g.
        // when CLI detection text appears).
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: intro
                case 1: detection
                default: finish
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(MoleTheme.border)

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                if step < 2 {
                    Button(step == 0 ? "Get Started" : "Continue") { advance() }
                        .buttonStyle(.borderedProminent)
                        .tint(MoleTheme.accent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(step == 1 && cliStatus?.found != true)
                } else {
                    Button("Finish") {
                        MolePreferences.shared.menuBarEnabled = menuBarEnabled
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MoleTheme.accent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(MoleTheme.panel.opacity(0.5))
        }
        .frame(width: 520, height: 480)
        .background(
            LinearGradient(colors: [MoleTheme.warmPanel, MoleTheme.panel],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var intro: some View {
        VStack(spacing: 18) {
            Spacer()
            MoleOrb()
                .frame(width: 160, height: 160)
            Text("Welcome to Mole")
                .font(MoleTheme.metric(30))
                .foregroundStyle(MoleTheme.textPrimary)
            Text("Clean, optimize, analyze, and monitor your Mac.")
                .font(.system(size: 14))
                .foregroundStyle(MoleTheme.textSecondary)
            VStack(alignment: .leading, spacing: 10) {
                featureRow("sparkles", "Clean", "Preview and remove caches, logs, and trash — always dry-run first.")
                featureRow("app.badge.minus", "Apps", "Uninstall applications with Mole's file-accurate plans.")
                featureRow("gauge.with.needle", "Optimize", "Refresh caches and services with skip reasons you can read.")
                featureRow("chart.pie", "Analyze", "Treemap of what's eating your disk, powered by mo analyze --json.")
                featureRow("waveform.path.ecg", "Status", "Live health dashboard streamed from Mole's warm collector.")
            }
            Spacer()
        }
    }

    private func featureRow(_ icon: String, _ title: String, _ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(MoleTheme.accent)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 70, alignment: .leading)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(MoleTheme.textSecondary)
            Spacer()
        }
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
                ProgressView("Detecting Mole CLI…")
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func detectedView(_ status: CLICheckResult) -> some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 44))
            .foregroundStyle(MoleTheme.healthy)
        Text("Mole CLI detected")
            .font(.system(size: 18, weight: .bold))
        if let version = status.version {
            Text(version)
                .font(MoleTheme.mono)
                .foregroundStyle(MoleTheme.textSecondary)
        }
        if let path = status.path {
            Text(path)
                .font(MoleTheme.mono)
                .foregroundStyle(MoleTheme.textTertiary)
        }
        Text("Mole will run the real `mo` commands under the hood. Nothing is deleted without your confirmation, and every cleanup starts as a dry-run preview.")
            .font(.system(size: 12))
            .foregroundStyle(MoleTheme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 400)
    }

    /// Missing CLI: offer a one-click install with live progress.
    private var missingCLIView: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.dotted")
                .font(.system(size: 44))
                .foregroundStyle(MoleTheme.caution)
            Text("Mole CLI not found")
                .font(.system(size: 18, weight: .bold))

            switch installer.phase {
            case .idle:
                Text("Mole.app needs the Mole command-line engine. Install it now — Homebrew is used when available, otherwise the official install script runs.")
                    .font(.system(size: 12))
                    .foregroundStyle(MoleTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                Button("Install Mole CLI") { installer.install() }
                    .buttonStyle(.borderedProminent)
                    .tint(MoleTheme.accent)
                Text("Prefer manual install? Run `brew install mole` in Terminal.")
                    .font(.system(size: 11))
                    .foregroundStyle(MoleTheme.textTertiary)

            case .installing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Installing via \(installer.method?.label ?? "installer")…")
                        .font(.system(size: 12))
                        .foregroundStyle(MoleTheme.textSecondary)
                }
                InstallerOutputLog(lines: installer.outputLines)

            case .failed(let reason):
                Label("Install failed", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MoleTheme.caution)
                Text(reason)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MoleTheme.textTertiary)
                    .lineLimit(4)
                    .frame(maxWidth: 420)
                InstallerOutputLog(lines: installer.outputLines)
                HStack(spacing: 10) {
                    Button("Retry") { installer.install() }
                        .buttonStyle(.borderedProminent)
                        .tint(MoleTheme.accent)
                    Button("Check again") { recheckCLI() }
                        .buttonStyle(.bordered)
                }

            case .installed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(MoleTheme.healthy)
                Text("Mole CLI installed")
                    .font(.system(size: 15, weight: .semibold))
                Button("Continue") { advance() }
                    .buttonStyle(.borderedProminent)
                    .tint(MoleTheme.accent)

            case .checking:
                ProgressView("Checking…")
            }
        }
    }

    private func recheckCLI() {
        Task { @MainActor in
            let client = MoleClient()
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
        let lines: [MoleInstaller.ProgressLine]

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { line in
                            Text(line.text)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(MoleTheme.textSecondary)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 130)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MoleTheme.border))
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
                .foregroundStyle(MoleTheme.accent)
            Text("Menu bar monitor")
                .font(.system(size: 18, weight: .bold))
            Text("Keep a compact CPU / memory / disk / network readout in your menu bar, independent of the main window.")
                .font(.system(size: 12))
                .foregroundStyle(MoleTheme.textSecondary)
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
