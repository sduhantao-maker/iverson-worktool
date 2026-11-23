import Cocoa

private enum Section: CaseIterable {
    case keepGoing
    case autoMessage

    var title: String {
        switch self {
        case .keepGoing:
            return "KeepGoing"
        case .autoMessage:
            return "Auto Message"
        }
    }

    var symbol: String {
        switch self {
        case .keepGoing:
            return "bolt.fill"
        case .autoMessage:
            return "message.fill"
        }
    }
}

private final class SidebarItemButton: NSControl {
    private let imageView = NSImageView()
    private let label: NSTextField
    private let onSelect: () -> Void

    var isSelectedItem = false {
        didSet { updateAppearance() }
    }

    init(section: Section, onSelect: @escaping () -> Void) {
        label = makeLabel(section.title, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
        self.onSelect = onSelect
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil)

        addSubview(imageView)
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),

            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(section.title)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        onSelect()
    }

    override func accessibilityPerformPress() -> Bool {
        onSelect()
        return true
    }

    private func updateAppearance() {
        label.textColor = isSelectedItem ? .labelColor : .secondaryLabelColor
        imageView.contentTintColor = .controlAccentColor
        setAccessibilityValue(isSelectedItem ? 1 : 0)
    }
}

final class RootViewController: NSViewController {
    private let contentHost = FillView(color: Palette.windowBackground)
    private let keepGoingViewController: KeepGoingViewController
    private let autoMessageController: AutoMessageViewController
    private var activeContentViewController: NSViewController?
    private var selectedSection: Section = .keepGoing
    private var sidebarButtons: [Section: SidebarItemButton] = [:]
    private let sidebarIndicator = GooeyIndicator(axis: .vertical)
    private var isIndicatorRetryPending = false

    init(
        keepGoing: KeepGoingViewController = KeepGoingViewController(),
        autoMessage: AutoMessageViewController = AutoMessageViewController()
    ) {
        keepGoingViewController = keepGoing
        autoMessageController = autoMessage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let root = FillView(color: Palette.windowBackground)
        root.frame = NSRect(x: 0, y: 0, width: 1010, height: 590)
        view = root
        buildUI(in: root)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        select(.keepGoing, animated: false)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        placeIndicator(animated: false)
    }

    private func buildUI(in root: NSView) {
        // A real sidebar material: translucent, and correct in Light and Dark Mode.
        let sidebar = NSVisualEffectView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .followsWindowActiveState

        contentHost.translatesAutoresizingMaskIntoConstraints = false

        sidebarIndicator.translatesAutoresizingMaskIntoConstraints = false
        sidebarIndicator.cornerRadius = 9
        sidebarIndicator.tintAlpha = 0.14

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading

        root.addSubview(sidebar)
        root.addSubview(contentHost)
        sidebar.addSubview(sidebarIndicator)
        sidebar.addSubview(stack)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 210),

            sidebarIndicator.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sidebarIndicator.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarIndicator.topAnchor.constraint(equalTo: sidebar.topAnchor),
            sidebarIndicator.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),

            contentHost.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: root.topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            contentHost.widthAnchor.constraint(equalToConstant: 800),

            stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 78),
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
        ])

        for section in Section.allCases {
            let button = SidebarItemButton(section: section) { [weak self] in
                self?.select(section, animated: true)
            }
            sidebarButtons[section] = button
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func select(_ section: Section, animated: Bool) {
        selectedSection = section
        for (buttonSection, button) in sidebarButtons {
            button.isSelectedItem = buttonSection == section
        }

        switch section {
        case .keepGoing:
            show(keepGoingViewController)
        case .autoMessage:
            show(autoMessageController)
        }
        placeIndicator(animated: animated)
    }

    private func placeIndicator(animated: Bool) {
        guard let button = sidebarButtons[selectedSection], button.superview != nil else { return }
        let rect = button.convert(button.bounds, to: sidebarIndicator)
        guard rect.width > 0, rect.height > 0 else {
            // The stack view sizes its buttons later in the same layout pass; try once more after it.
            if !isIndicatorRetryPending {
                isIndicatorRetryPending = true
                DispatchQueue.main.async { [weak self] in
                    self?.isIndicatorRetryPending = false
                    self?.placeIndicator(animated: false)
                }
            }
            return
        }
        sidebarIndicator.move(to: rect, tint: .controlAccentColor, animated: animated)
    }

    private func show(_ viewController: NSViewController) {
        guard activeContentViewController !== viewController else { return }

        if let activeContentViewController {
            activeContentViewController.view.removeFromSuperview()
            activeContentViewController.removeFromParent()
        }

        addChild(viewController)
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(viewController.view)
        NSLayoutConstraint.activate([
            viewController.view.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            viewController.view.topAnchor.constraint(equalTo: contentHost.topAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ])
        activeContentViewController = viewController
    }
}
