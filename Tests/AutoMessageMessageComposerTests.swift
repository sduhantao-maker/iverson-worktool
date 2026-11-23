import Foundation

func composerTests() throws {
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

    check(
        AutoMessageMessageComposer.messageText(for: target) == "请阅读附件并总结。",
        "message text stays separate from files"
    )
    let fileURLs = try AutoMessageMessageComposer.fileURLs(for: target)
    check(fileURLs == [firstFileURL, secondFileURL], "original file URLs are kept for the attachment paste")

    check(
        AutoMessageDestination.resolve(target) == AutoMessageDestination(
            displayName: "Codex",
            applicationName: "ChatGPT",
            processName: "ChatGPT",
            bundleIdentifier: "com.openai.codex"
        ),
        "a legacy Codex configuration targets ChatGPT in Codex mode"
    )

    let claude = AutoMessageTarget(
        enabled: true,
        appName: "Claude",
        processName: "Claude",
        message: "",
        filePaths: nil,
        launchWaitSeconds: 0
    )
    check(
        AutoMessageDestination.resolve(claude) == AutoMessageDestination(
            displayName: "Claude",
            applicationName: "Claude",
            processName: "Claude",
            bundleIdentifier: nil
        ),
        "the Claude destination is unchanged"
    )
}
