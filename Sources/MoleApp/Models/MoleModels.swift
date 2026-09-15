import Foundation

// MARK: - Status (mo status --json / --watch NDJSON)
// Mirrors cmd/status/metrics.go MetricsSnapshot exactly.

struct MetricsSnapshot: Codable, Equatable {
    var collectedAt: Date
    var host: String?
    var platform: String?
    var uptime: String?
    var uptimeSeconds: Int64?
    var procs: Int64?
    var hardware: HardwareInfo?
    var healthScore: Int?
    var healthScoreMsg: String?
    var cpu: CPUStatus?
    var gpu: [GPUStatus]?
    var memory: MemoryStatus?
    var disks: [DiskStatus]?
    var trashSize: Int64?
    var trashApprox: Bool?
    var diskIO: DiskIOStatus?
    var network: [NetworkStatus]?
    var networkHistory: NetworkHistory?
    var proxy: ProxyStatus?
    var batteries: [BatteryStatus]?
    var thermal: ThermalStatus?
    var sensors: [SensorReading]?
    var bluetooth: [BluetoothDevice]?
    var topProcesses: [ProcessInfoEntry]?
    var processCollectedAt: Date?
    var processStale: Bool?
    var zombieCount: Int?
    var zombieParents: [ZombieParent]?
    var zombieParentsComplete: Bool?
    var processWatch: ProcessWatchConfig?
    var processAlerts: [ProcessAlert]?
}

struct HardwareInfo: Codable, Equatable {
    var model: String?
    var cpuModel: String?
    var totalRAM: String?
    var diskSize: String?
    var osVersion: String?
    var refreshRate: String?
}

struct CPUStatus: Codable, Equatable {
    var usage: Double?
    var perCore: [Double]?
    var perCoreEstimated: Bool?
    var load1: Double?
    var load5: Double?
    var load15: Double?
    var coreCount: Int?
    // JSON "logical_cpu"; Foundation's convertFromSnakeCase yields "logicalCpu".
    var logicalCpu: Int?
    var pCoreCount: Int?
    var eCoreCount: Int?
}

struct GPUStatus: Codable, Equatable {
    var name: String?
    var usage: Double?
    var memoryUsed: Double?
    var memoryTotal: Double?
    var coreCount: Int?
    var note: String?
}

struct MemoryStatus: Codable, Equatable {
    var used: Int64?
    var total: Int64?
    var available: Int64?
    var usedPercent: Double?
    var swapUsed: Int64?
    var swapTotal: Int64?
    var cached: Int64?
    var pressure: String?
}

struct DiskStatus: Codable, Equatable {
    var mount: String?
    var device: String?
    var used: Int64?
    var total: Int64?
    var usedPercent: Double?
    var fstype: String?
    var external: Bool?
    var smartStatus: String?
    var purgeable: Int64?
}

struct DiskIOStatus: Codable, Equatable {
    var readRate: Double?
    var writeRate: Double?
}

struct NetworkStatus: Codable, Equatable {
    var name: String?
    // JSON "rx_rate_mbs" / "tx_rate_mbs".
    var rxRateMbs: Double?
    var txRateMbs: Double?
    var ip: String?
}

struct NetworkHistory: Codable, Equatable {
    var rxHistory: [Double]?
    var txHistory: [Double]?
}

struct ProxyStatus: Codable, Equatable {
    var enabled: Bool?
    var type: String?
    var host: String?
}

struct BatteryStatus: Codable, Equatable {
    var percent: Double?
    var status: String?
    var timeLeft: String?
    var health: String?
    var cycleCount: Int?
    var capacity: Int?
}

struct ThermalStatus: Codable, Equatable {
    var cpuTemp: Double?
    var gpuTemp: Double?
    var batteryTemp: Double?
    var fanSpeed: Int?
    var fanCount: Int?
    var systemPower: Double?
    var adapterPower: Double?
    var batteryPower: Double?
}

struct SensorReading: Codable, Equatable {
    var label: String?
    var value: Double?
    var unit: String?
    var note: String?
}

struct BluetoothDevice: Codable, Equatable {
    var name: String?
    var connected: Bool?
    var battery: String?
}

struct ProcessInfoEntry: Codable, Equatable {
    var pid: Int
    var ppid: Int?
    var name: String?
    var command: String?
    var cpu: Double?
    var memory: Double?
    var memoryBytes: Int64?
}

struct ZombieParent: Codable, Equatable {
    var pid: Int
    var name: String?
    var count: Int?
}

struct ProcessWatchConfig: Codable, Equatable {
    var enabled: Bool?
    var cpuThreshold: Double?
    var window: String?
}

struct ProcessAlert: Codable, Equatable {
    var pid: Int
    var name: String?
    var command: String?
    var cpu: Double?
    var threshold: Double?
    var window: String?
    var triggeredAt: Date?
    var status: String?
}

// MARK: - Analyze (mo analyze --json [path])
// Mirrors cmd/analyze/json.go jsonOutput exactly.

struct AnalyzeReport: Codable, Equatable {
    var path: String
    var overview: Bool
    var entries: [AnalyzeEntry]
    var largeFiles: [AnalyzeFileEntry]?
    var totalSize: Int64
    var totalFiles: Int64?
}

struct AnalyzeEntry: Codable, Equatable {
    var name: String
    var path: String
    var size: Int64
    var isDir: Bool
    var insight: Bool?
    var cleanable: Bool?
    var lastAccess: String?
}

struct AnalyzeFileEntry: Codable, Equatable {
    var name: String
    var path: String
    var size: Int64
}

// MARK: - History (mo history --json)
// Mirrors lib/core/history.sh history_render_json exactly.

struct HistoryReport: Codable, Equatable {
    var logs: HistoryLogs?
    var limit: Int?
    var sessions: [HistorySession]?
    var deletions: [HistoryDeletion]?
}

struct HistoryLogs: Codable, Equatable {
    var operations: String?
    var deletions: String?
}

struct HistorySession: Codable, Equatable {
    var command: String?
    var startedAt: String?
    var endedAt: String?
    var items: Int?
    var size: String?
    var operationCount: Int?
    var failedTasks: Int?
    var actions: HistoryActions?
}

struct HistoryActions: Codable, Equatable {
    var removed: Int?
    var trashed: Int?
    var skipped: Int?
    var failed: Int?
    var rebuilt: Int?
    var other: Int?
}

struct HistoryDeletion: Codable, Equatable {
    var timestamp: String?
    var mode: String?
    var status: String?
    // JSON "size_kb"; null when unknown.
    var sizeKb: Int??
    var path: String?
}

// MARK: - App inventory (mo uninstall --list, piped)
// Mirrors bin/uninstall.sh uninstall_list_apps JSON output exactly.

struct AppInventoryItem: Codable, Equatable {
    var name: String
    var bundleID: String
    var source: String
    var uninstallName: String
    var path: String
    var size: String

    // With convertFromSnakeCase, JSON "bundle_id" matches key "bundleId".
    enum CodingKeys: String, CodingKey {
        case name
        case bundleID = "bundleId"
        case source
        case uninstallName = "uninstallName"
        case path
        case size
    }
}
