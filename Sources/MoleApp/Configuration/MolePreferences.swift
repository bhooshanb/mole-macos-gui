import Foundation

/// User preferences persisted in the app's own domain.
/// Mole's protection model stays in Mole's config files; these keys only cover
/// presentation and app behavior.
final class MolePreferences: ObservableObject {
    static let shared = MolePreferences()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Keys {
        static let firstLaunch = "hasCompletedFirstLaunch"
        static let menuBarEnabled = "menuBarMonitorEnabled"
        static let statusInterval = "statusWatchInterval"
        static let statusProcessMonitoring = "statusProcessMonitoring"
        static let analyzeDefaultPath = "analyzeDefaultPath"
        static let confirmBeforeClean = "confirmBeforeClean"
        static let confirmBeforeUninstall = "confirmBeforeUninstall"
        static let cliPathOverride = "moleCLIPathOverride"
        static let debugLogging = "debugLogging"
        static let cleanWatchTotalBytes = "cleanWatchTotalBytes"
        static let cleanWatchSessionCount = "cleanWatchSessionCount"
        static let cleanWatchUninstallCount = "cleanWatchUninstallCount"
        static let cleanWatchOptimizeCount = "cleanWatchOptimizeCount"
    }

    var isFirstLaunch: Bool {
        get { !defaults.bool(forKey: Keys.firstLaunch) }
        set { defaults.set(!newValue, forKey: Keys.firstLaunch) }
    }

    var menuBarEnabled: Bool {
        get { defaults.object(forKey: Keys.menuBarEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.menuBarEnabled) }
    }

    /// Mole's watch interval string, e.g. "2s".
    var statusWatchInterval: String {
        get { defaults.string(forKey: Keys.statusInterval) ?? "2s" }
        set { defaults.set(newValue, forKey: Keys.statusInterval) }
    }

    var statusProcessMonitoring: Bool {
        get { defaults.object(forKey: Keys.statusProcessMonitoring) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.statusProcessMonitoring) }
    }

    var analyzeDefaultPath: String {
        get { defaults.string(forKey: Keys.analyzeDefaultPath) ?? "" }
        set { defaults.set(newValue, forKey: Keys.analyzeDefaultPath) }
    }

    var confirmBeforeClean: Bool {
        get { defaults.object(forKey: Keys.confirmBeforeClean) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.confirmBeforeClean) }
    }

    var confirmBeforeUninstall: Bool {
        get { defaults.object(forKey: Keys.confirmBeforeUninstall) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.confirmBeforeUninstall) }
    }

    var cliPathOverride: String {
        get { defaults.string(forKey: Keys.cliPathOverride) ?? "" }
        set { defaults.set(newValue, forKey: Keys.cliPathOverride) }
    }

    var debugLogging: Bool {
        get { defaults.bool(forKey: Keys.debugLogging) }
        set { defaults.set(newValue, forKey: Keys.debugLogging) }
    }

    // Clean Watch summary counters (accumulated from mo history sessions).
    var cleanWatchTotalBytes: Int64 {
        get { Int64(defaults.double(forKey: Keys.cleanWatchTotalBytes)) }
        set { defaults.set(Double(newValue), forKey: Keys.cleanWatchTotalBytes) }
    }

    var cleanWatchSessionCount: Int {
        get { defaults.integer(forKey: Keys.cleanWatchSessionCount) }
        set { defaults.set(newValue, forKey: Keys.cleanWatchSessionCount) }
    }

    var cleanWatchUninstallCount: Int {
        get { defaults.integer(forKey: Keys.cleanWatchUninstallCount) }
        set { defaults.set(newValue, forKey: Keys.cleanWatchUninstallCount) }
    }

    var cleanWatchOptimizeCount: Int {
        get { defaults.integer(forKey: Keys.cleanWatchOptimizeCount) }
        set { defaults.set(newValue, forKey: Keys.cleanWatchOptimizeCount) }
    }
}
