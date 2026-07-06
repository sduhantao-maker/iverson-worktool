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
        let expectedMessage = "Prompt\n\n文件：first.txt\nLine 1\nLine 2\n\n文件：second.txt\nLine 3\nLine 4"

        guard composedMessage == expectedMessage else {
            fputs("Expected composed message to include text and file contents.\n", stderr)
            fputs("Expected: \(expectedMessage)\n", stderr)
            fputs("Actual: \(composedMessage)\n", stderr)
            exit(1)
        }

        let docxURL = try makeDocx(in: tempDirectory)
        let docxTarget = AutoMessageTarget(
            enabled: true,
            appName: "Codex",
            processName: "Codex",
            message: "",
            filePaths: [docxURL.path],
            launchWaitSeconds: 0
        )
        let docxMessage = try AutoMessageMessageComposer.composedMessage(for: docxTarget)
        guard docxMessage.contains("Docx Line 1") else {
            fputs("Expected docx text extraction to include Docx Line 1.\n", stderr)
            fputs("Actual: \(docxMessage)\n", stderr)
            exit(1)
        }

        let xlsxURL = try makeXlsx(in: tempDirectory)
        let xlsxTarget = AutoMessageTarget(
            enabled: true,
            appName: "Codex",
            processName: "Codex",
            message: "",
            filePaths: [xlsxURL.path],
            launchWaitSeconds: 0
        )
        let xlsxMessage = try AutoMessageMessageComposer.composedMessage(for: xlsxTarget)
        guard xlsxMessage.contains("Alpha\tBeta") && xlsxMessage.contains("42") else {
            fputs("Expected xlsx text extraction to include Alpha, Beta, and 42.\n", stderr)
            fputs("Actual: \(xlsxMessage)\n", stderr)
            exit(1)
        }
    }

    private static func makeDocx(in tempDirectory: URL) throws -> URL {
        let packageURL = tempDirectory.appendingPathComponent("docx-package", isDirectory: true)
        let wordURL = packageURL.appendingPathComponent("word", isDirectory: true)
        try FileManager.default.createDirectory(at: wordURL, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Docx Line 1</w:t></w:r></w:p>
            <w:p><w:r><w:t>Docx Line 2</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """.write(to: wordURL.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        let docxURL = tempDirectory.appendingPathComponent("sample.docx")
        try zipDirectory(packageURL, outputURL: docxURL)
        return docxURL
    }

    private static func makeXlsx(in tempDirectory: URL) throws -> URL {
        let packageURL = tempDirectory.appendingPathComponent("xlsx-package", isDirectory: true)
        let xlURL = packageURL.appendingPathComponent("xl", isDirectory: true)
        let worksheetsURL = xlURL.appendingPathComponent("worksheets", isDirectory: true)
        try FileManager.default.createDirectory(at: worksheetsURL, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <si><t>Alpha</t></si>
          <si><t>Beta</t></si>
        </sst>
        """.write(to: xlURL.appendingPathComponent("sharedStrings.xml"), atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
            <row r="2"><c r="A2"><v>42</v></c></row>
          </sheetData>
        </worksheet>
        """.write(to: worksheetsURL.appendingPathComponent("sheet1.xml"), atomically: true, encoding: .utf8)

        let xlsxURL = tempDirectory.appendingPathComponent("sample.xlsx")
        try zipDirectory(packageURL, outputURL: xlsxURL)
        return xlsxURL
    }

    private static func zipDirectory(_ directoryURL: URL, outputURL: URL) throws {
        try? FileManager.default.removeItem(at: outputURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", outputURL.path, "."]
        process.currentDirectoryURL = directoryURL
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "AutoMessageTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "zip failed"]
            )
        }
    }
}
