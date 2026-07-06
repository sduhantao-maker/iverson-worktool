import Cocoa

private let helperPath = "/usr/local/bin/keepgoing-helper"

private enum HelperState {
    case ready(mode: String)
    case setupRequired(currentMode: String)
    case working(String)
    case error(String)
}

final class KeepGoingViewController: NSViewController {
    private let modeSwitch = ToggleSwitch()
    private let installButton = NSButton(title: "安装免密助手...", target: nil, action: nil)
    private let refreshButton = NSButton(title: "", target: nil, action: nil)
    private let statusBadge = BadgeView()
    private let helperBadge = BadgeView()
    private let statusTitle = NSTextField(labelWithString: "正在检查")
    private let statusDetail = NSTextField(labelWithString: "正在读取电脑睡眠状态。")
    private let helperDetail = NSTextField(labelWithString: " ")
    private let progress = NSProgressIndicator()
    private let keepAwakeToolbarItem = ToolbarItem(title: "保持运行", symbol: "bolt.fill")
    private let sleepToolbarItem = ToolbarItem(title: "正常睡眠", symbol: "moon.zzz.fill")
    private let toolbarPointer = TriangleView()
    private var toolbarPointerCenterConstraint: NSLayoutConstraint?
    private var suppressSwitchAction = false
    private var isApplyingMode = false

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 590))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.98, alpha: 1).cgColor
        view = root
        buildUI(in: root)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refreshStatus()
    }

    private func buildUI(in root: NSView) {
        let toolbar = ToolbarBackgroundView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.white.cgColor

        root.addSubview(toolbar)
        root.addSubview(content)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 118),

            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        buildToolbar(in: toolbar)
        buildContent(in: content)
    }

    private func buildToolbar(in toolbar: NSView) {
        keepAwakeToolbarItem.configure(active: false, accent: .systemYellow)
        sleepToolbarItem.configure(active: false, accent: .systemPurple)

        let stack = NSStackView(views: [keepAwakeToolbarItem, sleepToolbarItem])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 96
        stack.alignment = .centerY
        toolbar.addSubview(stack)

        toolbarPointer.translatesAutoresizingMaskIntoConstraints = false
        toolbarPointer.isHidden = true
        toolbar.addSubview(toolbarPointer)

        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.bezelStyle = .rounded
        refreshButton.toolTip = "刷新状态"
        refreshButton.target = self
        refreshButton.action = #selector(refreshFromButton)
        if #available(macOS 11.0, *) {
            refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        }
        toolbar.addSubview(refreshButton)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            stack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 28),

            toolbarPointer.widthAnchor.constraint(equalToConstant: 22),
            toolbarPointer.heightAnchor.constraint(equalToConstant: 12),
            toolbarPointer.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),

            refreshButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -18),
            refreshButton.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 22),
            refreshButton.widthAnchor.constraint(equalToConstant: 32),
            refreshButton.heightAnchor.constraint(equalToConstant: 28),
        ])

        toolbarPointerCenterConstraint = toolbarPointer.centerXAnchor.constraint(equalTo: keepAwakeToolbarItem.centerXAnchor)
        toolbarPointerCenterConstraint?.isActive = true
    }

    private func buildContent(in content: NSView) {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        content.addSubview(stack)

        let statusCard = makeStatusCard()
        let modeCard = makeModeCard()
        let helperCard = makeHelperCard()
        let warningCard = makeWarningCard()

        stack.addArrangedSubview(statusCard)
        stack.addArrangedSubview(modeCard)
        stack.addArrangedSubview(helperCard)
        stack.addArrangedSubview(warningCard)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            statusCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modeCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            helperCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            warningCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func makeStatusCard() -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 82).isActive = true

        let icon = SymbolTile(symbol: "macbook.and.iphone", fill: NSColor.systemBlue.withAlphaComponent(0.13), tint: .systemBlue)
        icon.translatesAutoresizingMaskIntoConstraints = false

        statusTitle.translatesAutoresizingMaskIntoConstraints = false
        statusTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        statusTitle.textColor = .labelColor

        statusDetail.translatesAutoresizingMaskIntoConstraints = false
        statusDetail.font = .systemFont(ofSize: 12)
        statusDetail.textColor = .secondaryLabelColor
        statusDetail.lineBreakMode = .byWordWrapping
        statusDetail.maximumNumberOfLines = 2

        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false

        card.addSubview(icon)
        card.addSubview(statusTitle)
        card.addSubview(statusDetail)
        card.addSubview(statusBadge)
        card.addSubview(progress)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),

            statusTitle.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            statusTitle.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            statusTitle.trailingAnchor.constraint(lessThanOrEqualTo: statusBadge.leadingAnchor, constant: -12),

            statusDetail.leadingAnchor.constraint(equalTo: statusTitle.leadingAnchor),
            statusDetail.topAnchor.constraint(equalTo: statusTitle.bottomAnchor, constant: 5),
            statusDetail.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -118),

            statusBadge.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            statusBadge.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            statusBadge.widthAnchor.constraint(equalToConstant: 92),
            statusBadge.heightAnchor.constraint(equalToConstant: 28),

            progress.trailingAnchor.constraint(equalTo: statusBadge.leadingAnchor, constant: -10),
            progress.centerYAnchor.constraint(equalTo: statusBadge.centerYAnchor),
        ])

        return card
    }

    private func makeModeCard() -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 104).isActive = true

        let icon = SymbolTile(symbol: "power", fill: NSColor.systemRed.withAlphaComponent(0.13), tint: .systemRed)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = makeLabel("合盖保持运行", font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
        let body = makeLabel("开启后，MacBook 合盖也不会进入睡眠，Wi-Fi 可保持连接。关闭后恢复系统正常睡眠。", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        body.lineBreakMode = .byWordWrapping
        body.maximumNumberOfLines = 2

        modeSwitch.translatesAutoresizingMaskIntoConstraints = false
        modeSwitch.target = self
        modeSwitch.action = #selector(toggleMode)

        card.addSubview(icon)
        card.addSubview(title)
        card.addSubview(body)
        card.addSubview(modeSwitch)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            title.trailingAnchor.constraint(lessThanOrEqualTo: modeSwitch.leadingAnchor, constant: -14),

            body.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -90),
            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),

            modeSwitch.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            modeSwitch.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])

        return card
    }

    private func makeHelperCard() -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 112).isActive = true

        let icon = SymbolTile(symbol: "lock.open.fill", fill: NSColor.systemOrange.withAlphaComponent(0.16), tint: .systemOrange)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = makeLabel("免密助手", font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
        helperDetail.translatesAutoresizingMaskIntoConstraints = false
        helperDetail.font = .systemFont(ofSize: 12)
        helperDetail.textColor = .secondaryLabelColor
        helperDetail.lineBreakMode = .byWordWrapping
        helperDetail.maximumNumberOfLines = 2

        helperBadge.translatesAutoresizingMaskIntoConstraints = false
        installButton.translatesAutoresizingMaskIntoConstraints = false
        installButton.bezelStyle = .rounded
        installButton.font = .systemFont(ofSize: 12, weight: .semibold)
        installButton.target = self
        installButton.action = #selector(installHelper)

        card.addSubview(icon)
        card.addSubview(title)
        card.addSubview(helperDetail)
        card.addSubview(helperBadge)
        card.addSubview(installButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            title.trailingAnchor.constraint(lessThanOrEqualTo: helperBadge.leadingAnchor, constant: -12),

            helperDetail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            helperDetail.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            helperDetail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),

            helperBadge.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            helperBadge.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            helperBadge.heightAnchor.constraint(equalToConstant: 28),
            helperBadge.widthAnchor.constraint(equalToConstant: 92),

            installButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            installButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            installButton.widthAnchor.constraint(equalToConstant: 142),
            installButton.heightAnchor.constraint(equalToConstant: 30),
        ])

        return card
    }

    private func makeWarningCard() -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 76).isActive = true

        let icon = SymbolTile(symbol: "exclamationmark.triangle.fill", fill: NSColor.systemYellow.withAlphaComponent(0.18), tint: .systemYellow)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = makeLabel("安全提示", font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
        let body = makeLabel("开启后合盖仍在运行。不要把 MacBook 放进包里，保持通风，避免发热和耗电。", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        body.lineBreakMode = .byWordWrapping
        body.maximumNumberOfLines = 2

        card.addSubview(icon)
        card.addSubview(title)
        card.addSubview(body)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),

            body.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
        ])

        return card
    }

    @objc private func refreshFromButton() {
        refreshStatus()
    }

    @objc private func toggleMode() {
        if suppressSwitchAction || isApplyingMode { return }
        let targetEnabled = modeSwitch.isOn
        setModeUI(enabled: targetEnabled)
        runModeAction(targetEnabled ? "enable" : "disable", optimisticEnabled: targetEnabled)
    }

    @objc private func installHelper() {
        guard let installer = Bundle.main.path(forResource: "install-helper", ofType: "sh") else {
            apply(.error("安装脚本缺失"))
            return
        }

        apply(.working("正在安装免密助手..."))
        DispatchQueue.global(qos: .userInitiated).async {
            let command = "\(shellQuote(installer)) \(shellQuote(NSUserName()))"
            let appleScript = "do shell script \(appleScriptLiteral(command)) with administrator privileges"
            let result = runCommand("/usr/bin/osascript", ["-e", appleScript])
            DispatchQueue.main.async {
                if result.code == 0 {
                    self.refreshStatus()
                } else {
                    self.apply(.error(cleanMessage(result.stderr, fallback: result.stdout)))
                }
            }
        }
    }

    private func refreshStatus() {
        apply(.working("正在检查状态..."))
        DispatchQueue.global(qos: .userInitiated).async {
            let helper = runCommand("/usr/bin/sudo", ["-n", helperPath, "status"])
            let fallbackMode = readCurrentModeWithoutHelper()
            DispatchQueue.main.async {
                if helper.code == 0 {
                    self.apply(.ready(mode: normalizedMode(helper.stdout)))
                } else {
                    self.apply(.setupRequired(currentMode: fallbackMode))
                }
            }
        }
    }

    private func runHelperAction(_ action: String, workingText: String) {
        apply(.working(workingText))
        DispatchQueue.global(qos: .userInitiated).async {
            let result = runCommand("/usr/bin/sudo", ["-n", helperPath, action])
            DispatchQueue.main.async {
                if result.code == 0 {
                    self.refreshStatus()
                } else {
                    self.apply(.error(cleanMessage(result.stderr, fallback: result.stdout)))
                }
            }
        }
    }

    private func runModeAction(_ action: String, optimisticEnabled: Bool) {
        isApplyingMode = true
        modeSwitch.isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = runCommand("/usr/bin/sudo", ["-n", helperPath, action])
            DispatchQueue.main.async {
                self.isApplyingMode = false
                self.modeSwitch.isBusy = false
                if result.code == 0 {
                    self.setModeUI(enabled: optimisticEnabled)
                } else {
                    self.suppressSwitchAction = true
                    self.modeSwitch.isOn = !optimisticEnabled
                    self.suppressSwitchAction = false
                    self.setModeUI(enabled: !optimisticEnabled)
                    self.apply(.error(cleanMessage(result.stderr, fallback: result.stdout)))
                }
            }
        }
    }

    private func apply(_ state: HelperState) {
        switch state {
        case .working(let text):
            progress.startAnimation(nil)
            statusTitle.stringValue = "处理中"
            statusDetail.stringValue = text
            statusBadge.configure(text: "处理中", fill: NSColor.systemBlue.withAlphaComponent(0.12), textColor: .systemBlue)
            helperBadge.configure(text: "检查中", fill: NSColor.systemBlue.withAlphaComponent(0.10), textColor: .systemBlue)
            helperDetail.stringValue = "正在读取或更新系统电源设置。"
            updateToolbarMode(nil)
            setControls(enabled: false, helperInstalled: false)

        case .ready(let mode):
            progress.stopAnimation(nil)
            let enabled = mode == "enabled"
            suppressSwitchAction = true
            modeSwitch.isOn = enabled
            suppressSwitchAction = false
            setFixedStatusText()
            setModeUI(enabled: enabled)
            helperBadge.configure(text: "已安装", fill: NSColor.systemGreen.withAlphaComponent(0.14), textColor: .systemGreen)
            helperDetail.stringValue = "已安装受限 sudoers 规则。日常点击开关不再需要输入管理员密码。"
            setControls(enabled: true, helperInstalled: true)

        case .setupRequired(let currentMode):
            progress.stopAnimation(nil)
            let enabled = currentMode == "enabled"
            suppressSwitchAction = true
            modeSwitch.isOn = enabled
            suppressSwitchAction = false
            setFixedStatusText()
            setModeUI(enabled: enabled)
            statusBadge.configure(text: "需安装", fill: NSColor.systemOrange.withAlphaComponent(0.16), textColor: .systemOrange)
            helperBadge.configure(text: "未安装", fill: NSColor.systemOrange.withAlphaComponent(0.16), textColor: .systemOrange)
            helperDetail.stringValue = "第一次安装需要管理员密码。之后本 App 只允许执行 status、enable、disable 三个固定动作。"
            setControls(enabled: false, helperInstalled: false)

        case .error(let message):
            progress.stopAnimation(nil)
            statusTitle.stringValue = "操作失败"
            statusDetail.stringValue = message.isEmpty ? "请重新打开 App 再试一次。" : message
            statusBadge.configure(text: "错误", fill: NSColor.systemRed.withAlphaComponent(0.13), textColor: .systemRed)
            helperBadge.configure(text: "未知", fill: NSColor.systemRed.withAlphaComponent(0.13), textColor: .systemRed)
            helperDetail.stringValue = "状态无法确认。"
            updateToolbarMode(nil)
            setControls(enabled: false, helperInstalled: false)
        }
    }

    private func setFixedStatusText() {
        statusTitle.stringValue = "合盖保持运行"
        statusDetail.stringValue = "MacBook 合盖后仍保持运行，Wi-Fi 可继续连接。"
    }

    private func setModeUI(enabled: Bool) {
        statusBadge.configure(
            text: enabled ? "已开启" : "已关闭",
            fill: enabled ? NSColor.systemGreen.withAlphaComponent(0.14) : NSColor.systemGray.withAlphaComponent(0.14),
            textColor: enabled ? .systemGreen : .secondaryLabelColor
        )
        updateToolbarMode(enabled)
    }

    private func updateToolbarMode(_ enabled: Bool?) {
        let target: ToolbarItem
        if let enabled {
            keepAwakeToolbarItem.configure(active: enabled, accent: .systemYellow)
            sleepToolbarItem.configure(active: !enabled, accent: .systemPurple)
            target = enabled ? keepAwakeToolbarItem : sleepToolbarItem
            toolbarPointer.isHidden = false
        } else {
            keepAwakeToolbarItem.configure(active: false, accent: .systemYellow)
            sleepToolbarItem.configure(active: false, accent: .systemPurple)
            target = keepAwakeToolbarItem
            toolbarPointer.isHidden = true
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            toolbarPointerCenterConstraint?.isActive = false
            toolbarPointerCenterConstraint = toolbarPointer.centerXAnchor.constraint(equalTo: target.centerXAnchor)
            toolbarPointerCenterConstraint?.isActive = true
            view.layoutSubtreeIfNeeded()
        }
    }

    private func setControls(enabled: Bool, helperInstalled: Bool) {
        modeSwitch.isEnabled = enabled
        installButton.isHidden = helperInstalled
        installButton.isEnabled = !helperInstalled
        refreshButton.isEnabled = true
    }
}

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
