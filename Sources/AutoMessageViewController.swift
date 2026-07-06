import Cocoa

private final class AutoMessageTargetRowView: NSView {
    private let enabledSwitch = ToggleSwitch()
    private let appLabel = NSTextField(labelWithString: "")
    private let messageField = NSTextField()
    private let originalAppName: String
    private let originalProcessName: String
    private let launchWaitSeconds: Double

    init(target: AutoMessageTarget) {
        originalAppName = target.appName
        originalProcessName = target.processName
        launchWaitSeconds = target.launchWaitSeconds
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 62).isActive = true

        enabledSwitch.translatesAutoresizingMaskIntoConstraints = false
        enabledSwitch.isOn = target.enabled

        appLabel.translatesAutoresizingMaskIntoConstraints = false
        appLabel.stringValue = target.appName
        appLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        appLabel.textColor = .labelColor
        configure(field: messageField, value: target.message, placeholder: "Message")

        addSubview(enabledSwitch)
        addSubview(appLabel)
        addSubview(messageField)

        NSLayoutConstraint.activate([
            enabledSwitch.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            enabledSwitch.centerYAnchor.constraint(equalTo: centerYAnchor),

            appLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 90),
            appLabel.centerYAnchor.constraint(equalTo: enabledSwitch.centerYAnchor),
            appLabel.widthAnchor.constraint(equalToConstant: 128),

            messageField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 232),
            messageField.trailingAnchor.constraint(equalTo: trailingAnchor),
            messageField.centerYAnchor.constraint(equalTo: enabledSwitch.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func target() -> AutoMessageTarget {
        let appName = originalAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        let processName: String
        if originalProcessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            originalProcessName == originalAppName {
            processName = appName
        } else {
            processName = originalProcessName
        }

        return AutoMessageTarget(
            enabled: enabledSwitch.isOn,
            appName: appName,
            processName: processName,
            message: messageField.stringValue,
            launchWaitSeconds: launchWaitSeconds
        )
    }

    private func configure(field: NSTextField, value: String, placeholder: String) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.stringValue = value
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingTail
    }
}

final class AutoMessageViewController: NSViewController {
    private let store = AutoMessageSettingsStore()
    private lazy var runner = AutoMessageRunner(store: store)
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
            applySettingsToUI()
            statusLabel.stringValue = "已加载自动消息配置"
        } catch {
            settings = .defaults
            applySettingsToUI()
            statusLabel.stringValue = "读取配置失败，已使用默认值：\(error.localizedDescription)"
        }
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
        let icon = SymbolTile(
            symbol: "message.fill",
            fill: NSColor.systemBlue.withAlphaComponent(0.18),
            tint: .systemBlue
        )
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = makeLabel(
            "Auto Message",
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: .secondaryLabelColor
        )
        title.alignment = .center

        toolbar.addSubview(icon)
        toolbar.addSubview(title)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            icon.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 28),
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),

            title.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8),
        ])
    }

    private func buildContent(in content: NSView) {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        content.addSubview(stack)

        let scheduleCard = makeScheduleCard()
        let targetsCard = makeTargetsCard()
        let actionsCard = makeActionsCard()

        stack.addArrangedSubview(scheduleCard)
        stack.addArrangedSubview(targetsCard)
        stack.addArrangedSubview(actionsCard)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            scheduleCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            targetsCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actionsCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func makeScheduleCard() -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 82).isActive = true

        let icon = SymbolTile(symbol: "clock.fill", fill: NSColor.systemPurple.withAlphaComponent(0.14), tint: .systemPurple)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = makeLabel("定时发送", font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
        let hourLabel = makeLabel("时", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        let minuteLabel = makeLabel("分", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)

        configureTimeField(hourField)
        configureTimeField(minuteField)

        card.addSubview(icon)
        card.addSubview(title)
        card.addSubview(hourField)
        card.addSubview(hourLabel)
        card.addSubview(minuteField)
        card.addSubview(minuteLabel)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.centerYAnchor.constraint(equalTo: card.centerYAnchor),

            hourField.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 26),
            hourField.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            hourField.widthAnchor.constraint(equalToConstant: 54),

            hourLabel.leadingAnchor.constraint(equalTo: hourField.trailingAnchor, constant: 6),
            hourLabel.centerYAnchor.constraint(equalTo: hourField.centerYAnchor),

            minuteField.leadingAnchor.constraint(equalTo: hourLabel.trailingAnchor, constant: 20),
            minuteField.centerYAnchor.constraint(equalTo: hourField.centerYAnchor),
            minuteField.widthAnchor.constraint(equalToConstant: 54),

            minuteLabel.leadingAnchor.constraint(equalTo: minuteField.trailingAnchor, constant: 6),
            minuteLabel.centerYAnchor.constraint(equalTo: minuteField.centerYAnchor),
        ])

        return card
    }

    private func makeTargetsCard() -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 230).isActive = true

        let icon = SymbolTile(symbol: "bubble.left.and.bubble.right.fill", fill: NSColor.systemBlue.withAlphaComponent(0.13), tint: .systemBlue)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = makeLabel("目标与消息", font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
        let headerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let headerColor = NSColor.controlTextColor.withAlphaComponent(0.76)
        let enabledHeader = makeLabel("启用", font: headerFont, color: headerColor)
        let appHeader = makeLabel("App", font: headerFont, color: headerColor)
        let messageHeader = makeLabel("Message", font: headerFont, color: headerColor)
        let headerRow = NSView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        targetsStack.translatesAutoresizingMaskIntoConstraints = false
        targetsStack.orientation = .vertical
        targetsStack.spacing = 8
        targetsStack.alignment = .leading

        card.addSubview(icon)
        card.addSubview(title)
        card.addSubview(headerRow)
        headerRow.addSubview(enabledHeader)
        headerRow.addSubview(appHeader)
        headerRow.addSubview(messageHeader)
        card.addSubview(targetsStack)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),

            headerRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            headerRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            headerRow.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            headerRow.heightAnchor.constraint(equalToConstant: 16),

            enabledHeader.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: 2),
            enabledHeader.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),

            appHeader.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: 90),
            appHeader.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),

            messageHeader.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: 232),
            messageHeader.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),

            targetsStack.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            targetsStack.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
            targetsStack.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 8),
        ])

        rebuildRows(with: AutoMessageSettings.defaults.targets)
        return card
    }

    private func makeActionsCard() -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let dryRunLabel = makeLabel("Dry run", font: .systemFont(ofSize: 13), color: .labelColor)
        let submitLabel = makeLabel("Submit after paste", font: .systemFont(ofSize: 13), color: .labelColor)
        let testButton = NSButton(title: "测试发送", target: self, action: #selector(testSend))
        let installButton = NSButton(title: "安装定时任务", target: self, action: #selector(installSchedule))
        let uninstallButton = NSButton(title: "卸载", target: self, action: #selector(uninstallSchedule))

        [testButton, installButton, uninstallButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.bezelStyle = .rounded
            $0.font = .systemFont(ofSize: 12, weight: .semibold)
        }

        dryRunSwitch.translatesAutoresizingMaskIntoConstraints = false
        submitSwitch.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        card.addSubview(dryRunLabel)
        card.addSubview(dryRunSwitch)
        card.addSubview(submitLabel)
        card.addSubview(submitSwitch)
        card.addSubview(testButton)
        card.addSubview(installButton)
        card.addSubview(uninstallButton)
        card.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            dryRunLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            dryRunLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),

            dryRunSwitch.leadingAnchor.constraint(equalTo: dryRunLabel.trailingAnchor, constant: 12),
            dryRunSwitch.centerYAnchor.constraint(equalTo: dryRunLabel.centerYAnchor),

            submitLabel.leadingAnchor.constraint(equalTo: dryRunSwitch.trailingAnchor, constant: 28),
            submitLabel.centerYAnchor.constraint(equalTo: dryRunLabel.centerYAnchor),

            submitSwitch.leadingAnchor.constraint(equalTo: submitLabel.trailingAnchor, constant: 12),
            submitSwitch.centerYAnchor.constraint(equalTo: dryRunLabel.centerYAnchor),

            testButton.leadingAnchor.constraint(equalTo: dryRunLabel.leadingAnchor),
            testButton.topAnchor.constraint(equalTo: dryRunLabel.bottomAnchor, constant: 22),
            testButton.widthAnchor.constraint(equalToConstant: 88),
            testButton.heightAnchor.constraint(equalToConstant: 30),

            installButton.leadingAnchor.constraint(equalTo: testButton.trailingAnchor, constant: 10),
            installButton.centerYAnchor.constraint(equalTo: testButton.centerYAnchor),
            installButton.widthAnchor.constraint(equalToConstant: 112),
            installButton.heightAnchor.constraint(equalToConstant: 30),

            uninstallButton.leadingAnchor.constraint(equalTo: installButton.trailingAnchor, constant: 10),
            uninstallButton.centerYAnchor.constraint(equalTo: testButton.centerYAnchor),
            uninstallButton.widthAnchor.constraint(equalToConstant: 64),
            uninstallButton.heightAnchor.constraint(equalToConstant: 30),

            statusLabel.leadingAnchor.constraint(equalTo: uninstallButton.trailingAnchor, constant: 14),
            statusLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            statusLabel.centerYAnchor.constraint(equalTo: testButton.centerYAnchor),
        ])

        return card
    }

    private func configureTimeField(_ field: NSTextField) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    }

    private func applySettingsToUI() {
        hourField.stringValue = "\(settings.hour)"
        minuteField.stringValue = "\(settings.minute)"
        dryRunSwitch.isOn = settings.dryRun
        submitSwitch.isOn = settings.submitAfterPaste
        rebuildRows(with: settings.targets)
    }

    private func rebuildRows(with targets: [AutoMessageTarget]) {
        for row in targetRows {
            targetsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }

        targetRows = targets.map { AutoMessageTargetRowView(target: $0) }
        for row in targetRows {
            targetsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: targetsStack.widthAnchor).isActive = true
        }
    }

    private func readSettingsFromUI() throws -> AutoMessageSettings {
        guard let hour = Int(hourField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), 0...23 ~= hour else {
            throw NSError(domain: "AutoMessage", code: 1, userInfo: [NSLocalizedDescriptionKey: "小时必须是 0-23"])
        }

        guard let minute = Int(minuteField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), 0...59 ~= minute else {
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

    @objc private func testSend() {
        do {
            let newSettings = try readSettingsFromUI()
            try store.save(newSettings)
            settings = newSettings
            let result = runner.run(settings: newSettings)
            statusLabel.stringValue = result.message
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func installSchedule() {
        do {
            let newSettings = try readSettingsFromUI()
            settings = newSettings
            let helperPath = Bundle.main.resourcePath.map { "\($0)/keepgoing-automessage" } ?? ""
            guard FileManager.default.isExecutableFile(atPath: helperPath) else {
                statusLabel.stringValue = "定时助手尚未打包，请先重新构建包含 keepgoing-automessage 的应用。"
                return
            }
            let result = runner.installLaunchAgent(helperPath: helperPath, settings: newSettings)
            statusLabel.stringValue = result.message
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func uninstallSchedule() {
        let result = runner.uninstallLaunchAgent()
        statusLabel.stringValue = result.message
    }
}
