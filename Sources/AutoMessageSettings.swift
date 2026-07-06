import Foundation

struct AutoMessageTarget: Codable, Equatable {
    var enabled: Bool
    var appName: String
    var processName: String
    var message: String
    var launchWaitSeconds: Double
}

struct AutoMessageSettings: Codable, Equatable {
    var startDate: Date?
    var hour: Int
    var minute: Int
    var dryRun: Bool
    var submitAfterPaste: Bool
    var targets: [AutoMessageTarget]
    var updatedAt: Date

    static var defaults: AutoMessageSettings {
        AutoMessageSettings(
            startDate: Calendar.current.startOfDay(for: Date()),
            hour: 9,
            minute: 30,
            dryRun: true,
            submitAfterPaste: false,
            targets: [
                AutoMessageTarget(
                    enabled: true,
                    appName: "Codex",
                    processName: "Codex",
                    message: "早上好，请继续昨天的任务。",
                    launchWaitSeconds: 8
                ),
                AutoMessageTarget(
                    enabled: true,
                    appName: "Claude",
                    processName: "Claude",
                    message: "早上好，请总结今天要做的三件事。",
                    launchWaitSeconds: 8
                ),
            ],
            updatedAt: Date()
        )
    }
}

final class AutoMessageSettingsStore {
    let fileURL: URL

    init() {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        fileURL = applicationSupportURL
            .appendingPathComponent("KeepGoing", isDirectory: true)
            .appendingPathComponent("auto-message.json", isDirectory: false)
    }

    func load() throws -> AutoMessageSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let defaults = AutoMessageSettings.defaults
            try save(defaults)
            return defaults
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AutoMessageSettings.self, from: data)
    }

    func save(_ settings: AutoMessageSettings) throws {
        var settingsToSave = settings
        settingsToSave.updatedAt = Date()

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settingsToSave)
        try data.write(to: fileURL, options: .atomic)
    }
}
