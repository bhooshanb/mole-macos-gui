import Foundation
import Combine

/// User preferences persisted in the app's own domain.
/// Mole's protection model stays in Mole's config files; these keys only cover
/// presentation and app behavior.
///
/// Observable: every setter sends objectWillChange so views outside the
/// settings sheet (menu bar scene, Status screen, Analyze) react live.
final class SparkCleanPreferences: ObservableObject {
    static let shared = SparkCleanPreferences()

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
        static let cliPathOverride = "sparkCleanCLIPathOverride"
        static let debugLogging = "debugLogging"
        static let cleanWatchTotalBytes = "cleanWatchTotalBytes"
        static let cleanWatchSessionCount = "cleanWatchSessionCount"
        static let cleanWatchUninstallCount = "cleanWatchUninstallCount"
        static let cleanWatchOptimizeCount = "cleanWatchOptimizeCount"
    }

    /// Publisher emitting the current menu-bar setting whenever it changes.
    /// (Computed properties can't be @Published, so this bridges manually.)
    lazy var menuBarEnabledPublisher: AnyPublisher<Bool, Never> = {
        var current = menuBarEnabled
        return objectWillChange
            .map { [weak self] _ in self?.menuBarEnabled ?? current }
            .handleEvents(receiveOutput: { current = $0 })
            .prepend(menuBarEnabled)
            .removeDuplicates()
            .share()
            .eraseToAnyPublisher()
    }()

    // MARK: - Notifying setters

    private func setBool(_ key: String, _ value: Bool) {
        guard defaults.object(forKey: key) as? Bool != value else { return }
        defaults.set(value, forKey: key)
        objectWillChange.send()
    }

    private func setString(_ key: String, _ value: String) {
        guard defaults.string(forKey: key) != value else { return }
        defaults.set(value, forKey: key)
        objectWillChange.send()
    }

    private func setInt(_ key: String, _ value: Int) {
        guard defaults.integer(forKey: key) != value else { return }
        defaults.set(value, forKey: key)
        objectWillChange.send()
    }

    private func setDouble(_ key: String, _ value: Double) {
        guard defaults.double(forKey: key) != value else { return }
        defaults.set(value, forKey: key)
        objectWillChange.send()
    }

    // MARK: - Properties

    var isFirstLaunch: Bool {
        get { !defaults.bool(forKey: Keys.firstLaunch) }
        set {
            let flag = !newValue
            if defaults.bool(forKey: Keys.firstLaunch) != flag {
                defaults.set(flag, forKey: Keys.firstLaunch)
                objectWillChange.send()
            }
        }
    }

    var menuBarEnabled: Bool {
        get { defaults.object(forKey: Keys.menuBarEnabled) as? Bool ?? true }
        set { setBool(Keys.menuBarEnabled, newValue) }
    }

    /// Mole's watch interval string, e.g. "2s".
    var statusWatchInterval: String {
        get { defaults.string(forKey: Keys.statusInterval) ?? "2s" }
        set { setString(Keys.statusInterval, newValue) }
    }

    var statusProcessMonitoring: Bool {
        get { defaults.object(forKey: Keys.statusProcessMonitoring) as? Bool ?? true }
        set { setBool(Keys.statusProcessMonitoring, newValue) }
    }

    var analyzeDefaultPath: String {
        get { defaults.string(forKey: Keys.analyzeDefaultPath) ?? "" }
        set { setString(Keys.analyzeDefaultPath, newValue) }
    }

    var confirmBeforeClean: Bool {
        get { defaults.object(forKey: Keys.confirmBeforeClean) as? Bool ?? true }
        set { setBool(Keys.confirmBeforeClean, newValue) }
    }

    var confirmBeforeUninstall: Bool {
        get { defaults.object(forKey: Keys.confirmBeforeUninstall) as? Bool ?? true }
        set { setBool(Keys.confirmBeforeUninstall, newValue) }
    }

    var cliPathOverride: String {
        get { defaults.string(forKey: Keys.cliPathOverride) ?? "" }
        set { setString(Keys.cliPathOverride, newValue) }
    }

    var debugLogging: Bool {
        get { defaults.bool(forKey: Keys.debugLogging) }
        set { setBool(Keys.debugLogging, newValue) }
    }

    // Clean Watch summary counters (accumulated from mo history sessions).
    var cleanWatchTotalBytes: Int64 {
        get { Int64(defaults.double(forKey: Keys.cleanWatchTotalBytes)) }
        set { setDouble(Keys.cleanWatchTotalBytes, Double(newValue)) }
    }

    var cleanWatchSessionCount: Int {
        get { defaults.integer(forKey: Keys.cleanWatchSessionCount) }
        set { setInt(Keys.cleanWatchSessionCount, newValue) }
    }

    var cleanWatchUninstallCount: Int {
        get { defaults.integer(forKey: Keys.cleanWatchUninstallCount) }
        set { setInt(Keys.cleanWatchUninstallCount, newValue) }
    }

    var cleanWatchOptimizeCount: Int {
        get { defaults.integer(forKey: Keys.cleanWatchOptimizeCount) }
        set { setInt(Keys.cleanWatchOptimizeCount, newValue) }
    }
}
