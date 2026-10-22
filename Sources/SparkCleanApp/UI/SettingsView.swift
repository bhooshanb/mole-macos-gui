import SwiftUI
import AppKit

/// Tabs in the Settings window; also used to deep-link (e.g. the
/// "Upgrade to PRO" popup jumps straight to License).
enum SettingsTab: Hashable {
    case general, license, cleaning, analyze, status, advanced
}

struct SettingsView: View {
    @ObservedObject private var prefs = SparkCleanPreferences.shared
    @ObservedObject private var license = SparkCleanLicenseManager.shared
    @State private var selectedTab: SettingsTab
    @State private var licenseKey = ""
    @State private var whitelist: [String] = []
    @State private var newRule = ""
    @State private var cliVersion: String? = nil
    @State private var cliVersionFailed = false
    @Environment(\.dismiss) private var dismiss

    init(tab: SettingsTab = .general) {
        _selectedTab = State(initialValue: tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                generalTab
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(SettingsTab.general)
                licenseTab
                    .tabItem { Label("License", systemImage: "key.fill") }
                    .tag(SettingsTab.license)
                cleaningTab
                    .tabItem { Label("Cleaning", systemImage: "sparkles") }
                    .tag(SettingsTab.cleaning)
                analyzeTab
                    .tabItem { Label("Analyze", systemImage: "chart.pie") }
                    .tag(SettingsTab.analyze)
                statusTab
                    .tabItem { Label("Status", systemImage: "waveform.path.ecg") }
                    .tag(SettingsTab.status)
                advancedTab
                    .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
                    .tag(SettingsTab.advanced)
            }
            .padding(12)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 600, height: 500)
        .background(SparkCleanTheme.panel)
        .onAppear {
            whitelist = SparkCleanClient().readWhitelist()
            fetchCLIVersion()
            if license.isActivated {
                Task { await license.validate() }
            }
        }
        .accessibilityLabel("Settings")
    }

    // MARK: General

    private var generalTab: some View {
        Form {
            Toggle("Show menu bar monitor", isOn: $prefs.menuBarEnabled)
            Toggle("Confirm before cleaning", isOn: $prefs.confirmBeforeClean)
            Toggle("Confirm before uninstalling apps", isOn: $prefs.confirmBeforeUninstall)
            Section("About protection") {
                Text("Protected locations live in the CLI whitelist files (~/.config/mole/whitelist and whitelist_optimize), shared with the terminal. Edit them below or with `mo clean --whitelist`.")
                    .font(.system(size: 11))
                    .foregroundStyle(SparkCleanTheme.textSecondary)
            }
        }
        .padding(16)
    }

    // MARK: License

    private var licenseTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: license.isActivated ? "checkmark.seal.fill" : "key.horizontal")
                    .font(.system(size: 22))
                    .foregroundStyle(license.isActivated ? SparkCleanTheme.healthy : SparkCleanTheme.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(license.isActivated ? "SparkClean is activated" : "Activate SparkClean")
                        .font(.system(size: 15, weight: .semibold))
                    Text(license.isActivated
                         ? "Your license is stored securely in this Mac’s Keychain."
                         : "Paste the license key from your Dodo Payments email.")
                        .font(.system(size: 11))
                        .foregroundStyle(SparkCleanTheme.textSecondary)
                }
            }

            if !license.isActivated {
                SecureField("License key", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await activateLicense() } }
                Button {
                    Task { await activateLicense() }
                } label: {
                    if license.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Activate License")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(license.isBusy || licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Button {
                    Task { await license.validate() }
                } label: {
                    if license.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Check License")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(license.isBusy)
            }

            if let message = license.message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(license.messageIsSuccess ? SparkCleanTheme.healthy : SparkCleanTheme.caution)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("SparkClean is distributed under the GNU General Public License, version 3. You may run, study, modify, and redistribute the covered software under its terms. A purchase or activation is not required to use GPL-covered features.")
                    .font(.system(size: 10))
                    .foregroundStyle(SparkCleanTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button("View GPL-3.0 license") {
                        if let url = Bundle.main.url(forResource: "GPL-3.0", withExtension: "txt") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Link("Source code", destination: URL(string: "https://github.com/bhooshanb/mole-macos-gui")!)
                    Link("Optional support license", destination: SparkCleanLicenseManager.purchaseURL)
                }
                .font(.system(size: 10))
            }

            Spacer()
            Text("License activation and checks use the SparkClean website’s secure server. The Dodo API secret is never included in this app.")
                .font(.system(size: 10))
                .foregroundStyle(SparkCleanTheme.textTertiary)
        }
        .padding(20)
    }

    private func activateLicense() async {
        await license.activate(licenseKey: licenseKey)
        if license.isActivated { licenseKey = "" }
    }

    // MARK: Cleaning

    private var cleaningTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Protected caches (mo clean --whitelist)")
            Text("These patterns are passed to the CLI verbatim; anything matching them is never touched. One glob per line.")
                .font(.system(size: 11))
                .foregroundStyle(SparkCleanTheme.textSecondary)

            List {
                ForEach(whitelist, id: \.self) { rule in
                    Text(rule)
                        .font(SparkCleanTheme.mono)
                }
                .onDelete { indexSet in
                    whitelist.remove(atOffsets: indexSet)
                    saveWhitelist()
                }
            }
            .listStyle(.bordered)
            .frame(minHeight: 160)

            HStack {
                TextField("Add pattern, e.g. ~/Library/Caches/com.example*", text: $newRule)
                    .textFieldStyle(.roundedBorder)
                    .font(SparkCleanTheme.mono)
                Button("Add") {
                    guard !newRule.isEmpty else { return }
                    whitelist.append(newRule)
                    newRule = ""
                    saveWhitelist()
                }
                .disabled(newRule.isEmpty)
            }
        }
        .padding(16)
    }

    private func saveWhitelist() {
        let path = NSString(string: "~/.config/mole/whitelist").expandingTildeInPath
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let content = whitelist.joined(separator: "\n") + "\n"
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: Analyze

    private var analyzeTab: some View {
        Form {
            TextField("Default analyze location (empty = overview)", text: $prefs.analyzeDefaultPath)
            Text("External volumes are only analyzed when explicitly requested. Use the Volumes shortcut or choose a folder.")
                .font(.system(size: 11))
                .foregroundStyle(SparkCleanTheme.textSecondary)
        }
        .padding(16)
    }

    // MARK: Status

    private var statusTab: some View {
        Form {
            Picker("Update interval", selection: $prefs.statusWatchInterval) {
                Text("1s").tag("1s")
                Text("2s").tag("2s")
                Text("5s").tag("5s")
            }
            Text("Lower intervals cost more CPU because the collector samples more often.")
                .font(.system(size: 11))
                .foregroundStyle(SparkCleanTheme.textSecondary)
            Toggle("Process monitoring (top processes, zombies)", isOn: $prefs.statusProcessMonitoring)
            Toggle("Show menu bar monitor", isOn: $prefs.menuBarEnabled)
        }
        .padding(16)
    }

    // MARK: Advanced

    private var advancedTab: some View {
        Form {
            TextField("Command-line tool path override", text: $prefs.cliPathOverride)
                .font(SparkCleanTheme.mono)
            Text("Leave empty to auto-detect (/usr/local/bin/mo, /opt/homebrew/bin/mo, ~/.local/bin/mo, PATH).")
                .font(.system(size: 11))
                .foregroundStyle(SparkCleanTheme.textSecondary)
            Toggle("Debug logging", isOn: $prefs.debugLogging)
            HStack {
                Button("Open Logs") { openLogs() }
                Button("Reset Preferences") { resetPreferences() }
                    .foregroundStyle(SparkCleanTheme.danger)
            }
            Section("CLI version") {
                if let cliVersion {
                    Text(cliVersion)
                        .font(SparkCleanTheme.mono)
                        .foregroundStyle(SparkCleanTheme.textSecondary)
                } else if cliVersionFailed {
                    Label("Command-line tool not found — check the path override or install it via onboarding.",
                          systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(SparkCleanTheme.caution)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(16)
    }

    private func fetchCLIVersion() {
        let client = SparkCleanClient()
        Task { @MainActor in
            do {
                let found = try client.locate()
                cliVersion = await client.version(of: found) ?? "version unavailable"
                cliVersionFailed = false
            } catch {
                cliVersion = nil
                cliVersionFailed = true
            }
        }
    }

    private func openLogs() {
        let fm = FileManager.default
        let appLogDir = NSString(string: "~/Library/Logs/SparkCleanApp").expandingTildeInPath
        // Ensure the directory exists — NSWorkspace.open no-ops on missing paths.
        try? fm.createDirectory(atPath: appLogDir, withIntermediateDirectories: true)
        // Seed a file so there's something to see on first open.
        let appLog = appLogDir + "/app.log"
        if !fm.fileExists(atPath: appLog) {
            let stamp = ISO8601DateFormatter().string(from: Date())
            try? "[\(stamp)] Log created. Enable Debug logging to record app activity.\n"
                .write(toFile: appLog, atomically: true, encoding: .utf8)
        }
        if NSWorkspace.shared.open(URL(fileURLWithPath: appLogDir)) { return }
        // Fall back to Mole's own operation log.
        let sparkCleanLog = NSString(string: "~/Library/Logs/mole/operations.log").expandingTildeInPath
        if fm.fileExists(atPath: sparkCleanLog) {
            NSWorkspace.shared.open(URL(fileURLWithPath: sparkCleanLog))
        }
    }

    private func resetPreferences() {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let defaults = UserDefaults(suiteName: bundleID) else { return }
        defaults.removePersistentDomain(forName: bundleID)
    }
}
