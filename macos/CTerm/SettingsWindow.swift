import AppKit

final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private weak var parentWindow: NSWindow?
    private weak var agentsTab: SettingsAgentsTab?
    private var tabButtons: [NSButton] = []
    private var tabViews: [NSView] = []
    private var selectedIndex = 0

    var onPresetsChanged: (([AgentPresetItem]) -> Void)? {
        didSet {
            agentsTab?.onPresetsChanged = onPresetsChanged
        }
    }

    override init() {
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "Settings"
        window.center()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.backgroundColor = AppTheme.bgPrimary
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.delegate = self

        setupUI()
    }

    func present(attachedTo parentWindow: NSWindow?) {
        if self.parentWindow !== parentWindow {
            detachFromParentWindow()
            if let parentWindow {
                parentWindow.addChildWindow(window, ordered: .above)
            }
            self.parentWindow = parentWindow
        }
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func close() {
        detachFromParentWindow()
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        detachFromParentWindow()
    }

    private func detachFromParentWindow() {
        parentWindow?.removeChildWindow(window)
        parentWindow = nil
    }

    private func setupUI() {
        let contentView = window.contentView!
        contentView.wantsLayer = true

        // Top bar
        let topBar = NSView()
        topBar.wantsLayer = true
        topBar.layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1).cgColor
        topBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(topBar)

        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = AppTheme.border.cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(border)

        // Tab buttons
        let tabStack = NSStackView()
        tabStack.orientation = .horizontal
        tabStack.spacing = 0
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(tabStack)

        let tabNames = ["General", "Agents", "Terminal", "Shortcuts"]
        for (i, name) in tabNames.enumerated() {
            let btn = NSButton()
            btn.title = name
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            btn.contentTintColor = (i == 0) ? AppTheme.textPrimary : AppTheme.textSecondary
            btn.target = self
            btn.action = #selector(tabClicked(_:))
            btn.tag = i
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true
            tabStack.addArrangedSubview(btn)
            tabButtons.append(btn)
        }

        // Content container
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 38),

            border.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            border.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),

            tabStack.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            tabStack.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            container.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // Tab content views
        let generalTab = SettingsGeneralTab()
        let agentsTab = SettingsAgentsTab()
        self.agentsTab = agentsTab
        agentsTab.onPresetsChanged = onPresetsChanged
        let terminalTab = SettingsTerminalTab()
        let shortcutsTab = SettingsShortcutsTab()

        let views: [NSView] = [
            generalTab,
            agentsTab,
            terminalTab,
            shortcutsTab,
        ]
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            view.isHidden = true
            tabViews.append(view)
        }
        tabViews[0].isHidden = false
    }

    @objc private func tabClicked(_ sender: NSButton) {
        let index = sender.tag
        guard index != selectedIndex else { return }
        tabViews[selectedIndex].isHidden = true
        tabViews[index].isHidden = false
        tabButtons[selectedIndex].contentTintColor = AppTheme.textSecondary
        tabButtons[index].contentTintColor = AppTheme.textPrimary
        selectedIndex = index
    }
}
