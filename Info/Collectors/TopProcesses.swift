import Foundation
import Observation

struct ProcRow: Identifiable, Sendable, Equatable {
    let id: Int        // pid
    let name: String
    let detail: String // "42%" or "1.2 GB"
}

/// Lazily loads the top CPU/memory processes by shelling out to `ps`, but ONLY
/// while a panel is visible (started in `.onAppear`, stopped in `.onDisappear`).
/// When the popover is closed this does nothing — no background process churn.
@MainActor
@Observable
final class TopProcessesModel {
    var rows: [ProcRow] = []
    private var task: Task<Void, Never>?
    private let kind: MetricKind

    init(kind: MetricKind) { self.kind = kind }

    deinit { MainActor.assumeIsolated { task?.cancel() } }

    func start() {
        guard task == nil else { return }
        let kind = self.kind
        task = Task { [weak self] in
            while !Task.isCancelled {
                let rows = await Self.fetch(kind: kind)
                if Task.isCancelled { return }
                self?.rows = rows
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private static func fetch(kind: MetricKind) async -> [ProcRow] {
        let args = kind == .cpu
            ? ["-Aceo", "pid=,pcpu=,comm=", "-r"]
            : ["-Aceo", "pid=,rss=,comm=", "-m"]
        guard let out = await Shell.run("/bin/ps", args, timeout: 1.5) else { return [] }
        return parse(out, kind: kind, limit: 5)
    }

    /// Pure parser for `ps` output (unit-testable, no system calls).
    /// Lines look like: `<pid> <value> <comm...>` where value is %CPU or RSS(KB).
    nonisolated static func parse(_ output: String, kind: MetricKind, limit: Int) -> [ProcRow] {
        var rows: [ProcRow] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = Int(parts[0]) else { continue }
            let name = parts[2...].joined(separator: " ")
            if kind == .cpu, let pct = Double(parts[1]) {
                rows.append(ProcRow(id: pid, name: name, detail: "\(Int(pct))%"))
            } else if kind != .cpu, let rssKB = Double(parts[1]) {
                rows.append(ProcRow(id: pid, name: name, detail: Fmt.bytes(UInt64(rssKB * 1024))))
            }
            if rows.count == limit { break }
        }
        return rows
    }
}

/// Minimal process helper with timeout + cancellation. It runs work off-main and
/// terminates the subprocess if the panel closes while `ps` is still running.
enum Shell {
    static func run(_ path: String, _ args: [String], timeout: TimeInterval) async -> String? {
        let box = ProcessBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: runSync(path, args, timeout: timeout, box: box))
                }
            }
        } onCancel: {
            box.cancel()
        }
    }

    private static func runSync(_ path: String, _ args: [String], timeout: TimeInterval, box: ProcessBox) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        guard !box.isCancelled else { return nil }
        do {
            try process.run()
            box.process = process
        } catch {
            return nil
        }
        let output = ProcessOutput()
        let outputGroup = DispatchGroup()
        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            output.set(stdout.fileHandleForReading.readDataToEndOfFile())
            outputGroup.leave()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if box.isCancelled || Date() >= deadline {
                process.terminate()
                process.waitUntilExit()
                _ = outputGroup.wait(timeout: .now() + 0.5)
                return nil
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard !box.isCancelled, process.terminationStatus == 0 else { return nil }
        guard outputGroup.wait(timeout: .now() + 0.5) == .success else { return nil }
        return String(data: output.data, encoding: .utf8)
    }
}

private final class ProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var _data = Data()

    var data: Data { lock.withLock { _data } }

    func set(_ data: Data) {
        lock.withLock { _data = data }
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _process: Process?
    private var _cancelled = false

    var process: Process? {
        get { lock.withLock { _process } }
        set { lock.withLock { _process = newValue } }
    }

    var isCancelled: Bool { lock.withLock { _cancelled } }

    func cancel() {
        let process = lock.withLock { () -> Process? in
            _cancelled = true
            return _process
        }
        process?.terminate()
    }
}
