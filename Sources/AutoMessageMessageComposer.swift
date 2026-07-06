import Foundation
import PDFKit

enum AutoMessageMessageComposer {
    static func composedMessage(for target: AutoMessageTarget) throws -> String {
        let message = target.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let filePaths = (target.filePaths ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !filePaths.isEmpty else {
            return message
        }

        var parts: [String] = []
        if !message.isEmpty {
            parts.append(message)
        }

        for filePath in filePaths {
            let fileContent = try readFileContent(at: filePath)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !fileContent.isEmpty {
                let fileName = URL(fileURLWithPath: filePath).lastPathComponent
                parts.append("文件：\(fileName)\n\(fileContent)")
            }
        }

        return parts.joined(separator: "\n\n")
    }

    private static func readFileContent(at filePath: String) throws -> String {
        let fileExtension = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        switch fileExtension {
        case "docx":
            if let text = try? readDocumentWithTextutil(at: filePath) {
                return text
            }
            return try readDocxContent(at: filePath)
        case "doc":
            return try readDocumentWithTextutil(at: filePath)
        case "pdf":
            return try readPDFContent(at: filePath)
        case "xlsx":
            return try readXlsxContent(at: filePath)
        default:
            return try readPlainTextContent(at: filePath)
        }
    }

    private static func readPlainTextContent(at filePath: String) throws -> String {
        do {
            var encoding = String.Encoding.utf8
            return try String(contentsOfFile: filePath, usedEncoding: &encoding)
        } catch {
            throw NSError(
                domain: "AutoMessage",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "读取文件内容失败：\(filePath)。支持 doc、docx、xlsx、csv、pdf、markdown、md、py 和常见文本文件。原始错误：\(error.localizedDescription)"
                ]
            )
        }
    }

    private static func readDocumentWithTextutil(at filePath: String) throws -> String {
        let data = try commandOutput(
            executable: "/usr/bin/textutil",
            arguments: ["-convert", "txt", "-stdout", filePath],
            errorMessage: "读取 doc/docx 失败：\(filePath)"
        )
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func readPDFContent(at filePath: String) throws -> String {
        guard let document = PDFDocument(url: URL(fileURLWithPath: filePath)) else {
            throw NSError(
                domain: "AutoMessage",
                code: 7,
                userInfo: [
                    NSLocalizedDescriptionKey: "读取 pdf 失败：\(filePath)"
                ]
            )
        }

        var pages: [String] = []
        for pageIndex in 0..<document.pageCount {
            if let pageText = document.page(at: pageIndex)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pageText.isEmpty {
                pages.append(pageText)
            }
        }

        return pages.joined(separator: "\n\n")
    }

    private static func readDocxContent(at filePath: String) throws -> String {
        let data = try commandOutput(
            executable: "/usr/bin/unzip",
            arguments: ["-p", filePath, "word/document.xml"],
            errorMessage: "读取 docx 失败：\(filePath)"
        )
        return try DocxDocumentTextParser.parse(data)
    }

    private static func readXlsxContent(at filePath: String) throws -> String {
        let listData = try commandOutput(
            executable: "/usr/bin/unzip",
            arguments: ["-Z", "-1", filePath],
            errorMessage: "读取 xlsx 失败：\(filePath)"
        )
        let entries = (String(data: listData, encoding: .utf8) ?? "")
            .components(separatedBy: .newlines)
        let sheetEntries = entries
            .filter { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }
            .sorted()

        let sharedStringsData = try? commandOutput(
            executable: "/usr/bin/unzip",
            arguments: ["-p", filePath, "xl/sharedStrings.xml"],
            errorMessage: "读取 xlsx 共享字符串失败：\(filePath)"
        )
        let sharedStrings = (try? sharedStringsData.map { try XlsxSharedStringsParser.parse($0) }) ?? []

        var sheets: [String] = []
        for sheetEntry in sheetEntries {
            let sheetData = try commandOutput(
                executable: "/usr/bin/unzip",
                arguments: ["-p", filePath, sheetEntry],
                errorMessage: "读取 xlsx 工作表失败：\(filePath)"
            )
            let rows = try XlsxWorksheetParser.parse(sheetData, sharedStrings: sharedStrings)
            if !rows.isEmpty {
                sheets.append("\(URL(fileURLWithPath: sheetEntry).lastPathComponent)\n\(rows.joined(separator: "\n"))")
            }
        }

        return sheets.joined(separator: "\n\n")
    }

    private static func commandOutput(
        executable: String,
        arguments: [String],
        errorMessage: String
    ) throws -> Data {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let rawError = String(data: errorData, encoding: .utf8) ?? ""
                throw NSError(
                    domain: "AutoMessage",
                    code: 4,
                    userInfo: [
                        NSLocalizedDescriptionKey: "\(errorMessage)。\(rawError.trimmingCharacters(in: .whitespacesAndNewlines))"
                    ]
                )
            }

            return outputData
        } catch {
            throw NSError(
                domain: "AutoMessage",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey: "\(errorMessage)。原始错误：\(error.localizedDescription)"
                ]
            )
        }
    }
}

private final class DocxDocumentTextParser: NSObject, XMLParserDelegate {
    private var text = ""

    static func parse(_ data: Data) throws -> String {
        let parserDelegate = DocxDocumentTextParser()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        guard parser.parse() else {
            throw NSError(
                domain: "AutoMessage",
                code: 6,
                userInfo: [
                    NSLocalizedDescriptionKey: "读取 docx 失败：无法解析 document.xml"
                ]
            )
        }

        return parserDelegate.text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "w:p" {
            text += "\n"
        }
    }
}

private final class XlsxSharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var currentString = ""
    private var isInsideStringItem = false
    private var isCollectingText = false

    static func parse(_ data: Data) throws -> [String] {
        let parserDelegate = XlsxSharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        guard parser.parse() else {
            throw NSError(
                domain: "AutoMessage",
                code: 8,
                userInfo: [
                    NSLocalizedDescriptionKey: "读取 xlsx 失败：无法解析 sharedStrings.xml"
                ]
            )
        }

        return parserDelegate.strings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "si" {
            isInsideStringItem = true
            currentString = ""
        } else if isInsideStringItem && elementName == "t" {
            isCollectingText = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCollectingText {
            currentString += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "t" {
            isCollectingText = false
        } else if elementName == "si" {
            strings.append(currentString)
            currentString = ""
            isInsideStringItem = false
        }
    }
}

private final class XlsxWorksheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rows: [String] = []
    private var currentRow: [String] = []
    private var currentCellType = ""
    private var currentCellValue = ""
    private var isInsideCell = false
    private var isCollectingValue = false
    private var collectedValue = ""

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    static func parse(_ data: Data, sharedStrings: [String]) throws -> [String] {
        let parserDelegate = XlsxWorksheetParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        guard parser.parse() else {
            throw NSError(
                domain: "AutoMessage",
                code: 9,
                userInfo: [
                    NSLocalizedDescriptionKey: "读取 xlsx 失败：无法解析 worksheet xml"
                ]
            )
        }

        return parserDelegate.rows
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "row" {
            currentRow = []
        } else if elementName == "c" {
            isInsideCell = true
            currentCellType = attributeDict["t"] ?? ""
            currentCellValue = ""
        } else if isInsideCell && (elementName == "v" || elementName == "t") {
            isCollectingValue = true
            collectedValue = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCollectingValue {
            collectedValue += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if isInsideCell && (elementName == "v" || elementName == "t") {
            currentCellValue += collectedValue
            collectedValue = ""
            isCollectingValue = false
        } else if elementName == "c" {
            let resolvedValue = resolvedCellValue()
            if !resolvedValue.isEmpty {
                currentRow.append(resolvedValue)
            }
            isInsideCell = false
            currentCellType = ""
            currentCellValue = ""
        } else if elementName == "row" {
            if !currentRow.isEmpty {
                rows.append(currentRow.joined(separator: "\t"))
            }
            currentRow = []
        }
    }

    private func resolvedCellValue() -> String {
        let cleanedValue = currentCellValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentCellType == "s",
           let sharedStringIndex = Int(cleanedValue),
           sharedStrings.indices.contains(sharedStringIndex) {
            return sharedStrings[sharedStringIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleanedValue
    }
}
