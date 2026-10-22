import Foundation

/// Single point of process execution for the app.
/// All Mole CLI invocations go through this runner: async execution, streaming
/// output, cancellation, timeouts, and controlled environment.
protocol ProcessRunning: Sendable {
    /// Run a command to completion, capturing stdout/stderr.
    func run(
        _ executable: String,
        arguments: [String],
        workingDirectory: String?,
        timeout: TimeInterval?,
        environment: [String: String]?
    ) async throws -> ProcessResult

    /// Run a command with a stdin payload (used for uninstall confirmations).
    func runWithStdin(
        _ executable: String,
        arguments: [String],
        stdin: Data,
        timeout: TimeInterval?,
        environment: [String: String]?
    ) async throws -> ProcessResult
    /// Stream stdout line by line until the process exits or the task is cancelled.
    func streamLines(
        _ executable: String,
        arguments: [String],
        environment: [String: String]?
    ) -> AsyncThrowingStream<String, Error>
}

struct ProcessResult: Sendable, Equatable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var truncated: Bool
    var timedOut: Bool
    var wasCancelled: Bool

    var succeeded: Bool { exitCode == 0 && !timedOut && !wasCancelled }
    var outputData: Data { Data(stdout.utf8) }
}

enum ProcessError: Error, Equatable {
    case launchFailed(String)
    case timedOut
    case cancelled
    case nonZeroExit(code: Int32, stderr: String)
}

extension ProcessRunning {
    /// Convenience overload with default options.
    func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        try await run(
            executable, arguments: arguments, workingDirectory: nil,
            timeout: timeout, environment: nil)
    }

    /// Convenience overload with default options.
    func runWithStdin(
        _ executable: String,
        arguments: [String],
        stdin: Data,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        try await runWithStdin(
            executable, arguments: arguments, stdin: stdin,
            timeout: timeout, environment: nil)
    }

    /// Convenience overload with default options.
    func streamLines(
        _ executable: String,
        arguments: [String]
    ) -> AsyncThrowingStream<String, Error> {
        streamLines(executable, arguments: arguments, environment: nil)
    }
}

/// Foundation-based implementation. Deliberately the only place in the app
/// that spawns subprocesses.
struct FoundationProcessRunner: ProcessRunning {
    /// Hard cap on captured output so runaway commands cannot exhaust memory.
    private let maxCapturedBytes = 8 * 1_024 * 1_024

    func run(
        _ executable: String,
        arguments: [String],
        workingDirectory: String? = nil,
        timeout: TimeInterval? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        try await runInternal(
            executable, arguments: arguments, workingDirectory: workingDirectory,
            timeout: timeout, environment: environment, stdin: nil)
    }

    func runWithStdin(
        _ executable: String,
        arguments: [String],
        stdin: Data,
        timeout: TimeInterval? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        try await runInternal(
            executable, arguments: arguments, workingDirectory: nil,
            timeout: timeout, environment: environment, stdin: stdin)
    }

    private func runInternal(
        _ executable: String,
        arguments: [String],
        workingDirectory: String?,
        timeout: TimeInterval?,
        environment: [String: String]?,
        stdin: Data?
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        var env = ProcessEnvironment.base
        if let environment { env.merge(environment) { _, new in new } }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if let stdin {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            stdinPipe.fileHandleForWriting.write(stdin)
            try? stdinPipe.fileHandleForWriting.close()
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        do {
            try process.run()
        } catch {
            throw ProcessError.launchFailed("\(executable): \(error.localizedDescription)")
        }

        // Capture output concurrently so large pipes never deadlock.
        let stdoutTask = Task.detached { Self.readData(stdoutPipe.fileHandleForReading, cap: maxCapturedBytes) }
        let stderrTask = Task.detached { Self.readData(stderrPipe.fileHandleForReading, cap: maxCapturedBytes) }

        let timedOut = await Self.waitWithTimeout(process, timeout: timeout)

        if Task.isCancelled {
            if process.isRunning { process.terminate() }
            _ = await stdoutTask.value
            _ = await stderrTask.value
            throw ProcessError.cancelled
        }

        if timedOut {
            process.terminate()
            // Grace window, then SIGKILL.
            for _ in 0..<20 where process.isRunning {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            _ = await stdoutTask.value
            _ = await stderrTask.value
            throw ProcessError.timedOut
        }

        let stdout = await stdoutTask.value
        let stderr = await stderrTask.value

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self),
            truncated: stdout.count >= maxCapturedBytes || stderr.count >= maxCapturedBytes,
            timedOut: false,
            wasCancelled: false)
    }

    private static func readData(_ handle: FileHandle, cap: Int) -> Data {
        var data = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count >= cap {
                // Drain quietly past the cap without storing more.
                continue
            }
        }
        return data
    }

    private static func waitWithTimeout(_ process: Process, timeout: TimeInterval?) async -> Bool {
        guard let timeout, timeout > 0 else {
            process.waitUntilExit()
            return false
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    func streamLines(
        _ executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            var env = ProcessEnvironment.base
            if let environment { env.merge(environment) { _, new in new } }
            process.environment = env
            process.standardInput = FileHandle.nullDevice

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            continuation.onTermination = { [weak process] _ in
                if let process, process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: ProcessError.launchFailed(error.localizedDescription))
                return
            }

            let reader = LineReader(handle: pipe.fileHandleForReading)
            let readTask = Task {
                for await line in reader.lines() {
                    continuation.yield(line)
                }
            }

            Task.detached {
                process.waitUntilExit()
                readTask.cancel()
                if process.terminationStatus != 0 && process.terminationReason != .uncaughtSignal {
                    continuation.finish(
                        throwing: ProcessError.nonZeroExit(
                            code: process.terminationStatus, stderr: ""))
                } else {
                    continuation.finish()
                }
            }
        }
    }
}

enum ProcessEnvironment {
    /// Mole's bash scripts expect LC_ALL=C for stable parsing, and a clean PATH
    /// with the common Homebrew prefixes so `mo` and its dependencies resolve.
    static var base: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "C"
        env["LANG"] = "C"
        env.removeValue(forKey: "MOLE_TEST_MODE")
        env.removeValue(forKey: "MOLE_TEST_NO_AUTH")
        return env
    }
}

/// Buffered line reader over a FileHandle, usable from any executor.
struct LineReader {
    let handle: FileHandle

    func lines() -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task.detached {
                var buffer = Data()
                while !Task.isCancelled {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
                        buffer.removeSubrange(buffer.startIndex...newlineIndex)
                        continuation.yield(String(decoding: lineData, as: UTF8.self))
                    }
                }
                if !buffer.isEmpty {
                    continuation.yield(String(decoding: buffer, as: UTF8.self))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
