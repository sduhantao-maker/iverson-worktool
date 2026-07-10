import Cocoa
import Foundation
import ApplicationServices

struct AutoMessageRunResult {
    let ok: Bool
    let message: String
}

final class AutoMessageRunner {
    static let agentLabel = "com.iverson.keepgoing.automessage"

    let store: AutoMessageSettingsStore

    init(store: AutoMessageSettingsStore = AutoMessageSettingsStore()) {
        self.store = store
    }

    func runOnce() -> AutoMessageRunResult {
        do {
            let settings = try store.load()
            return run(settings: settings)
        } catch {
            return AutoMessageRunResult(
                ok: false,
                message: "读取自动消息配置失败：\(error.localizedDescription)"
            )
        }
    }

    func run(settings: AutoMessageSettings) -> AutoMessageRunResult {
        let enabledTargets = settings.targets.filter(\.enabled)

        if settings.dryRun {
            let appNames = enabledTargets
                .map { AutoMessageDestination.resolve($0).displayName }
                .filter { !$0.isEmpty }
                .joined(separator: "、")
            return AutoMessageRunResult(
                ok: true,
                message: "Dry run 已开启：不会粘贴或发送；目标是 \(appNames.isEmpty ? "无启用目标" : appNames)"
            )
        }

        if let startDateSkip = skipResultBeforeStartDate(settings) {
            return startDateSkip
        }

        guard accessibilityTrusted(prompt: true) else {
            return AutoMessageRunResult(
                ok: false,
                message: "需要辅助功能权限：请在 System Settings -> Privacy & Security -> Accessibility 允许当前程序。测试发送允许 Iverson’s WorkTool；定时发送允许 keepgoing-automessage。"
            )
        }

        for target in enabledTargets {
            if let failure = validate(target) {
                return failure
            }

            let result = send(target: target, submit: settings.submitAfterPaste)
            if !result.ok {
                return result
            }
        }

        return AutoMessageRunResult(ok: true, message: "自动消息发送完成")
    }

    private func skipResultBeforeStartDate(_ settings: AutoMessageSettings) -> AutoMessageRunResult? {
        guard let startDate = settings.startDate else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDay = calendar.startOfDay(for: startDate)
        guard today < startDay else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return AutoMessageRunResult(
            ok: true,
            message: "未到开始日期：\(formatter.string(from: startDay)) 后开始发送"
        )
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
            _ = runCommand("/bin/launchctl", ["bootout", "\(domain)/\(Self.agentLabel)"])
            let bootstrap = runCommand("/bin/launchctl", ["bootstrap", domain, plistURL.path])
            if bootstrap.code != 0 {
                return AutoMessageRunResult(
                    ok: false,
                    message: "安装自动消息定时任务失败：\(cleanMessage(bootstrap.stderr, fallback: bootstrap.stdout))"
                )
            }

            return AutoMessageRunResult(ok: true, message: "自动消息定时任务已安装")
        } catch {
            return AutoMessageRunResult(
                ok: false,
                message: "安装自动消息定时任务失败：\(error.localizedDescription)"
            )
        }
    }

    func uninstallLaunchAgent() -> AutoMessageRunResult {
        let domain = "gui/\(getuid())"
        _ = runCommand("/bin/launchctl", ["bootout", "\(domain)/\(Self.agentLabel)"])

        do {
            let plistURL = launchAgentURL()
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
            return AutoMessageRunResult(ok: true, message: "自动消息定时任务已卸载")
        } catch {
            return AutoMessageRunResult(
                ok: false,
                message: "卸载自动消息定时任务失败：\(error.localizedDescription)"
            )
        }
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
        if target.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AutoMessageRunResult(ok: false, message: "自动消息配置错误：应用名称不能为空")
        }

        if target.processName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AutoMessageRunResult(ok: false, message: "自动消息配置错误：进程名称不能为空")
        }

        do {
            let message = AutoMessageMessageComposer.messageText(for: target)
            let fileURLs = try AutoMessageMessageComposer.fileURLs(for: target)
            if message.isEmpty && fileURLs.isEmpty {
                return AutoMessageRunResult(ok: false, message: "自动消息配置错误：消息或附件不能为空")
            }
        } catch {
            return AutoMessageRunResult(ok: false, message: error.localizedDescription)
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
            return AutoMessageRunResult(ok: false, message: error.localizedDescription)
        }

        let activateArguments: [String]
        if let bundleIdentifier = destination.bundleIdentifier {
            activateArguments = ["-b", bundleIdentifier]
        } else {
            activateArguments = ["-a", destination.applicationName]
        }
        let activate = runCommand("/usr/bin/open", activateArguments)
        if activate.code != 0 {
            return AutoMessageRunResult(
                ok: false,
                message: "打开 \(appName) 失败：\(cleanMessage(activate.stderr, fallback: activate.stdout))"
            )
        }

        Thread.sleep(forTimeInterval: max(0, target.launchWaitSeconds))

        let isClaude = processName.localizedCaseInsensitiveContains("claude")
        if isClaude {
            Thread.sleep(forTimeInterval: 0.4)
            _ = clickChatInput(for: processName)
        }

        if !message.isEmpty {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(message, forType: .string)

            if let failure = pasteClipboard(to: appName, processName: processName, isClaude: isClaude) {
                return failure
            }
        }

        if !fileURLs.isEmpty {
            Thread.sleep(forTimeInterval: message.isEmpty ? 0.4 : 0.8)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.writeObjects(fileURLs as [NSURL]) else {
                return AutoMessageRunResult(
                    ok: false,
                    message: "写入附件到剪贴板失败"
                )
            }

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
        return AutoMessageRunResult(ok: true, message: submit ? "已发送到 \(appName)\(fileSummary) 并回车提交" : "已发送到 \(appName)\(fileSummary)")
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
        let paste = runCommand("/usr/bin/osascript", ["-e", pasteScript])
        if paste.code != 0 {
            return AutoMessageRunResult(
                ok: false,
                message: "发送到 \(appName) 失败。请在 System Settings -> Privacy & Security -> Accessibility -> Iverson’s WorkTool 开启辅助功能权限。若是定时任务触发失败，也请允许 keepgoing-automessage。\(cleanMessage(paste.stderr, fallback: paste.stdout))"
            )
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
        ])
        if submit.code != 0 {
            return AutoMessageRunResult(
                ok: false,
                message: "发送到 \(appName) 已粘贴但提交失败：\(cleanMessage(submit.stderr, fallback: submit.stdout))"
            )
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

    private func accessibilityTrusted(prompt: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
