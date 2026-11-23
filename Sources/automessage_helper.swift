import Foundation

@main
struct AutoMessageHelper {
    static func main() {
        let result = AutoMessageRunner().runOnce()
        // One line per run: when, the outcome, and the details, e.g.
        // 2026-11-24T02:00:03+01:00 [sent] 已发送到 Codex 并回车提交
        let line = "\(logTimestamp()) [\(result.status.rawValue)] \(result.message)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
        exit(result.ok ? 0 : 1)
    }
}
