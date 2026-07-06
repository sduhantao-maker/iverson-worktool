import Foundation

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
            let fileContent: String
            do {
                fileContent = try String(contentsOfFile: filePath, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                throw NSError(
                    domain: "AutoMessage",
                    code: 3,
                    userInfo: [
                        NSLocalizedDescriptionKey: "读取文件内容失败：\(filePath)"
                    ]
                )
            }

            if !fileContent.isEmpty {
                parts.append(fileContent)
            }
        }

        return parts.joined(separator: "\n\n")
    }
}
