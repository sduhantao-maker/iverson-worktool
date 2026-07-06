import Foundation

@main
struct AutoMessageMessageComposerTests {
    static func main() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoMessageMessageComposerTests", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let firstFileURL = tempDirectory.appendingPathComponent("first.txt")
        let secondFileURL = tempDirectory.appendingPathComponent("second.txt")
        try "Line 1\nLine 2".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "Line 3\nLine 4".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let target = AutoMessageTarget(
            enabled: true,
            appName: "Codex",
            processName: "Codex",
            message: "Prompt",
            filePaths: [firstFileURL.path, secondFileURL.path],
            launchWaitSeconds: 0
        )

        let composedMessage = try AutoMessageMessageComposer.composedMessage(for: target)
        let expectedMessage = "Prompt\n\nLine 1\nLine 2\n\nLine 3\nLine 4"

        guard composedMessage == expectedMessage else {
            fputs("Expected composed message to include text and file contents.\n", stderr)
            fputs("Expected: \(expectedMessage)\n", stderr)
            fputs("Actual: \(composedMessage)\n", stderr)
            exit(1)
        }
    }
}
