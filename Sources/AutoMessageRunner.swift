import Cocoa
import Foundation
import ApplicationServices

struct AutoMessageRunResult: Equatable {
    enum Status: String {
        case sent
        case skipped
        case failed
    }

    let status: Status
    let message: String

    var ok: Bool { status != .failed }

    static func sent(_ message: String) -> AutoMessageRunResult {
        AutoMessageRunResult(status: .sent, message: message)
    }

    static func skipped(_ message: String) -> AutoMessageRunResult {
        AutoMessageRunResult(status: .skipped, message: message)
    }

    static func failed(_ message: String) -> AutoMessageRunResult {
        AutoMessageRunResult(status: .failed, message: message)
    }
}

enum AutoMessageTrigger {
    /// The "测试发送" button.
    case manual
    /// The LaunchAgent.
    case scheduled
}

/// What the login session looks like, from `CGSessionCopyCurrentDictionary`.
struct ScreenSessionState: Equatable {
    var hasGUISession: Bool
    var isLocked: Bool
    var isOnConsole: Bool

    static func current() -> ScreenSessionState {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return ScreenSessionState(hasGUISession: false, isLocked: false, isOnConsole: false)
        }
        return ScreenSessionState(
            hasGUISession: true,
            isLocked: session["CGSSessionScreenIsLocked"] as? Bool ?? false,
            isOnConsole: session["kCGSSessionOnConsoleKey"] as? Bool ?? true
        )
    }
}

/// The parts of the outside world the runner checks. Tests replace them.
struct AutoMessageEnvironment {
    var now: () -> Date = { Date() }
    var calendar: Calendar = .current
    var screenSession: () -> ScreenSessionState = { ScreenSessionState.current() }
    var accessibilityTrusted: (_ prompt: Bool) -> Bool = { AutoMessageRunner.isAccessibilityTrusted(prompt: $0) }
}

/// The general pasteboard's items, so a send can put back what you had copied.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(_ pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item -> [NSPasteboard.PasteboardType: Data] in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type] = data }
            }
            return entry
        }
        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}

final class AutoMessageRunner {
    static let agentLabel = "com.iverson.keepgoing.automessage"

    /// A scheduled run that starts more than this after its planned time is skipped.
    /// launchd runs a missed calendar job when the Mac wakes, so without this a 02:00 send
    /// would fire when you open the lid in the morning.
    static let scheduledGraceInterval: TimeInterval = 30 * 60

    let store: AutoMessageSettingsStore
    var environment: AutoMessageEnvironment
    /// Replaces the GUI delivery in tests.
    var deliverOverride: ((AutoMessageTarget, _ submit: Bool) -> AutoMessageRunResult)?
    private var lastOwnPasteboardChange: Int?

    init(store: AutoMessageSettingsStore = AutoMessageSettingsStore(), environment: AutoMessageEnvironment = AutoMessageEnvironment()) {
        self.store = store
        self.environment = environment
    }

    func runOnce() -> AutoMessageRunResult {
        do {
            return run(settings: try store.load(), trigger: .scheduled)
        } catch {
            return .failed("读取自动消息配置失败：\(error.localizedDescription)")
        }
    }

    func run(settings: AutoMessageSettings, trigger: AutoMessageTrigger) -> AutoMessageRunResult {
        let enabledTargets = settings.targets.filter(\.enabled)
        guard !enabledTargets.isEmpty else {
            return .skipped("没有启用的目标，未发送")
        }

        if settings.dryRun {
            let appNames = enabledTargets
                .map { AutoMessageDestination.resolve($0).displayName }
                .filter { !$0.isEmpty }
                .joined(separator: "、")
            return .skipped("Dry run 已开启：不会粘贴或发送；目标是 \(appNames)")
        }

        let now = environment.now()
        if let skip = Self.skipResultBeforeStartDate(settings, now: now, calendar: environment.calendar) {
            return skip
        }
        if trigger == .scheduled, let skip = Self.staleRunResult(settings, now: now, calendar: environment.calendar) {
            return skip
        }

        let session = environment.screenSession()
        guard session.hasGUISession, session.isOnConsole else {
            return .failed("没有可用的图形会话（没有登录，或切换到了别的用户），未发送")
        }
        guard !session.isLocked else {
            return .failed("屏幕已锁定，未发送：锁屏时模拟的按键会落到锁屏界面，不会到达目标 App")
        }
        // A permission prompt at 3 AM helps nobody, so only manual sends may ask.
        guard environment.accessibilityTrusted(trigger == .manual) else {
            return .failed("需要辅助功能权限：请在 系统设置 → 隐私与安全性 → 辅助功能 中允许当前程序。测试发送允许 Iverson’s WorkTool；定时发送允许 keepgoing-automessage。")
        }

        // Every target is tried, even when an earlier one fails.
        let snapshot = deliverOverride == nil ? PasteboardSnapshot.capture() : nil
        lastOwnPasteboardChange = nil
        var outcomes: [AutoMessageRunResult] = []
        for target in enabledTargets {
            if let problem = validate(target) {
                outcomes.append(problem)
                continue
            }
            let outcome = deliverOverride?(target, settings.submitAfterPaste)
                ?? send(target: target, submit: settings.submitAfterPaste)
            outcomes.append(outcome)
        }

        // Put your clipboard back, unless something else has written to it since our paste.
        if let snapshot, let ownChange = lastOwnPasteboardChange {
            if !settings.submitAfterPaste { Thread.sleep(forTimeInterval: 1.0) }
            if NSPasteboard.general.changeCount == ownChange { snapshot.restore() }
        }

        return Self.summarize(outcomes)
    }

    static func summarize(_ outcomes: [AutoMessageRunResult]) -> AutoMessageRunResult {
        let text = outcomes.map(\.message).joined(separator: "；")
        let failures = outcomes.filter { $0.status == .failed }.count
        if failures == 0 {
            return outcomes.allSatisfy { $0.status == .skipped } ? .skipped(text) : .sent(text)
        }
        return .failed(failures == outcomes.count ? text : "部分失败：\(text)")
    }

    static func skipResultBeforeStartDate(_ settings: AutoMessageSettings, now: Date, calendar: Calendar = .current) -> AutoMessageRunResult? {
        guard let startDate = settings.startDate else { return nil }

        let today = calendar.startOfDay(for: now)
        let startDay = calendar.startOfDay(for: startDate)
        guard today < startDay else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return .skipped("未到开始日期：\(formatter.string(from: startDay)) 后开始发送")
    }

    /// How long after its most recent planned time this run started.
    static func lateness(of settings: AutoMessageSettings, now: Date, calendar: Calendar = .current) -> TimeInterval? {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = settings.hour
        components.minute = settings.minute
        components.second = 0
        guard var slot = calendar.date(from: components) else { return nil }
        if slot > now {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: slot) else { return nil }
            slot = previous
        }
        return now.timeIntervalSince(slot)
    }

    static func staleRunResult(_ settings: AutoMessageSettings, now: Date, calendar: Calendar = .current) -> AutoMessageRunResult? {
        guard let late = lateness(of: settings, now: now, calendar: calendar), late > scheduledGraceInterval else {
            return nil
        }
        let planned = String(format: "%02d:%02d", settings.hour, settings.minute)
        return .skipped("错过了计划时间 \(planned)，晚了 \(Int(late / 60)) 分钟（电脑当时在睡眠，launchd 唤醒后补发），本次跳过")
    }

    func installLaunchAgent(helperPath: String, settings: AutoMessageSettings) -> AutoMessageRunResult {
        do {
            try store.save(settings)

            let plistURL = launchAgentURL()
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let plist: [String: Any] = [
                "Label": Self.agentLabel,
                "ProgramArguments": [helperPath],
                "StartCalendarInterval": [
                    "Hour": settings.hour,
                    "Minute": settings.minute,
                ],
                "RunAtLoad": false,
                "StandardOutPath": try logURL("auto-message.out.log").path,
                "StandardErrorPath": try logURL("auto-message.err.log").path,
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: plistURL, options: .atomic)

            let domain = "gui/\(getuid())"
            runCommand("/bin/launchctl", ["bootout", "\(domain)/\(Self.agentLabel)"], timeout: 10)
            let bootstrap = runCommand("/bin/launchctl", ["bootstrap", domain, plistURL.path], timeout: 10)
            if bootstrap.code != 0 {
                return .failed("安装自动消息定时任务失败：\(cleanMessage(bootstrap.stderr, fallback: bootstrap.stdout))")
            }

            return .sent(String(format: "定时任务已安装：每天 %02d:%02d", settings.hour, settings.minute))
        } catch {
            return .failed("安装自动消息定时任务失败：\(error.localizedDescription)")
        }
    }

    func uninstallLaunchAgent() -> AutoMessageRunResult {
        let domain = "gui/\(getuid())"
        runCommand("/bin/launchctl", ["bootout", "\(domain)/\(Self.agentLabel)"], timeout: 10)

        do {
            let plistURL = launchAgentURL()
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
            return .sent("自动消息定时任务已卸载")
        } catch {
            return .failed("卸载自动消息定时任务失败：\(error.localizedDescription)")
        }
    }

    /// The time in the installed LaunchAgent, or nil when none is installed.
    func installedSchedule() -> (hour: Int, minute: Int)? {
        guard let data = try? Data(contentsOf: launchAgentURL()),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let interval = plist["StartCalendarInterval"] as? [String: Any],
              let hour = interval["Hour"] as? Int,
              let minute = interval["Minute"] as? Int
        else { return nil }
        return (hour, minute)
    }

    func launchAgentURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.agentLabel).plist", isDirectory: false)
    }

    private func logURL(_ name: String) throws -> URL {
        let logsURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("KeepGoing", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        return logsURL.appendingPathComponent(name, isDirectory: false)
    }

    private func validate(_ target: AutoMessageTarget) -> AutoMessageRunResult? {
        let name = AutoMessageDestination.resolve(target).displayName
        if target.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failed("自动消息配置错误：应用名称不能为空")
        }

        if target.processName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failed("\(name)：进程名称不能为空")
        }

        do {
            let message = AutoMessageMessageComposer.messageText(for: target)
            let fileURLs = try AutoMessageMessageComposer.fileURLs(for: target)
            if message.isEmpty && fileURLs.isEmpty {
                return .failed("\(name)：消息和附件都是空的，未发送")
            }
        } catch {
            return .failed("\(name)：\(error.localizedDescription)")
        }

        return nil
    }

    private func send(target: AutoMessageTarget, submit: Bool) -> AutoMessageRunResult {
        let destination = AutoMessageDestination.resolve(target)
        let appName = destination.displayName
        let processName = destination.processName
        let message = AutoMessageMessageComposer.messageText(for: target)
        let fileURLs: [URL]
        do {
            fileURLs = try AutoMessageMessageComposer.fileURLs(for: target)
        } catch {
            return .failed("\(appName)：\(error.localizedDescription)")
        }

        let activateArguments: [String]
        if let bundleIdentifier = destination.bundleIdentifier {
            activateArguments = ["-b", bundleIdentifier]
        } else {
            activateArguments = ["-a", destination.applicationName]
        }
        let activate = runCommand("/usr/bin/open", activateArguments, timeout: 30)
        if activate.code != 0 {
            return .failed("打开 \(appName) 失败：\(cleanMessage(activate.stderr, fallback: activate.stdout))")
        }

        Thread.sleep(forTimeInterval: max(0, target.launchWaitSeconds))

        let isClaude = processName.localizedCaseInsensitiveContains("claude")
        if isClaude {
            Thread.sleep(forTimeInterval: 0.4)
            _ = clickChatInput(for: processName)
        }

        let pasteboard = NSPasteboard.general
        if !message.isEmpty {
            pasteboard.clearContents()
            pasteboard.setString(message, forType: .string)
            lastOwnPasteboardChange = pasteboard.changeCount

            if let failure = pasteClipboard(to: appName, processName: processName, isClaude: isClaude) {
                return failure
            }
        }

        if !fileURLs.isEmpty {
            Thread.sleep(forTimeInterval: message.isEmpty ? 0.4 : 0.8)
            pasteboard.clearContents()
            guard pasteboard.writeObjects(fileURLs as [NSURL]) else {
                return .failed("\(appName)：写入附件到剪贴板失败")
            }
            lastOwnPasteboardChange = pasteboard.changeCount

            if let failure = pasteClipboard(to: appName, processName: processName, isClaude: isClaude) {
                return failure
            }
        }

        if submit {
            Thread.sleep(forTimeInterval: fileURLs.isEmpty ? 0.8 : 2.0)
            if let failure = submitMessage(to: appName, processName: processName) {
                return failure
            }
        }

        let fileSummary = fileURLs.isEmpty ? "" : "，附件 \(fileURLs.count) 个"
        return .sent(submit ? "已发送到 \(appName)\(fileSummary) 并回车提交" : "已粘贴到 \(appName)\(fileSummary)")
    }

    private func pasteClipboard(
        to appName: String,
        processName: String,
        isClaude: Bool
    ) -> AutoMessageRunResult? {
        let pasteCommand: String
        if isClaude {
            pasteCommand = """
                try
                    click menu item "Paste" of menu "Edit" of menu bar 1
                on error
                    keystroke "v" using command down
                end try
            """
        } else {
            pasteCommand = "keystroke \"v\" using command down"
        }

        let pasteScript = """
        tell application "System Events"
            tell process \(appleScriptLiteral(processName))
                set frontmost to true
                delay 0.5
                \(pasteCommand)
            end tell
        end tell
        """
        let paste = runCommand("/usr/bin/osascript", ["-e", pasteScript], timeout: 30)
        if paste.code != 0 {
            return .failed("发送到 \(appName) 失败。请在 系统设置 → 隐私与安全性 → 辅助功能 中允许 Iverson’s WorkTool；定时任务还要允许 keepgoing-automessage。\(cleanMessage(paste.stderr, fallback: paste.stdout))")
        }

        return nil
    }

    private func submitMessage(to appName: String, processName: String) -> AutoMessageRunResult? {
        let submit = runCommand("/usr/bin/osascript", [
            "-e",
            """
            tell application "System Events"
                tell process \(appleScriptLiteral(processName))
                    set frontmost to true
                    delay 0.6
                    key code 36
                end tell
            end tell
            """,
        ], timeout: 30)
        if submit.code != 0 {
            return .failed("\(appName) 已粘贴，但提交失败：\(cleanMessage(submit.stderr, fallback: submit.stdout))")
        }

        return nil
    }

    private func clickChatInput(for processName: String) -> Bool {
        guard let bounds = targetWindowBounds(for: processName) else { return false }
        return clickScreenPoint(CGPoint(x: bounds.midX, y: bounds.maxY - 72))
    }

    private func targetWindowBounds(for processName: String) -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard
                let ownerName = window[kCGWindowOwnerName as String] as? String,
                ownerName.localizedCaseInsensitiveContains(processName),
                let layer = window[kCGWindowLayer as String] as? Int,
                layer == 0,
                let boundsDictionary = window[kCGWindowBounds as String] as? [String: Any]
            else {
                continue
            }

            var bounds = CGRect.zero
            if CGRectMakeWithDictionaryRepresentation(boundsDictionary as CFDictionary, &bounds) {
                return bounds
            }
        }

        return nil
    }

    private func clickScreenPoint(_ point: CGPoint) -> Bool {
        guard
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else {
            return false
        }

        down.post(tap: .cghidEventTap)
        usleep(80_000)
        up.post(tap: .cghidEventTap)
        usleep(120_000)
        return true
    }

    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        // The value of kAXTrustedCheckOptionPrompt; the constant is a mutable global in Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
