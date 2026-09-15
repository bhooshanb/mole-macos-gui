import Testing
import Foundation
@testable import Mole

@Suite
struct MoleJSONDecodingTests {
    // Captured from `mo status --json` on Mole 1.53.0.
    static let statusJSON = """
    {
      "collected_at": "2026-09-15T17:04:23.565843+05:30",
      "host": "MacM1.local",
      "platform": "darwin 26.6.2",
      "uptime": "20d 4h",
      "uptime_seconds": 1743682,
      "procs": 544,
      "hardware": {"model": "MacBook Air", "cpu_model": "Apple M1", "total_ram": "8.0 GB", "disk_size": "228.3 GB", "os_version": "macOS 26.6.2", "refresh_rate": ""},
      "health_score": 86,
      "health_score_msg": "Excellent: Restart Recommended",
      "cpu": {"usage": 13.29, "per_core": [19.75, 0], "per_core_estimated": false, "load1": 2.58, "load5": 2.98, "load15": 2.89, "core_count": 8, "logical_cpu": 8, "p_core_count": 4, "e_core_count": 4},
      "gpu": [{"name": "kHW_AppleM1Item", "usage": -1, "memory_used": 0, "memory_total": 0, "core_count": 7, "note": "sppci_vendor_Apple"}],
      "memory": {"used": 6766084096, "total": 8589934592, "available": 1823850496, "used_percent": 78.76, "swap_used": 2505375744, "swap_total": 4294967296, "cached": 1105199104, "pressure": ""},
      "disks": [{"mount": "/", "device": "/dev/disk3s1s1", "used": 209918911006, "total": 245107195904, "used_percent": 85.64, "fstype": "apfs", "external": false, "smart_status": "verified", "purgeable": 716733922}],
      "trash_size": 2280031131,
      "trash_approx": false,
      "disk_io": {"read_rate": 0, "write_rate": 0},
      "network": [{"name": "en0", "rx_rate_mbs": 0.0006, "tx_rate_mbs": 0.003, "ip": "10.10.10.4"}],
      "network_history": {"rx_history": [0.1], "tx_history": [0.2]},
      "proxy": {"enabled": true, "type": "TUN", "host": "utun0+"},
      "batteries": [{"percent": 86, "status": "charging", "time_left": "", "health": "Good", "cycle_count": 612, "capacity": 84}],
      "thermal": {"cpu_temp": 0, "gpu_temp": 0, "battery_temp": 31.11, "fan_speed": 0, "fan_count": 0, "system_power": 7.099, "adapter_power": 8, "battery_power": -1.223},
      "sensors": null,
      "bluetooth": [],
      "top_processes": [{"pid": 175, "ppid": 1, "name": "WindowServer", "command": "WindowServer", "cpu": 46.8, "memory": 1, "memory_bytes": 83755008}],
      "process_collected_at": "2026-09-15T17:04:33.538169+05:30",
      "process_stale": false,
      "zombie_count": 11,
      "zombie_parents": [{"pid": 925, "name": "RustDesk", "count": 11}],
      "zombie_parents_complete": true,
      "process_watch": {"enabled": true, "cpu_threshold": 100, "window": "5m0s"},
      "process_alerts": []
    }
    """

    @Test func metricsSnapshotDecodingFromRealCLIOutput() throws {
        let snapshot = try MoleJSON.decode(MetricsSnapshot.self, from: Data(Self.statusJSON.utf8))
        #expect(snapshot.healthScore == 86)
        #expect(snapshot.hardware?.cpuModel == "Apple M1")
        #expect(snapshot.cpu?.logicalCpu == 8)
        #expect(snapshot.disks?.first?.smartStatus == "verified")
        #expect(snapshot.batteries?.first?.cycleCount == 612)
        #expect(snapshot.zombieCount == 11)
        #expect(snapshot.zombieParents?.first?.name == "RustDesk")
        #expect(snapshot.processStale == false)
        #expect(snapshot.processCollectedAt != nil)
    }

    @Test func metricsSnapshotOmittedProcessFields() throws {
        // Before a process sample exists, Mole omits these fields entirely.
        let json = """
        {"collected_at": "2026-09-15T17:04:23+05:30", "health_score": 90, "zombie_parents": null}
        """
        let snapshot = try MoleJSON.decode(MetricsSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.processCollectedAt == nil)
        #expect(snapshot.processStale == nil)
        #expect(snapshot.zombieCount == nil)
        #expect(snapshot.zombieParents == nil)
        #expect(snapshot.zombieParentsComplete == nil)
    }

    @Test func analyzeReportDecoding() throws {
        let json = """
        {
          "path": "/private/tmp",
          "overview": false,
          "entries": [
            {"name": "mo-clean-dry.txt", "path": "/private/tmp/mo-clean-dry.txt", "size": 3589, "is_dir": false, "last_access": "2026-09-15T11:32:09Z"},
            {"name": "RustDesk-service", "path": "/private/tmp/RustDesk-service", "size": 0, "is_dir": true}
          ],
          "large_files": [{"name": "backup.zip", "path": "/private/tmp/backup.zip", "size": 8796093022}],
          "total_size": 3589,
          "total_files": 2
        }
        """
        let report = try MoleJSON.decode(AnalyzeReport.self, from: Data(json.utf8))
        #expect(report.overview == false)
        #expect(report.entries.count == 2)
        #expect(report.entries.first?.lastAccess == "2026-09-15T11:32:09Z")
        #expect(report.largeFiles?.first?.size == 8796093022)
    }

    @Test func analyzeOverviewInsightFlag() throws {
        let json = """
        {"path": "/", "overview": true, "entries": [{"name": "Home", "path": "/Users/x", "size": 100, "is_dir": true, "insight": true, "cleanable": false}], "total_size": 100}
        """
        let report = try MoleJSON.decode(AnalyzeReport.self, from: Data(json.utf8))
        #expect(report.entries.first?.insight == true)
    }

    @Test func historyReportDecoding() throws {
        let json = """
        {
          "logs": {"operations": "/Users/x/Library/Logs/mole/operations.log", "deletions": "/Users/x/Library/Logs/mole/deletions.log"},
          "limit": 3,
          "sessions": [
            {"command": "clean", "started_at": "2026-09-13 14:46:03", "ended_at": "2026-09-13 14:52:44", "items": 638, "size": "2.44GB", "operation_count": 768, "failed_tasks": 0,
             "actions": {"removed": 655, "trashed": 0, "skipped": 113, "failed": 0, "rebuilt": 0, "other": 0}}
          ],
          "deletions": [
            {"timestamp": "2026-09-13 14:47:00", "mode": "permanent", "status": "OK", "size_kb": 1900, "path": "/private/var/log/old.asl"},
            {"timestamp": "2026-09-13 14:48:00", "mode": "trash", "status": "OK", "size_kb": null, "path": "/tmp/unknown-size"}
          ]
        }
        """
        let report = try MoleJSON.decode(HistoryReport.self, from: Data(json.utf8))
        #expect(report.sessions?.first?.command == "clean")
        #expect(report.sessions?.first?.actions?.removed == 655)
        #expect(report.deletions?.count == 2)
        // sizeKb is Int?? : outer optional from key presence, inner from JSON null.
        #expect(report.deletions?.first?.sizeKb != nil)
        #expect(report.deletions?.first?.sizeKb ?? nil == 1900)
        #expect(report.deletions?.last?.sizeKb ?? nil == nil)
    }

    @Test func appInventoryDecoding() throws {
        let json = """
        [
          {"name": "Mos", "bundle_id": "com.caldis.Mos", "source": "App", "uninstall_name": "Mos", "path": "/Applications/Mos.app", "size": "--"},
          {"name": "AppCleaner", "bundle_id": "net.freemacsoft.AppCleaner", "source": "App", "uninstall_name": "AppCleaner", "path": "/Applications/AppCleaner.app", "size": "8.4MB"}
        ]
        """
        let apps = try MoleJSON.decode([AppInventoryItem].self, from: Data(json.utf8))
        #expect(apps.count == 2)
        #expect(apps[0].bundleID == "com.caldis.Mos")
        #expect(apps[1].size == "8.4MB")
    }

    @Test func historySessionDateParsing() {
        let date = MoleJSON.decodeSessionDate("2026-09-13 14:46:03")
        #expect(date != nil)
        #expect(MoleJSON.decodeSessionDate("not a date") == nil)
    }
}
