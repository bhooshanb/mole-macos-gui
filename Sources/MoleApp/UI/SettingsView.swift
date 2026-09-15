import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = MolePreferences.shared
    @State private var whitelist: [String] = []
    @State private var newRule = ""
    @State private var cliVersion: String? = nil
    @State private var cliVersionFailed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                generalTab
                    .tabItem { Label("General", systemImage: "gearshape") }
                cleaningTab
                    .tabItem { Label("Cleaning", systemImage: "sparkles") }
                analyzeTab
                    .tabItem { Label("Analyze", systemImage: "chart.pie") }
                statusTab
                    .tabItem { Label("Status", systemImage: "waveform.path.ecg") }
                advancedTab
                    .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
            }
            .padding(12)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 560, height: 480)
        .background(MoleTheme.panel)
        .onAppear {
            whitelist = MoleClient().readWhitelist()
            fetchCLIVersion()
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
                Text("Mole's protected locations live in the CLI's own whitelist files (~/.config/mole/whitelist and whitelist_optimize), shared with the terminal. Edit them below or with `mo clean --whitelist`.")
                    .font(.system(size: 11))
                    .foregroundStyle(MoleTheme.textSecondary)
            }
        }
        .padding(16)
    }

    // MARK: Cleaning

    private var cleaningTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Protected caches (mo clean --whitelist)")
            Text("These patterns are passed to Mole verbatim; anything matching them is never touched. One glob per line.")
                .font(.system(size: 11))
                .foregroundStyle(MoleTheme.textSecondary)

            List {
                ForEach(whitelist, id: \.self) { rule in
                    Text(rule)
                        .font(MoleTheme.mono)
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
                    .font(MoleTheme.mono)
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
            Text("External volumes are only analyzed when explicitly requested — matching Mole's own rule. Use the Volumes shortcut or choose a folder.")
                .font(.system(size: 11))
                .foregroundStyle(MoleTheme.textSecondary)
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
            Text("Lower intervals cost more CPU because Mole's collector samples more often.")
                .font(.system(size: 11))
                .foregroundStyle(MoleTheme.textSecondary)
            Toggle("Process monitoring (top processes, zombies)", isOn: $prefs.statusProcessMonitoring)
            Toggle("Show menu bar monitor", isOn: $prefs.menuBarEnabled)
        }
        .padding(16)
    }

    // MARK: Advanced

    private var advancedTab: some View {
        Form {
            TextField("Mole CLI path override", text: $prefs.cliPathOverride)
                .font(MoleTheme.mono)
            Text("Leave empty to auto-detect (/usr/local/bin/mo, /opt/homebrew/bin/mo, ~/.local/bin/mo, PATH).")
                .font(.system(size: 11))
                .foregroundStyle(MoleTheme.textSecondary)
            Toggle("Debug logging", isOn: $prefs.debugLogging)
            HStack {
                Button("Open Logs") { openLogs() }
                Button("Reset Preferences") { resetPreferences() }
                    .foregroundStyle(MoleTheme.danger)
            }
            Section("CLI version") {
                if let cliVersion {
                    Text(cliVersion)
                        .font(MoleTheme.mono)
                        .foregroundStyle(MoleTheme.textSecondary)
                } else if cliVersionFailed {
                    Label("Mole CLI not found — check the path override or install it via onboarding.",
                          systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(MoleTheme.caution)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(16)
    }

    private func fetchCLIVersion() {
        let client = MoleClient()
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
        let appLogDir = NSString(string: "~/Library/Logs/MoleApp").expandingTildeInPath
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
        let moleLog = NSString(string: "~/Library/Logs/mole/operations.log").expandingTildeInPath
        if fm.fileExists(atPath: moleLog) {
            NSWorkspace.shared.open(URL(fileURLWithPath: moleLog))
        }
    }

    private func resetPreferences() {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let defaults = UserDefaults(suiteName: bundleID) else { return }
        defaults.removePersistentDomain(forName: bundleID)
    }
}
