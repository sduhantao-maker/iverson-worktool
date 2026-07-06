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

    var isSelectedItem: Bool = false {
        didSet { updateAppearance() }
    }

    init(section: Section, onSelect: @escaping () -> Void) {
        label = makeLabel(section.title, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
        self.onSelect = onSelect
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .systemBlue
        if #available(macOS 11.0, *) {
            imageView.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil)
        }

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

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        onSelect()
    }

    private func updateAppearance() {
        layer?.backgroundColor = isSelectedItem
            ? NSColor.systemBlue.withAlphaComponent(0.12).cgColor
            : NSColor.clear.cgColor
        label.textColor = isSelectedItem ? .labelColor : .secondaryLabelColor
        imageView.contentTintColor = .systemBlue
    }
}

final class RootViewController: NSViewController {
    private let contentHost = NSView()
    private let keepGoingViewController = KeepGoingViewController()
    private let autoMessageController = AutoMessageViewController()
    private var activeContentViewController: NSViewController?
    private var selectedSection: Section = .keepGoing
    private var sidebarButtons: [Section: SidebarItemButton] = [:]

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1010, height: 590))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view = root
        buildUI(in: root)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        select(.keepGoing)
    }

    private func buildUI(in root: NSView) {
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor(calibratedWhite: 0.94, alpha: 1).cgColor

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        contentHost.wantsLayer = true
        contentHost.layer?.backgroundColor = NSColor(calibratedWhite: 0.98, alpha: 1).cgColor

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading

        root.addSubview(sidebar)
        root.addSubview(contentHost)
        sidebar.addSubview(stack)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 210),

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
                self?.select(section)
            }
            sidebarButtons[section] = button
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func select(_ section: Section) {
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
