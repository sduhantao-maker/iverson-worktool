import Cocoa

final class KeepGoingViewController: NSViewController {
    private static let batteryChoices = [10, 15, 20, 30, 40]

    private let power: PowerControlling
    private let settingsStore: KeepGoingStore
    private var autoOff: KeepGoingAutoOffSettings
    private var lastStatus: PowerStatus?
    private var isApplyingMode = false
    private var refreshStartedAt: Date?
    private var didArmExistingSession = false

    // Toolbar: two choices with a glass bubble that slides between them.
    private let keepAwakeItem = ToolbarItem(title: "保持运行", symbol: "bolt.fill", accent: .systemYellow)
    private let sleepItem = ToolbarItem(title: "正常睡眠", symbol: "moon.zzz.fill", accent: .systemPurple)
    private let toolbarBubble = GooeyIndicator(axis: .horizontal)
    private let toolbarPointer = TriangleView()
    private var toolbarPointerCenterConstraint: NSLayoutConstraint?
    private var toolbarMode: PowerMode?
    private let refreshButton = GlassButton(icon: "arrow.clockwise", toolTip: "刷新状态")

    private let statusBadge = BadgeView()
    private let statusTitle = NSTextField(labelWithString: "正在检查")
    private let statusDetail = NSTextField(labelWithString: "正在读取电脑的睡眠状态。")
    private let progress = NSProgressIndicator()

    private let modeSwitch = ToggleSwitch()
    private let deadlineSwitch = ToggleSwitch(size: .small)
    private let deadlinePicker = NSDatePicker()
    private let batterySwitch = ToggleSwitch(size: .small)
    private let batteryPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private let helperBadge = BadgeView()
    private let helperDetail = NSTextField(labelWithString: " ")
    private let installButton = GlassButton(title: "安装免密助手…", symbol: "lock.open.fill", style: .primary, busyStyle: .ring)

    init(power: PowerControlling? = nil, store: KeepGoingStore = KeepGoingStore()) {
        settingsStore = store
        self.power = power ?? HelperPowerControl(store: store)
        autoOff = store.loadAutoOff()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let root = FillView(color: Palette.windowBackground)
        root.frame = NSRect(x: 0, y: 0, width: 800, height: 590)
        view = root
        buildUI(in: root)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyAutoOffToUI()
        showWorking("正在读取电脑的睡眠状态。")
        refreshStatus()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Keeps the bubble on its item after layout passes. Same target: no jump.
        if let toolbarMode {
            let item = toolbarMode == .keepAwake ? keepAwakeItem : sleepItem
            toolbarBubble.move(to: item.iconFrame(in: toolbarBubble), tint: item.accent, animated: true)
        }
    }

    // MARK: Layout

    private func buildUI(in root: NSView) {
        let toolbar = ToolbarBackgroundView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let content = FillView(color: Palette.contentBackground)
        content.translatesAutoresizingMaskIntoConstraints = false

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
        toolbarBubble.translatesAutoresizingMaskIntoConstraints = false
        toolbarBubble.tintAlpha = 0.20
        toolbar.addSubview(toolbarBubble)

        keepAwakeItem.toolTip = "开启保持运行"
        sleepItem.toolTip = "恢复正常睡眠"
        keepAwakeItem.onSelect = { [weak self] in self?.requestMode(.keepAwake) }
        sleepItem.onSelect = { [weak self] in self?.requestMode(.normal) }

        let stack = NSStackView(views: [keepAwakeItem, sleepItem])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 96
        stack.alignment = .centerY
        toolbar.addSubview(stack)

        toolbarPointer.translatesAutoresizingMaskIntoConstraints = false
        toolbarPointer.isHidden = true
        toolbar.addSubview(toolbarPointer)

        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.target = self
        refreshButton.action = #selector(refreshFromButton)
        toolbar.addSubview(refreshButton)

        NSLayoutConstraint.activate([
            toolbarBubble.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            toolbarBubble.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            toolbarBubble.topAnchor.constraint(equalTo: toolbar.topAnchor),
            toolbarBubble.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),

            stack.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            stack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 28),

            toolbarPointer.widthAnchor.constraint(equalToConstant: 22),
            toolbarPointer.heightAnchor.constraint(equalToConstant: 12),
            toolbarPointer.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),

            refreshButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -18),
            refreshButton.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 22),
            refreshButton.widthAnchor.constraint(equalToConstant: 30),
            refreshButton.heightAnchor.constraint(equalToConstant: 30),
        ])

        toolbarPointerCenterConstraint = toolbarPointer.centerXAnchor.constraint(equalTo: keepAwakeItem.centerXAnchor)
        toolbarPointerCenterConstraint?.isActive = true
    }

    private func buildContent(in content: NSView) {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        content.addSubview(stack)

        let cards = [makeStatusCard(), makeModeCard(), makeHelperCard(), makeWarningCard()]
        cards.forEach(stack.addArrangedSubview)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
        ] + cards.map { $0.widthAnchor.constraint(equalTo: stack.widthAnchor) })
    }

    private func makeStatusCard() -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 82).isActive = true

        let icon = SymbolTile(symbol: "laptopcomputer", fill: NSColor.systemBlue.withAlphaComponent(0.13), tint: .systemBlue)
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

        [icon, statusTitle, statusDetail, statusBadge, progress].forEach(card.addSubview)

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
            statusDetail.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -128),

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
        card.heightAnchor.constraint(equalToConstant: 128).isActive = true

        let icon = SymbolTile(symbol: "power", fill: NSColor.systemRed.withAlphaComponent(0.13), tint: .systemRed)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = makeLabel("合盖保持运行", font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
        let body = makeLabel(
            "开启后，MacBook 合盖也不睡眠，网络保持连接。关闭后恢复你原来的睡眠设置。",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
        body.lineBreakMode = .byWordWrapping
        body.maximumNumberOfLines = 2

        modeSwitch.translatesAutoresizingMaskIntoConstraints = false
        modeSwitch.target = self
        modeSwitch.action = #selector(toggleMode)
        modeSwitch.setAccessibilityLabel("合盖保持运行")

        let autoOffRow = makeAutoOffRow()

        [icon, title, body, modeSwitch, autoOffRow].forEach(card.addSubview)

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
            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),

            modeSwitch.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            modeSwitch.centerYAnchor.constraint(equalTo: card.topAnchor, constant: 34),

            autoOffRow.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            autoOffRow.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])

        return card
    }

    private func makeAutoOffRow() -> NSView {
        let labelFont = NSFont.systemFont(ofSize: 12)
        let labelColor = NSColor.secondaryLabelColor

        deadlineSwitch.translatesAutoresizingMaskIntoConstraints = false
        deadlineSwitch.target = self
        deadlineSwitch.action = #selector(autoOffChanged)
        deadlineSwitch.setAccessibilityLabel("定时自动关闭")

        deadlinePicker.translatesAutoresizingMaskIntoConstraints = false
        deadlinePicker.datePickerStyle = .textFieldAndStepper
        deadlinePicker.datePickerElements = .hourMinute
        deadlinePicker.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        deadlinePicker.target = self
        deadlinePicker.action = #selector(autoOffChanged)

        batterySwitch.translatesAutoresizingMaskIntoConstraints = false
        batterySwitch.target = self
        batterySwitch.action = #selector(autoOffChanged)
        batterySwitch.setAccessibilityLabel("低电量自动关闭")

        batteryPopup.translatesAutoresizingMaskIntoConstraints = false
        batteryPopup.controlSize = .small
        batteryPopup.font = .systemFont(ofSize: 12)
        batteryPopup.addItems(withTitles: Self.batteryChoices.map { "\($0)%" })
        batteryPopup.target = self
        batteryPopup.action = #selector(autoOffChanged)

        let row = NSStackView(views: [
            deadlineSwitch,
            makeLabel("到", font: labelFont, color: labelColor),
            deadlinePicker,
            makeLabel("自动关闭", font: labelFont, color: labelColor),
            batterySwitch,
            makeLabel("电量低于", font: labelFont, color: labelColor),
            batteryPopup,
            makeLabel("时关闭", font: labelFont, color: labelColor),
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.setCustomSpacing(10, after: deadlineSwitch)
        row.setCustomSpacing(30, after: row.arrangedSubviews[3])
        row.setCustomSpacing(10, after: batterySwitch)
        return row
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
        installButton.target = self
        installButton.action = #selector(installHelper)

        [icon, title, helperDetail, helperBadge, installButton].forEach(card.addSubview)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            title.trailingAnchor.constraint(lessThanOrEqualTo: helperBadge.leadingAnchor, constant: -12),

            helperDetail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            helperDetail.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -128),
            helperDetail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),

            helperBadge.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            helperBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            helperBadge.heightAnchor.constraint(equalToConstant: 28),
            helperBadge.widthAnchor.constraint(equalToConstant: 92),

            installButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            installButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            installButton.widthAnchor.constraint(equalToConstant: 146),
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
        let body = makeLabel(
            "开启后合盖仍在运行。不要把 MacBook 放进包里，保持通风。建议保留定时关闭和低电量关闭。",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
        body.lineBreakMode = .byWordWrapping
        body.maximumNumberOfLines = 2

        [icon, title, body].forEach(card.addSubview)

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

    // MARK: Actions

    @objc private func refreshFromButton() {
        refreshStatus()
    }

    @objc private func toggleMode() {
        requestMode(modeSwitch.isOn ? .keepAwake : .normal)
    }

    @objc private func autoOffChanged() {
        let time = Calendar.current.dateComponents([.hour, .minute], from: deadlinePicker.dateValue)
        let index = max(0, batteryPopup.indexOfSelectedItem)
        autoOff = KeepGoingAutoOffSettings(
            deadlineEnabled: deadlineSwitch.isOn,
            deadlineHour: time.hour ?? 8,
            deadlineMinute: time.minute ?? 0,
            batteryFloorEnabled: batterySwitch.isOn,
            batteryFloorPercent: Self.batteryChoices[min(index, Self.batteryChoices.count - 1)]
        )
        deadlinePicker.isEnabled = deadlineSwitch.isOn
        batteryPopup.isEnabled = batterySwitch.isOn
        try? settingsStore.saveAutoOff(autoOff)

        // While KeepGoing is on, the new rules replace the running guard.
        guard lastStatus?.mode == .keepAwake else { return }
        let settings = autoOff
        let power = self.power
        DispatchQueue.global(qos: .userInitiated).async {
            let error = power.armAutoOff(settings)
            let state = power.autoOffState()
            DispatchQueue.main.async {
                self.statusDetail.stringValue = error ?? self.detailText(on: true, guardState: state)
            }
        }
    }

    @objc private func installHelper() {
        installButton.setBusy(true)
        setInteractive(false)
        let power = self.power
        DispatchQueue.global(qos: .userInitiated).async {
            let result = power.installHelper()
            DispatchQueue.main.async {
                let ok = result.code == 0
                self.installButton.finish(success: ok)
                if !ok {
                    self.showError(cleanMessage(result.stderr, fallback: result.stdout))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + (ok ? 1.3 : 0)) {
                    self.refreshStatus()
                }
            }
        }
    }

    private func requestMode(_ mode: PowerMode) {
        guard !isApplyingMode, let status = lastStatus, status.helper != .missing else {
            modeSwitch.isOn = lastStatus?.mode == .keepAwake
            return
        }
        guard mode != status.mode else {
            modeSwitch.isOn = mode == .keepAwake
            return
        }

        isApplyingMode = true
        modeSwitch.isOn = mode == .keepAwake
        modeSwitch.isBusy = true
        setToolbarMode(mode, animated: true)
        setInteractive(false)
        showWorking(mode == .keepAwake ? "正在开启保持运行…" : "正在恢复正常睡眠…")

        let power = self.power
        let settings = autoOff
        DispatchQueue.global(qos: .userInitiated).async {
            let result = power.setMode(mode)
            var guardError: String?
            if result.code == 0 {
                if mode == .keepAwake {
                    guardError = power.armAutoOff(settings)
                } else {
                    power.disarmAutoOff()
                }
            }
            DispatchQueue.main.async {
                self.isApplyingMode = false
                self.modeSwitch.isBusy = false
                if result.code == 0 {
                    self.refreshStatus(note: guardError)
                } else {
                    self.modeSwitch.isOn = status.mode == .keepAwake
                    self.setToolbarMode(status.mode, animated: true)
                    self.setInteractive(true)
                    self.showError(cleanMessage(result.stderr, fallback: result.stdout))
                }
            }
        }
    }

    private func refreshStatus(note: String? = nil) {
        refreshStartedAt = Date()
        refreshButton.isSpinningIcon = true
        progress.startAnimation(nil)
        let power = self.power
        DispatchQueue.global(qos: .userInitiated).async {
            let status = power.readStatus()
            let guardState = power.autoOffState()
            DispatchQueue.main.async {
                // Let the refresh symbol turn at least once, so the click visibly did something.
                let elapsed = Date().timeIntervalSince(self.refreshStartedAt ?? Date())
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.6 - elapsed)) {
                    self.refreshButton.isSpinningIcon = false
                }
                self.progress.stopAnimation(nil)
                self.apply(status: status, guardState: guardState, note: note)
            }
        }
    }

    // MARK: State → UI

    private func apply(status: PowerStatus, guardState: KeepGoingGuardState?, note: String?) {
        let firstStatus = lastStatus == nil
        lastStatus = status
        let on = status.mode == .keepAwake

        modeSwitch.setOn(on, animated: !firstStatus)
        setToolbarMode(status.mode, animated: !firstStatus)

        statusTitle.stringValue = on ? "保持运行中" : "正常睡眠"
        statusDetail.stringValue = note ?? detailText(on: on, guardState: guardState)
        statusBadge.configure(
            text: on ? "已开启" : "已关闭",
            fill: on ? NSColor.systemGreen.withAlphaComponent(0.14) : NSColor.systemGray.withAlphaComponent(0.14),
            textColor: on ? .systemGreen : .secondaryLabelColor
        )

        switch status.helper {
        case .missing:
            helperBadge.configure(text: "未安装", fill: NSColor.systemOrange.withAlphaComponent(0.16), textColor: .systemOrange)
            helperDetail.stringValue = "第一次安装需要管理员密码。之后本 App 只能执行 status、enable、disable 三个固定动作。"
            installButton.setTitle("安装免密助手…")
            installButton.isHidden = false
            statusBadge.configure(text: "需安装", fill: NSColor.systemOrange.withAlphaComponent(0.16), textColor: .systemOrange)
        case .outdated:
            helperBadge.configure(text: "需更新", fill: NSColor.systemOrange.withAlphaComponent(0.16), textColor: .systemOrange)
            helperDetail.stringValue = "已装的助手是旧版：关闭时不会恢复你原来的睡眠设置。点“更新”重装一次（需要管理员密码）。"
            installButton.setTitle("更新免密助手…")
            installButton.isHidden = false
        case .current:
            helperBadge.configure(text: "已安装", fill: NSColor.systemGreen.withAlphaComponent(0.14), textColor: .systemGreen)
            helperDetail.stringValue = "已安装受限 sudoers 规则。日常切换不需要输入管理员密码。"
            installButton.isHidden = true
        }
        setInteractive(status.helper != .missing)

        if on, guardState == nil, status.helper != .missing, !didArmExistingSession,
           KeepGoingGuard.makeState(from: autoOff, now: Date()) != nil {
            didArmExistingSession = true
            let settings = autoOff
            let power = self.power
            DispatchQueue.global(qos: .userInitiated).async {
                let error = power.armAutoOff(settings)
                let state = power.autoOffState()
                DispatchQueue.main.async {
                    self.statusDetail.stringValue = error ?? self.detailText(on: true, guardState: state)
                }
            }
        }
    }

    func detailText(on: Bool, guardState: KeepGoingGuardState?) -> String {
        guard on else {
            return "合盖后正常睡眠。开启后，合盖也会继续运行，网络保持连接。"
        }
        var rules: [String] = []
        if let deadline = guardState?.deadline {
            rules.append("将于 \(KeepGoingGuard.timeText(deadline)) 自动关闭")
        }
        if let floor = guardState?.batteryFloorPercent {
            rules.append("用电池且电量不高于 \(floor)% 时关闭")
        }
        guard !rules.isEmpty else {
            return "没有设置自动关闭，用完记得手动关掉。"
        }
        return rules.joined(separator: "；") + "。"
    }

    private func applyAutoOffToUI() {
        deadlineSwitch.setOn(autoOff.deadlineEnabled, animated: false)
        batterySwitch.setOn(autoOff.batteryFloorEnabled, animated: false)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = autoOff.deadlineHour
        components.minute = autoOff.deadlineMinute
        deadlinePicker.dateValue = Calendar.current.date(from: components) ?? Date()
        let index = Self.batteryChoices.firstIndex(of: autoOff.batteryFloorPercent) ?? 2
        batteryPopup.selectItem(at: index)
        deadlinePicker.isEnabled = autoOff.deadlineEnabled
        batteryPopup.isEnabled = autoOff.batteryFloorEnabled
    }

    private func setToolbarMode(_ mode: PowerMode, animated: Bool) {
        let changed = mode != toolbarMode
        toolbarMode = mode
        keepAwakeItem.isSelectedItem = mode == .keepAwake
        sleepItem.isSelectedItem = mode == .normal
        toolbarBubble.isHidden = false
        toolbarPointer.isHidden = false

        let item = mode == .keepAwake ? keepAwakeItem : sleepItem
        if changed {
            toolbarPointerCenterConstraint?.isActive = false
            toolbarPointerCenterConstraint = toolbarPointer.centerXAnchor.constraint(equalTo: item.centerXAnchor)
            toolbarPointerCenterConstraint?.isActive = true
        }
        if animated && changed && !Motion.isReduced {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.34
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.4, 0.64, 1)
                context.allowsImplicitAnimation = true
                view.layoutSubtreeIfNeeded()
            }
        } else {
            view.layoutSubtreeIfNeeded()
        }
        toolbarBubble.move(to: item.iconFrame(in: toolbarBubble), tint: item.accent, animated: animated)
    }

    private func setInteractive(_ enabled: Bool) {
        modeSwitch.isEnabled = enabled
        keepAwakeItem.isEnabled = enabled
        sleepItem.isEnabled = enabled
        deadlineSwitch.isEnabled = enabled
        batterySwitch.isEnabled = enabled
        deadlinePicker.isEnabled = enabled && autoOff.deadlineEnabled
        batteryPopup.isEnabled = enabled && autoOff.batteryFloorEnabled
        installButton.isEnabled = !isApplyingMode
    }

    private func showWorking(_ text: String) {
        progress.startAnimation(nil)
        statusTitle.stringValue = "处理中"
        statusDetail.stringValue = text
        statusBadge.configure(text: "处理中", fill: NSColor.systemBlue.withAlphaComponent(0.12), textColor: .systemBlue)
    }

    private func showError(_ message: String) {
        progress.stopAnimation(nil)
        statusTitle.stringValue = "操作失败"
        statusDetail.stringValue = message.isEmpty ? "请重新打开 App 再试一次。" : message
        statusBadge.configure(text: "错误", fill: NSColor.systemRed.withAlphaComponent(0.13), textColor: .systemRed)
    }
}
