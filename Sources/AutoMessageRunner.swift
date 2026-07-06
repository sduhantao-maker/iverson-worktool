import Cocoa
import Foundation

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
                .map { $0.appName.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "、")
            return AutoMessageRunResult(
                ok: true,
                message: "Dry run 已开启：不会粘贴或发送；目标是 \(appNames.isEmpty ? "无启用目标" : appNames)"
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

        if cleanMessage(target.message, fallback: "").isEmpty {
            return AutoMessageRunResult(ok: false, message: "自动消息配置错误：消息内容不能为空")
        }

        return nil
    }

    private func send(target: AutoMessageTarget, submit: Bool) -> AutoMessageRunResult {
        let appName = target.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let processName = target.processName.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = cleanMessage(target.message, fallback: "")

        let activateScript = "tell application \(appleScriptLiteral(appName)) to activate"
        let activate = runCommand("/usr/bin/osascript", ["-e", activateScript])
        if activate.code != 0 {
            return AutoMessageRunResult(
                ok: false,
                message: "打开 \(appName) 失败：\(cleanMessage(activate.stderr, fallback: activate.stdout))"
            )
        }

        Thread.sleep(forTimeInterval: max(0, target.launchWaitSeconds))

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message, forType: .string)

        let submitScript = submit ? "\ndelay 0.45\nkey code 36" : ""
        let pasteScript = """
        tell application "System Events"
            tell process \(appleScriptLiteral(processName))
                set frontmost to true
                keystroke "v" using command down\(submitScript)
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

        return AutoMessageRunResult(ok: true, message: submit ? "已发送到 \(appName) 并回车提交" : "已发送到 \(appName)")
    }
}
