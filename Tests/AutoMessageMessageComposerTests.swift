import Foundation

@main
struct AutoMessageMessageComposerTests {
    static func main() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoMessageMessageComposerTests", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let firstFileURL = tempDirectory.appendingPathComponent("first.docx")
        let secondFileURL = tempDirectory.appendingPathComponent("second.pdf")
        try "docx bytes stay attached".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "pdf bytes stay attached".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let target = AutoMessageTarget(
            enabled: true,
            appName: "Codex",
            processName: "Codex",
            message: "请阅读附件并总结。",
            filePaths: [firstFileURL.path, secondFileURL.path],
            launchWaitSeconds: 0
        )

        let message = AutoMessageMessageComposer.messageText(for: target)
        guard message == "请阅读附件并总结。" else {
            fputs("Expected message text to stay separate from files.\n", stderr)
            fputs("Actual: \(message)\n", stderr)
            exit(1)
        }

        let fileURLs = try AutoMessageMessageComposer.fileURLs(for: target)
        guard fileURLs == [firstFileURL, secondFileURL] else {
            fputs("Expected original file URLs to be preserved for attachment paste.\n", stderr)
            fputs("Actual: \(fileURLs)\n", stderr)
            exit(1)
        }
    }
}
