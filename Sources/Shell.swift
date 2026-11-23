import Foundation

struct CommandResult {
    let code: Int32
    let stdout: String
    let stderr: String
    var timedOut = false
}

/// Reads one pipe to its end on a background queue, so the child never blocks on a full pipe.
private final class PipeDrain {
    private var data = Data()
    private let done = DispatchGroup()

    init(_ handle: FileHandle) {
        done.enter()
        DispatchQueue.global(qos: .utility).async {
            self.data = handle.readDataToEndOfFile()
            self.done.leave()
        }
    }

    func wait() -> Data {
        done.wait()
        return data
    }
}

/// Runs a program and waits for it.
///
/// Both pipes are drained while the child runs: reading them only after exit can deadlock
/// once a child writes more than a pipe buffer. The child is stopped after `timeout`.
@discardableResult
func runCommand(_ path: String, _ args: [String], timeout: TimeInterval = 60) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err

    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }

    do {
        try process.run()
    } catch {
        return CommandResult(code: 127, stdout: "", stderr: error.localizedDescription)
    }

    let stdoutDrain = PipeDrain(out.fileHandleForReading)
    let stderrDrain = PipeDrain(err.fileHandleForReading)

    var timedOut = false
    if exited.wait(timeout: .now() + timeout) == .timedOut {
        timedOut = true
        process.terminate()
        if exited.wait(timeout: .now() + 2) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            exited.wait()
        }
    }

    let stdout = String(decoding: stdoutDrain.wait(), as: UTF8.self)
    var stderr = String(decoding: stderrDrain.wait(), as: UTF8.self)
    if timedOut {
        stderr = "超过 \(Int(timeout)) 秒未结束，已终止。\(stderr)"
    }
    return CommandResult(code: process.terminationStatus, stdout: stdout, stderr: stderr, timedOut: timedOut)
}

func cleanMessage(_ primary: String, fallback: String) -> String {
    let message = primary.trimmingCharacters(in: .whitespacesAndNewlines)
    if !message.isEmpty { return message }
    return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
}

func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func appleScriptLiteral(_ value: String) -> String {
    "\"" + value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        + "\""
}

/// Local time with offset, e.g. 2026-11-24T02:00:03+01:00, for log lines.
func logTimestamp(_ date: Date = Date()) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = .current
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}
