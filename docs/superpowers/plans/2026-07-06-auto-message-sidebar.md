# Auto Message Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a BetterDisplay-style sidebar to KeepGoing and add an Auto Message section without redesigning the existing KeepGoing screen.

**Architecture:** Split the current monolithic `Sources/App.swift` into focused Cocoa controllers and utilities. KeepGoing remains a dedicated content controller reused inside a new two-column shell; Auto Message gets its own settings model, view controller, send engine, and scheduled helper executable.

**Tech Stack:** Swift, Cocoa/AppKit, AppleScript via `osascript`, user LaunchAgent plist via `PropertyListSerialization`, existing `swiftc` build script.

---

## File Structure

- Modify `Sources/App.swift`: keep app delegate only, resize window for sidebar shell, set root controller to `RootViewController`.
- Create `Sources/KeepGoingViewController.swift`: move existing `MainViewController` KeepGoing UI and helper logic here with behavior preserved.
- Create `Sources/UIComponents.swift`: move shared AppKit controls and helper functions used by both sections.
- Create `Sources/RootViewController.swift`: own sidebar, nav state, and right-side content host.
- Create `Sources/AutoMessageSettings.swift`: codable settings model, defaults, Application Support read/write.
- Create `Sources/AutoMessageRunner.swift`: run-once send engine and LaunchAgent install/uninstall.
- Create `Sources/AutoMessageViewController.swift`: AppKit UI for Auto Message configuration, status, test send, install/uninstall.
- Create `Sources/automessage_helper.swift`: command-line helper built into `Contents/Resources/keepgoing-automessage`.
- Modify `Scripts/build_app.sh`: compile new source files and bundled helper.
- Modify `README.md`: document new Auto Message section and Accessibility permission.

## Task 1: Split Shared UI And Utilities

**Files:**
- Modify: `Sources/App.swift`
- Create: `Sources/UIComponents.swift`
- Test: build compile check

- [ ] **Step 1: Create `Sources/UIComponents.swift`**

Move these existing declarations from `Sources/App.swift` into the new file unchanged, preserving each current implementation exactly:

```swift
import Cocoa

struct CommandResult {
    let code: Int32
    let stdout: String
    let stderr: String
}
```

Move the full existing definitions for:

- `ToolbarBackgroundView`
- `ToggleSwitch`
- `CardView`
- `BadgeView`
- `SymbolTile`
- `ToolbarItem`
- `TriangleView`
- `makeLabel(_:,font:,color:)`
- `runCommand(_:_:)`
- `shellQuote(_:)`
- `appleScriptLiteral(_:)`
- `cleanMessage(_:fallback:)`

Remove `private` from moved types/functions that other files need.

- [ ] **Step 2: Remove moved declarations from `Sources/App.swift`**

Leave only `import Cocoa`, `helperPath`, `HelperState`, `AppDelegate`, and the current controller until Task 2 moves it.

- [ ] **Step 3: Update `Scripts/build_app.sh` compile list**

Replace the current `swiftc` file list with:

```zsh
/usr/bin/swiftc \
  -O \
  -framework Cocoa \
  -o "$MACOS/KeepGoing" \
  "$ROOT/Sources/main.swift" \
  "$ROOT/Sources/UIComponents.swift" \
  "$ROOT/Sources/App.swift"
```

- [ ] **Step 4: Build**

Run:

```bash
./Scripts/build_app.sh
```

Expected: `dist/KeepGoing.app` path printed and no compile errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/App.swift Sources/UIComponents.swift Scripts/build_app.sh
git commit -m "refactor: split shared UI components"
```

## Task 2: Move KeepGoing Screen Into Its Own Controller

**Files:**
- Modify: `Sources/App.swift`
- Create: `Sources/KeepGoingViewController.swift`
- Modify: `Scripts/build_app.sh`
- Test: build compile check

- [ ] **Step 1: Create `Sources/KeepGoingViewController.swift`**

Create the file by moving the complete existing `MainViewController` declaration from `Sources/App.swift` into `Sources/KeepGoingViewController.swift`, then rename the class declaration from:

```swift
final class MainViewController: NSViewController {
```

to:

```swift
import Cocoa

private let helperPath = "/usr/local/bin/keepgoing-helper"

private enum HelperState {
    case ready(mode: String)
    case setupRequired(currentMode: String)
    case working(String)
    case error(String)
}

final class KeepGoingViewController: NSViewController {
```

Keep the full moved class body between that opening line and the original final `}` of `MainViewController`.

Place these helper functions after the class:

```swift

private func readCurrentModeWithoutHelper() -> String {
    let result = runCommand("/usr/bin/pmset", ["-g"])
    for line in result.stdout.split(separator: "\n") {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        if parts.count >= 2 && parts[0] == "SleepDisabled" {
            return parts[1] == "1" ? "enabled" : "normal"
        }
    }
    return "normal"
}

private func normalizedMode(_ output: String) -> String {
    output.trimmingCharacters(in: .whitespacesAndNewlines) == "enabled" ? "enabled" : "normal"
}
```

Inside the moved class, keep all existing UI constants and actions unchanged. Keep `loadView()` root size `800 x 590` for now.

- [ ] **Step 2: Simplify `Sources/App.swift`**

Replace the controller property and creation:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var controller: KeepGoingViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = KeepGoingViewController()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 590),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "KeepGoing"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 800, height: 590)
        window.maxSize = NSSize(width: 800, height: 590)
        window.contentViewController = controller
        window.center()
        window.isReleasedWhenClosed = false
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    private func showWindow() {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
```

- [ ] **Step 3: Update build script source list**

```zsh
/usr/bin/swiftc \
  -O \
  -framework Cocoa \
  -o "$MACOS/KeepGoing" \
  "$ROOT/Sources/main.swift" \
  "$ROOT/Sources/UIComponents.swift" \
  "$ROOT/Sources/KeepGoingViewController.swift" \
  "$ROOT/Sources/App.swift"
```

- [ ] **Step 4: Build**

Run:

```bash
./Scripts/build_app.sh
```

Expected: build succeeds. Visual behavior should still match current KeepGoing because root controller is only renamed/moved.

- [ ] **Step 5: Commit**

```bash
git add Sources/App.swift Sources/KeepGoingViewController.swift Scripts/build_app.sh
git commit -m "refactor: isolate KeepGoing view controller"
```

## Task 3: Add Sidebar Shell

**Files:**
- Create: `Sources/RootViewController.swift`
- Modify: `Sources/App.swift`
- Modify: `Sources/KeepGoingViewController.swift`
- Modify: `Scripts/build_app.sh`
- Test: build and manual launch

- [ ] **Step 1: Create sidebar models and button view**

Create `Sources/RootViewController.swift`:

```swift
import Cocoa

private enum Section: CaseIterable {
    case keepGoing
    case autoMessage

    var title: String {
        switch self {
        case .keepGoing: return "KeepGoing"
        case .autoMessage: return "Auto Message"
        }
    }

    var symbol: String {
        switch self {
        case .keepGoing: return "bolt.fill"
        case .autoMessage: return "message.fill"
        }
    }
}

final class SidebarItemButton: NSControl {
    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let section: Section
    var onSelect: ((Section) -> Void)?
    var isSelectedItem = false { didSet { updateAppearance() } }

    init(section: Section) {
        self.section = section
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentTintColor = .systemBlue
        if #available(macOS 11.0, *) {
            imageView.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil)
        }
        label.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = section.title
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        addSubview(imageView)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        onSelect?(section)
    }

    private func updateAppearance() {
        layer?.backgroundColor = isSelectedItem
            ? NSColor(calibratedWhite: 0.82, alpha: 1).cgColor
            : NSColor.clear.cgColor
    }
}
```

- [ ] **Step 2: Add `RootViewController`**

Append in same file:

```swift
final class RootViewController: NSViewController {
    private let sidebar = NSView()
    private let contentHost = NSView()
    private let keepGoingController = KeepGoingViewController()
    private let placeholderAutoMessage = NSViewController()
    private var activeController: NSViewController?
    private var buttons: [Section: SidebarItemButton] = [:]

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1010, height: 590))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.white.cgColor
        view = root
        buildLayout(in: root)
        select(.keepGoing)
    }

    private func buildLayout(in root: NSView) {
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1).cgColor
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)
        root.addSubview(contentHost)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 210),
            contentHost.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: root.topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        buildSidebar()
    }

    private func buildSidebar() {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        sidebar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 78),
        ])
        for section in Section.allCases {
            let button = SidebarItemButton(section: section)
            button.onSelect = { [weak self] selected in self?.select(selected) }
            buttons[section] = button
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func select(_ section: Section) {
        buttons.forEach { key, button in button.isSelectedItem = key == section }
        let controller: NSViewController
        switch section {
        case .keepGoing:
            controller = keepGoingController
        case .autoMessage:
            controller = makeAutoMessagePlaceholder()
        }
        show(controller)
    }

    private func show(_ controller: NSViewController) {
        if activeController === controller { return }
        activeController?.view.removeFromSuperview()
        activeController?.removeFromParent()
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: contentHost.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ])
        activeController = controller
    }

    private func makeAutoMessagePlaceholder() -> NSViewController {
        let controller = NSViewController()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 590))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.98, alpha: 1).cgColor
        let label = makeLabel("Auto Message", font: .systemFont(ofSize: 18, weight: .bold), color: .labelColor)
        root.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        controller.view = root
        return controller
    }
}
```

- [ ] **Step 3: Change `AppDelegate` to use root shell**

In `Sources/App.swift`, set:

```swift
private var controller: RootViewController!
controller = RootViewController()
window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1010, height: 590),
    styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
    backing: .buffered,
    defer: false
)
window.minSize = NSSize(width: 1010, height: 590)
window.maxSize = NSSize(width: 1010, height: 590)
```

- [ ] **Step 4: KeepGoing content remains 800 px wide**

In `KeepGoingViewController.loadView()`, leave:

```swift
let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 590))
```

The sidebar consumes 210 px, so right content still gets 800 px and existing layout remains visually stable.

- [ ] **Step 5: Update build script**

Add `"$ROOT/Sources/RootViewController.swift"` before `App.swift`.

- [ ] **Step 6: Build and launch**

Run:

```bash
./Scripts/build_app.sh
open dist/KeepGoing.app
```

Expected: sidebar visible, KeepGoing selected by default, original KeepGoing content visible on right, Auto Message selection shows placeholder.

- [ ] **Step 7: Commit**

```bash
git add Sources/App.swift Sources/KeepGoingViewController.swift Sources/RootViewController.swift Scripts/build_app.sh
git commit -m "feat: add sidebar shell"
```

## Task 4: Add Auto Message Settings Model

**Files:**
- Create: `Sources/AutoMessageSettings.swift`
- Modify: `Scripts/build_app.sh`
- Test: build compile check

- [ ] **Step 1: Create settings model**

Create `Sources/AutoMessageSettings.swift`:

```swift
import Foundation

struct AutoMessageTarget: Codable, Equatable {
    var enabled: Bool
    var appName: String
    var processName: String
    var message: String
    var launchWaitSeconds: Double
}

struct AutoMessageSettings: Codable, Equatable {
    var hour: Int
    var minute: Int
    var dryRun: Bool
    var submitAfterPaste: Bool
    var targets: [AutoMessageTarget]
    var updatedAt: Date

    static var defaults: AutoMessageSettings {
        AutoMessageSettings(
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

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeepGoing", isDirectory: true)
        self.fileURL = base.appendingPathComponent("auto-message.json")
    }

    func load() throws -> AutoMessageSettings {
        let manager = FileManager.default
        if !manager.fileExists(atPath: fileURL.path) {
            let settings = AutoMessageSettings.defaults
            try save(settings)
            return settings
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AutoMessageSettings.self, from: data)
    }

    func save(_ settings: AutoMessageSettings) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var updated = settings
        updated.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(updated)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 2: Add to build script**

Add `"$ROOT/Sources/AutoMessageSettings.swift"` before `RootViewController.swift`.

- [ ] **Step 3: Build**

Run:

```bash
./Scripts/build_app.sh
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/AutoMessageSettings.swift Scripts/build_app.sh
git commit -m "feat: add Auto Message settings model"
```

## Task 5: Add Auto Message Runner And LaunchAgent

**Files:**
- Create: `Sources/AutoMessageRunner.swift`
- Modify: `Scripts/build_app.sh`
- Test: build compile check and `plutil -lint`

- [ ] **Step 1: Create runner**

Create `Sources/AutoMessageRunner.swift`:

```swift
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
            return AutoMessageRunResult(ok: false, message: "读取配置失败：\(error.localizedDescription)")
        }
    }

    func run(settings: AutoMessageSettings) -> AutoMessageRunResult {
        if settings.dryRun {
            let names = settings.targets.filter(\.enabled).map(\.appName).joined(separator: ", ")
            return AutoMessageRunResult(ok: true, message: "Dry run：将发送到 \(names)")
        }
        for target in settings.targets where target.enabled {
            let validation = validate(target)
            if !validation.ok { return validation }
            let result = send(target: target, submit: settings.submitAfterPaste)
            if !result.ok { return result }
        }
        return AutoMessageRunResult(ok: true, message: "发送完成")
    }

    func installLaunchAgent(helperPath: String, settings: AutoMessageSettings) -> AutoMessageRunResult {
        do {
            try store.save(settings)
            let plistURL = launchAgentURL()
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "Label": Self.agentLabel,
                "ProgramArguments": [helperPath],
                "StartCalendarInterval": ["Hour": settings.hour, "Minute": settings.minute],
                "RunAtLoad": false,
                "StandardOutPath": logURL("automessage.out.log").path,
                "StandardErrorPath": logURL("automessage.err.log").path,
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            _ = runCommand("/bin/launchctl", ["bootout", "gui/\(getuid())", plistURL.path])
            let load = runCommand("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path])
            if load.code != 0 {
                return AutoMessageRunResult(ok: false, message: cleanMessage(load.stderr, fallback: load.stdout))
            }
            return AutoMessageRunResult(ok: true, message: "定时任务已安装：\(String(format: "%02d:%02d", settings.hour, settings.minute))")
        } catch {
            return AutoMessageRunResult(ok: false, message: "安装定时任务失败：\(error.localizedDescription)")
        }
    }

    func uninstallLaunchAgent() -> AutoMessageRunResult {
        let plistURL = launchAgentURL()
        _ = runCommand("/bin/launchctl", ["bootout", "gui/\(getuid())", plistURL.path])
        do {
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
            return AutoMessageRunResult(ok: true, message: "定时任务已卸载")
        } catch {
            return AutoMessageRunResult(ok: false, message: "卸载定时任务失败：\(error.localizedDescription)")
        }
    }

    func launchAgentURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.agentLabel).plist")
    }

    private func logURL(_ name: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeepGoing/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    private func validate(_ target: AutoMessageTarget) -> AutoMessageRunResult {
        if target.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AutoMessageRunResult(ok: false, message: "目标 app 名称不能为空")
        }
        if target.processName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AutoMessageRunResult(ok: false, message: "目标 process 名称不能为空")
        }
        if target.message.isEmpty {
            return AutoMessageRunResult(ok: false, message: "\(target.appName) 消息为空")
        }
        return AutoMessageRunResult(ok: true, message: "")
    }

    private func send(target: AutoMessageTarget, submit: Bool) -> AutoMessageRunResult {
        let launchScript = """
        tell application \(appleScriptLiteral(target.appName))
            activate
        end tell
        """
        let launch = runCommand("/usr/bin/osascript", ["-e", launchScript])
        if launch.code != 0 {
            return AutoMessageRunResult(ok: false, message: cleanMessage(launch.stderr, fallback: launch.stdout))
        }
        Thread.sleep(forTimeInterval: target.launchWaitSeconds)
        let submitLine = submit ? "key code 36" : ""
        let pasteScript = """
        set the clipboard to \(appleScriptLiteral(target.message))
        tell application "System Events"
            tell process \(appleScriptLiteral(target.processName))
                set frontmost to true
                delay 0.5
                keystroke "v" using command down
                delay 0.2
                \(submitLine)
            end tell
        end tell
        """
        let paste = runCommand("/usr/bin/osascript", ["-e", pasteScript])
        if paste.code != 0 {
            let message = cleanMessage(paste.stderr, fallback: paste.stdout)
            if message.localizedCaseInsensitiveContains("not authorized") || message.localizedCaseInsensitiveContains("not allowed") {
                return AutoMessageRunResult(ok: false, message: "需要 Accessibility 权限：System Settings -> Privacy & Security -> Accessibility -> KeepGoing")
            }
            return AutoMessageRunResult(ok: false, message: message)
        }
        return AutoMessageRunResult(ok: true, message: "\(target.appName) 已发送")
    }
}
```

- [ ] **Step 2: Add to build script**

Add `"$ROOT/Sources/AutoMessageRunner.swift"` to the main app `swiftc` list after `AutoMessageSettings.swift`.

- [ ] **Step 3: Build**

Run:

```bash
./Scripts/build_app.sh
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/AutoMessageRunner.swift Scripts/build_app.sh
git commit -m "feat: add Auto Message runner"
```

## Task 6: Build Auto Message View

**Files:**
- Create: `Sources/AutoMessageViewController.swift`
- Modify: `Sources/RootViewController.swift`
- Modify: `Scripts/build_app.sh`
- Test: build and manual UI check

- [ ] **Step 1: Create controller skeleton**

Create `Sources/AutoMessageViewController.swift`:

```swift
import Cocoa

final class AutoMessageViewController: NSViewController {
    private let store = AutoMessageSettingsStore()
    private let runner = AutoMessageRunner()
    private var settings = AutoMessageSettings.defaults
    private let hourField = NSTextField()
    private let minuteField = NSTextField()
    private let dryRunSwitch = ToggleSwitch()
    private let submitSwitch = ToggleSwitch()
    private let statusLabel = NSTextField(labelWithString: " ")
    private let targetsStack = NSStackView()
    private var targetRows: [AutoMessageTargetRowView] = []

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 590))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.98, alpha: 1).cgColor
        view = root
        buildUI(in: root)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        do {
            settings = try store.load()
        } catch {
            settings = .defaults
            statusLabel.stringValue = "读取配置失败，已使用默认值：\(error.localizedDescription)"
        }
        applySettingsToUI()
    }
}
```

- [ ] **Step 2: Add UI build methods**

Append:

```swift
private extension AutoMessageViewController {
    func buildUI(in root: NSView) {
        let toolbar = ToolbarBackgroundView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        let title = makeLabel("Auto Message", font: .systemFont(ofSize: 13, weight: .semibold), color: .secondaryLabelColor)
        let icon = SymbolTile(symbol: "message.fill", fill: NSColor.systemBlue.withAlphaComponent(0.18), tint: .systemBlue)
        icon.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(icon)
        toolbar.addSubview(title)

        let content = NSStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.spacing = 10
        content.alignment = .leading

        root.addSubview(toolbar)
        root.addSubview(content)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 118),
            icon.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            icon.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 28),
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
            title.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8),
            content.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 28),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
        ])

        let schedule = makeScheduleCard()
        let targets = makeTargetsCard()
        let actions = makeActionsCard()
        content.addArrangedSubview(schedule)
        content.addArrangedSubview(targets)
        content.addArrangedSubview(actions)
        [schedule, targets, actions].forEach { $0.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
    }

    func makeScheduleCard() -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 96).isActive = true
        let title = makeLabel("定时发送", font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
        let hour = makeLabel("时", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        let minute = makeLabel("分", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        hourField.translatesAutoresizingMaskIntoConstraints = false
        minuteField.translatesAutoresizingMaskIntoConstraints = false
        hourField.alignment = .center
        minuteField.alignment = .center
        [title, hour, minute, hourField, minuteField].forEach(card.addSubview)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            hourField.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            hourField.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            hourField.widthAnchor.constraint(equalToConstant: 54),
            minuteField.leadingAnchor.constraint(equalTo: hourField.trailingAnchor, constant: 24),
            minuteField.centerYAnchor.constraint(equalTo: hourField.centerYAnchor),
            minuteField.widthAnchor.constraint(equalToConstant: 54),
            hour.leadingAnchor.constraint(equalTo: hourField.trailingAnchor, constant: 6),
            hour.centerYAnchor.constraint(equalTo: hourField.centerYAnchor),
            minute.leadingAnchor.constraint(equalTo: minuteField.trailingAnchor, constant: 6),
            minute.centerYAnchor.constraint(equalTo: minuteField.centerYAnchor),
        ])
        return card
    }

    func makeTargetsCard() -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 210).isActive = true
        targetsStack.translatesAutoresizingMaskIntoConstraints = false
        targetsStack.orientation = .vertical
        targetsStack.spacing = 10
        targetsStack.alignment = .leading
        let title = makeLabel("目标与消息", font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
        card.addSubview(title)
        card.addSubview(targetsStack)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            targetsStack.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            targetsStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            targetsStack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
        ])
        targetRows = AutoMessageSettings.defaults.targets.map { AutoMessageTargetRowView(target: $0) }
        targetRows.forEach { row in
            targetsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: targetsStack.widthAnchor).isActive = true
        }
        return card
    }

    func makeActionsCard() -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 118).isActive = true
        let dryRunLabel = makeLabel("Dry run", font: .systemFont(ofSize: 13), color: .labelColor)
        let submitLabel = makeLabel("Submit after paste", font: .systemFont(ofSize: 13), color: .labelColor)
        let testButton = NSButton(title: "测试发送", target: self, action: #selector(testSend))
        let installButton = NSButton(title: "安装定时任务", target: self, action: #selector(installSchedule))
        let uninstallButton = NSButton(title: "卸载", target: self, action: #selector(uninstallSchedule))
        [dryRunSwitch, submitSwitch, dryRunLabel, submitLabel, testButton, installButton, uninstallButton, statusLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview($0)
        }
        NSLayoutConstraint.activate([
            dryRunLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            dryRunLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            dryRunSwitch.leadingAnchor.constraint(equalTo: dryRunLabel.trailingAnchor, constant: 12),
            dryRunSwitch.centerYAnchor.constraint(equalTo: dryRunLabel.centerYAnchor),
            submitLabel.leadingAnchor.constraint(equalTo: dryRunSwitch.trailingAnchor, constant: 24),
            submitLabel.centerYAnchor.constraint(equalTo: dryRunLabel.centerYAnchor),
            submitSwitch.leadingAnchor.constraint(equalTo: submitLabel.trailingAnchor, constant: 12),
            submitSwitch.centerYAnchor.constraint(equalTo: submitLabel.centerYAnchor),
            testButton.leadingAnchor.constraint(equalTo: dryRunLabel.leadingAnchor),
            testButton.topAnchor.constraint(equalTo: dryRunLabel.bottomAnchor, constant: 22),
            installButton.leadingAnchor.constraint(equalTo: testButton.trailingAnchor, constant: 10),
            installButton.centerYAnchor.constraint(equalTo: testButton.centerYAnchor),
            uninstallButton.leadingAnchor.constraint(equalTo: installButton.trailingAnchor, constant: 10),
            uninstallButton.centerYAnchor.constraint(equalTo: testButton.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: uninstallButton.trailingAnchor, constant: 14),
            statusLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            statusLabel.centerYAnchor.constraint(equalTo: testButton.centerYAnchor),
        ])
        return card
    }
}
```

- [ ] **Step 3: Add row view and actions**

Append:

```swift
final class AutoMessageTargetRowView: NSView {
    private let enabledSwitch = ToggleSwitch()
    private let appField = NSTextField()
    private let processField = NSTextField()
    private let messageField = NSTextField()

    init(target: AutoMessageTarget) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 70).isActive = true
        [enabledSwitch, appField, processField, messageField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        enabledSwitch.isOn = target.enabled
        appField.stringValue = target.appName
        processField.stringValue = target.processName
        messageField.stringValue = target.message
        NSLayoutConstraint.activate([
            enabledSwitch.leadingAnchor.constraint(equalTo: leadingAnchor),
            enabledSwitch.centerYAnchor.constraint(equalTo: centerYAnchor),
            appField.leadingAnchor.constraint(equalTo: enabledSwitch.trailingAnchor, constant: 12),
            appField.topAnchor.constraint(equalTo: topAnchor),
            appField.widthAnchor.constraint(equalToConstant: 110),
            processField.leadingAnchor.constraint(equalTo: appField.trailingAnchor, constant: 8),
            processField.topAnchor.constraint(equalTo: topAnchor),
            processField.widthAnchor.constraint(equalToConstant: 110),
            messageField.leadingAnchor.constraint(equalTo: processField.trailingAnchor, constant: 8),
            messageField.trailingAnchor.constraint(equalTo: trailingAnchor),
            messageField.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func target() -> AutoMessageTarget {
        AutoMessageTarget(
            enabled: enabledSwitch.isOn,
            appName: appField.stringValue,
            processName: processField.stringValue,
            message: messageField.stringValue,
            launchWaitSeconds: 8
        )
    }
}

private extension AutoMessageViewController {
    func applySettingsToUI() {
        hourField.stringValue = "\(settings.hour)"
        minuteField.stringValue = "\(settings.minute)"
        dryRunSwitch.isOn = settings.dryRun
        submitSwitch.isOn = settings.submitAfterPaste
        rebuildRows(with: settings.targets)
    }

    func rebuildRows(with targets: [AutoMessageTarget]) {
        targetRows.forEach {
            targetsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        targetRows = targets.map { AutoMessageTargetRowView(target: $0) }
        targetRows.forEach { row in
            targetsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: targetsStack.widthAnchor).isActive = true
        }
    }

    func readSettingsFromUI() throws -> AutoMessageSettings {
        guard let hour = Int(hourField.stringValue), 0...23 ~= hour else {
            throw NSError(domain: "AutoMessage", code: 1, userInfo: [NSLocalizedDescriptionKey: "小时必须是 0-23"])
        }
        guard let minute = Int(minuteField.stringValue), 0...59 ~= minute else {
            throw NSError(domain: "AutoMessage", code: 2, userInfo: [NSLocalizedDescriptionKey: "分钟必须是 0-59"])
        }
        return AutoMessageSettings(
            hour: hour,
            minute: minute,
            dryRun: dryRunSwitch.isOn,
            submitAfterPaste: submitSwitch.isOn,
            targets: targetRows.map { $0.target() },
            updatedAt: Date()
        )
    }

    @objc func testSend() {
        do {
            let newSettings = try readSettingsFromUI()
            try store.save(newSettings)
            let result = runner.run(settings: newSettings)
            statusLabel.stringValue = result.message
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc func installSchedule() {
        do {
            let newSettings = try readSettingsFromUI()
            let helper = Bundle.main.resourcePath.map { "\($0)/keepgoing-automessage" } ?? ""
            let result = runner.installLaunchAgent(helperPath: helper, settings: newSettings)
            statusLabel.stringValue = result.message
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc func uninstallSchedule() {
        let result = runner.uninstallLaunchAgent()
        statusLabel.stringValue = result.message
    }
}
```

- [ ] **Step 4: Replace Auto Message placeholder**

In `RootViewController`, replace `placeholderAutoMessage` and `makeAutoMessagePlaceholder()` with:

```swift
private let autoMessageController = AutoMessageViewController()
```

And in `select(_:)`:

```swift
case .autoMessage:
    controller = autoMessageController
```

- [ ] **Step 5: Add to build script**

Add `"$ROOT/Sources/AutoMessageViewController.swift"` before `RootViewController.swift`.

- [ ] **Step 6: Build and check UI**

Run:

```bash
./Scripts/build_app.sh
open dist/KeepGoing.app
```

Expected: Auto Message tab shows schedule, target rows, toggles, and action buttons. KeepGoing tab remains unchanged.

- [ ] **Step 7: Commit**

```bash
git add Sources/AutoMessageViewController.swift Sources/RootViewController.swift Scripts/build_app.sh
git commit -m "feat: add Auto Message settings UI"
```

## Task 7: Add Scheduled Helper Executable

**Files:**
- Create: `Sources/automessage_helper.swift`
- Modify: `Scripts/build_app.sh`
- Test: helper dry run

- [ ] **Step 1: Create helper entrypoint**

Create `Sources/automessage_helper.swift`:

```swift
import Cocoa
import Foundation

let runner = AutoMessageRunner()
let result = runner.runOnce()
FileHandle.standardOutput.write((result.message + "\n").data(using: .utf8)!)
exit(result.ok ? 0 : 1)
```

- [ ] **Step 2: Compile helper in build script**

Add after main app `swiftc` command:

```zsh
/usr/bin/swiftc \
  -O \
  -framework Cocoa \
  -o "$RESOURCES/keepgoing-automessage" \
  "$ROOT/Sources/UIComponents.swift" \
  "$ROOT/Sources/AutoMessageSettings.swift" \
  "$ROOT/Sources/AutoMessageRunner.swift" \
  "$ROOT/Sources/automessage_helper.swift"
```

Then ensure executable bit:

```zsh
/bin/chmod 755 "$RESOURCES/keepgoing-automessage"
```

- [ ] **Step 3: Build**

Run:

```bash
./Scripts/build_app.sh
```

Expected: file exists:

```bash
test -x dist/KeepGoing.app/Contents/Resources/keepgoing-automessage
```

- [ ] **Step 4: Dry-run helper**

Run:

```bash
dist/KeepGoing.app/Contents/Resources/keepgoing-automessage
```

Expected output contains `Dry run` with Codex/Claude if defaults are still enabled.

- [ ] **Step 5: Commit**

```bash
git add Sources/automessage_helper.swift Scripts/build_app.sh
git commit -m "feat: add Auto Message scheduled helper"
```

## Task 8: Validate LaunchAgent And Docs

**Files:**
- Modify: `README.md`
- Test: build, dry run, plist lint

- [ ] **Step 1: Update README**

Add section:

```markdown
## Auto Message

KeepGoing includes an Auto Message tab for scheduling messages to Codex and Claude.

- Keep `Dry run` enabled while testing.
- Grant Accessibility access to KeepGoing before real sends:
  `System Settings -> Privacy & Security -> Accessibility`.
- `Test Send` runs one send cycle immediately.
- `Install Schedule` writes and loads:
  `~/Library/LaunchAgents/com.iverson.keepgoing.automessage.plist`.
- `Uninstall` unloads and removes that LaunchAgent.

Settings are stored at:

```text
~/Library/Application Support/KeepGoing/auto-message.json
```
```

- [ ] **Step 2: Build final app**

Run:

```bash
./Scripts/build_app.sh
```

Expected: codesign verification succeeds and prints `dist/KeepGoing.app`.

- [ ] **Step 3: Manual UI verification**

Run:

```bash
open dist/KeepGoing.app
```

Check:

- KeepGoing opens selected.
- KeepGoing content visually matches original right-side layout.
- Sidebar has only `KeepGoing` and `Auto Message`.
- Auto Message screen opens when clicked.
- Editing values and clicking `测试发送` with dry run shows a dry-run message.

- [ ] **Step 4: LaunchAgent plist verification**

From Auto Message UI, click `安装定时任务` with dry run enabled. Then run:

```bash
plutil -lint ~/Library/LaunchAgents/com.iverson.keepgoing.automessage.plist
```

Expected:

```text
/Users/iverson/Library/LaunchAgents/com.iverson.keepgoing.automessage.plist: OK
```

- [ ] **Step 5: Git status and commit**

```bash
git add README.md
git commit -m "docs: document Auto Message"
git status --short
```

Expected: no tracked source changes remain. Generated `dist/` remains ignored.

## Self-Review

- Spec coverage: sidebar, preserved KeepGoing content, Auto Message UI, settings persistence, Swift-native send engine, bundled helper, LaunchAgent, Accessibility error text, and verification steps are all covered.
- Scope: single daily schedule shared by Codex and Claude only; per-target schedules are excluded as specified.
- Type consistency: `AutoMessageSettings`, `AutoMessageTarget`, `AutoMessageSettingsStore`, `AutoMessageRunner`, `AutoMessageViewController`, and `RootViewController` names are used consistently.
- Risk note: Task 6 row rebuilding is specified through the `targetsStack` property and `rebuildRows(with:)`; execute those lines exactly so saved targets replace default rows on load.
