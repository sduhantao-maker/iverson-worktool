import Foundation

enum AutoMessageMessageComposer {
    static func messageText(for target: AutoMessageTarget) -> String {
        target.message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fileURLs(for target: AutoMessageTarget) throws -> [URL] {
        try (target.filePaths ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { filePath in
                let fileURL = URL(fileURLWithPath: filePath)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    throw NSError(
                        domain: "AutoMessage",
                        code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey: "附件文件不存在：\(filePath)"
                        ]
                    )
                }

                return fileURL
            }
    }
}
