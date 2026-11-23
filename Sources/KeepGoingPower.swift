import Foundation
import IOKit.ps

enum PowerMode: String {
    case keepAwake = "enabled"
    case normal = "normal"
}

enum HelperInstallState: Equatable {
    /// `sudo -n keepgoing-helper status` fails: the helper or its sudoers rule is missing.
    case missing
    /// The installed helper differs from the one in this app, e.g. it predates snapshot/restore.
    case outdated
    case current
}

struct PowerStatus: Equatable {
    var mode: PowerMode
    var helper: HelperInstallState
}

/// When KeepGoing should switch itself off.
struct KeepGoingAutoOffSettings: Codable, Equatable {
    var deadlineEnabled = true
    var deadlineHour = 8
    var deadlineMinute = 0
    var batteryFloorEnabled = true
    var batteryFloorPercent = 20
}

/// The rules the guard checks, fixed when KeepGoing is switched on.
struct KeepGoingGuardState: Codable, Equatable {
    var deadline: Date?
    var batteryFloorPercent: Int?
    var armedAt: Date
}

struct BatteryReading: Equatable {
    var percent: Int
    var onBattery: Bool

    /// The internal battery, or nil on a Mac without one.
    static func current() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            let state = description[kIOPSPowerSourceStateKey] as? String
            return BatteryReading(
                percent: Int((Double(current) / Double(maximum) * 100).rounded()),
                onBattery: state == kIOPSBatteryPowerValue
            )
        }
        return nil
    }
}

/// Everything the KeepGoing page does to the system. The page talks only to this, so it
/// can be rendered and tested with a fake.
protocol PowerControlling: AnyObject {
    func readStatus() -> PowerStatus
    func setMode(_ mode: PowerMode) -> CommandResult
    func installHelper() -> CommandResult
    /// Starts the auto-off guard. Returns an error message, or nil.
    func armAutoOff(_ settings: KeepGoingAutoOffSettings) -> String?
    func disarmAutoOff()
    func autoOffState() -> KeepGoingGuardState?
}

/// Files under ~/Library/Application Support/KeepGoing.
final class KeepGoingStore {
    let directory: URL

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("KeepGoing", isDirectory: true)) {
        self.directory = directory
    }

    var autoOffURL: URL { directory.appendingPathComponent("keepgoing.json") }
    var guardStateURL: URL { directory.appendingPathComponent("keepgoing-guard.json") }
    var logsURL: URL { directory.appendingPathComponent("Logs", isDirectory: true) }

    func loadAutoOff() -> KeepGoingAutoOffSettings {
        (try? decode(KeepGoingAutoOffSettings.self, from: autoOffURL)) ?? KeepGoingAutoOffSettings()
    }

    func saveAutoOff(_ settings: KeepGoingAutoOffSettings) throws {
        try encode(settings, to: autoOffURL)
    }

    func loadGuardState() -> KeepGoingGuardState? {
        try? decode(KeepGoingGuardState.self, from: guardStateURL)
    }

    func saveGuardState(_ state: KeepGoingGuardState) throws {
        try encode(state, to: guardStateURL)
    }

    func clearGuardState() {
        try? FileManager.default.removeItem(at: guardStateURL)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

enum GuardDecision: Equatable {
    case idle
    case disable(reason: String)
    case retire(reason: String)
}

/// Switches KeepGoing off at a set time or on low battery.
///
/// A user LaunchAgent runs the app's own executable with `--keepgoing-guard` every two
/// minutes while KeepGoing is on. It needs no new privileges: it calls the same
/// `sudo -n keepgoing-helper disable` that the sudoers rule already allows.
enum KeepGoingGuard {
    static let label = "com.iverson.keepgoing.guard"
    static let launchArgument = "--keepgoing-guard"
    static let checkInterval = 120

    static func nextDeadline(hour: Int, minute: Int, after date: Date, calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime, direction: .forward)
    }

    static func makeState(from settings: KeepGoingAutoOffSettings, now: Date, calendar: Calendar = .current) -> KeepGoingGuardState? {
        let deadline = settings.deadlineEnabled
            ? nextDeadline(hour: settings.deadlineHour, minute: settings.deadlineMinute, after: now, calendar: calendar)
            : nil
        let floor = settings.batteryFloorEnabled ? settings.batteryFloorPercent : nil
        guard deadline != nil || floor != nil else { return nil }
        return KeepGoingGuardState(deadline: deadline, batteryFloorPercent: floor, armedAt: now)
    }

    static func evaluate(state: KeepGoingGuardState?, sleepDisabled: Bool, battery: BatteryReading?, now: Date) -> GuardDecision {
        guard sleepDisabled else { return .retire(reason: "KeepGoing 已经关闭") }
        guard let state else { return .retire(reason: "没有自动关闭设置") }
        if let deadline = state.deadline, now >= deadline {
            return .disable(reason: "到了设定的关闭时间 \(timeText(deadline))")
        }
        if let floor = state.batteryFloorPercent, let battery, battery.onBattery, battery.percent <= floor {
            return .disable(reason: "正在用电池，电量 \(battery.percent)%，不高于设定的 \(floor)%")
        }
        return .idle
    }

    static func agentURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist", isDirectory: false)
    }

    /// Writes and loads the guard agent. Returns an error message, or nil on success.
    static func arm(settings: KeepGoingAutoOffSettings, executablePath: String, store: KeepGoingStore, now: Date = Date()) -> String? {
        guard let state = makeState(from: settings, now: now) else {
            disarm(store: store)
            return nil
        }
        do {
            try store.saveGuardState(state)
            try FileManager.default.createDirectory(at: store.logsURL, withIntermediateDirectories: true)
            let logPath = store.logsURL.appendingPathComponent("keepgoing-guard.log").path
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executablePath, launchArgument],
                "StartInterval": checkInterval,
                "RunAtLoad": true,
                "ProcessType": "Background",
                "StandardOutPath": logPath,
                "StandardErrorPath": logPath,
            ]
            let url = agentURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url, options: .atomic)
            let domain = "gui/\(getuid())"
            runCommand("/bin/launchctl", ["bootout", "\(domain)/\(label)"], timeout: 10)
            let result = runCommand("/bin/launchctl", ["bootstrap", domain, url.path], timeout: 10)
            if result.code != 0 {
                return "自动关闭守护没有启动：\(cleanMessage(result.stderr, fallback: result.stdout))"
            }
            return nil
        } catch {
            return "自动关闭守护写入失败：\(error.localizedDescription)"
        }
    }

    /// Removes the guard. Called from the guard itself, this ends its own process last.
    static func disarm(store: KeepGoingStore) {
        store.clearGuardState()
        try? FileManager.default.removeItem(at: agentURL())
        runCommand("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"], timeout: 10)
    }

    /// Entry point when launchd starts the main executable with `--keepgoing-guard`.
    static func runFromLaunchd() -> Int32 {
        let store = KeepGoingStore()
        let decision = evaluate(
            state: store.loadGuardState(),
            sleepDisabled: HelperPowerControl.readModeWithoutHelper() == .keepAwake,
            battery: BatteryReading.current(),
            now: Date()
        )
        switch decision {
        case .idle:
            return 0
        case .retire(let reason):
            log("守护退出：\(reason)")
            disarm(store: store)
            return 0
        case .disable(let reason):
            let result = runCommand("/usr/bin/sudo", ["-n", HelperPowerControl.helperPath, "disable"], timeout: 30)
            guard result.code == 0 else {
                log("自动关闭 KeepGoing 失败（\(reason)）：\(cleanMessage(result.stderr, fallback: result.stdout))")
                return 1
            }
            log("已自动关闭 KeepGoing：\(reason)")
            disarm(store: store)
            return 0
        }
    }

    static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data("\(logTimestamp()) \(message)\n".utf8))
    }
}

/// The real system: the sudo helper for pmset, osascript for the one-time install, and
/// a LaunchAgent for the auto-off guard.
final class HelperPowerControl: PowerControlling {
    static let helperPath = "/usr/local/bin/keepgoing-helper"

    private let store: KeepGoingStore
    private let bundledHelperURL: URL?
    private let installerURL: URL?

    init(store: KeepGoingStore = KeepGoingStore(), bundle: Bundle = .main) {
        self.store = store
        bundledHelperURL = bundle.url(forResource: "keepgoing-helper", withExtension: nil)
        installerURL = bundle.url(forResource: "install-helper", withExtension: "sh")
    }

    func readStatus() -> PowerStatus {
        let result = runCommand("/usr/bin/sudo", ["-n", Self.helperPath, "status"], timeout: 15)
        guard result.code == 0 else {
            return PowerStatus(mode: Self.readModeWithoutHelper(), helper: .missing)
        }
        let enabled = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "enabled"
        return PowerStatus(mode: enabled ? .keepAwake : .normal, helper: installedHelperIsCurrent() ? .current : .outdated)
    }

    func setMode(_ mode: PowerMode) -> CommandResult {
        runCommand("/usr/bin/sudo", ["-n", Self.helperPath, mode == .keepAwake ? "enable" : "disable"], timeout: 30)
    }

    func installHelper() -> CommandResult {
        guard let installer = installerURL?.path else {
            return CommandResult(code: 66, stdout: "", stderr: "安装脚本缺失")
        }
        let command = "\(shellQuote(installer)) \(shellQuote(NSUserName()))"
        let script = "do shell script \(appleScriptLiteral(command)) with administrator privileges"
        return runCommand("/usr/bin/osascript", ["-e", script], timeout: 600)
    }

    func armAutoOff(_ settings: KeepGoingAutoOffSettings) -> String? {
        guard let executable = Bundle.main.executablePath else { return "找不到 App 的可执行文件" }
        return KeepGoingGuard.arm(settings: settings, executablePath: executable, store: store)
    }

    func disarmAutoOff() {
        KeepGoingGuard.disarm(store: store)
    }

    func autoOffState() -> KeepGoingGuardState? {
        store.loadGuardState()
    }

    /// Compares the installed helper with the copy in this app. If either file cannot be
    /// read, it reports current rather than nag.
    func installedHelperIsCurrent() -> Bool {
        guard let bundledHelperURL,
              let expected = try? Data(contentsOf: bundledHelperURL),
              let installed = FileManager.default.contents(atPath: Self.helperPath)
        else { return true }
        return expected == installed
    }

    /// Reads SleepDisabled from `pmset -g`, which needs no privileges.
    static func readModeWithoutHelper() -> PowerMode {
        let result = runCommand("/usr/bin/pmset", ["-g"], timeout: 10)
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[0] == "SleepDisabled" {
                return parts[1] == "1" ? .keepAwake : .normal
            }
        }
        return .normal
    }
}
