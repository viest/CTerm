import AppKit

class SettingsShortcutsTab: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private var tableView: NSTableView!
    private let cellHorizontalInset: CGFloat = 10

    private struct ShortcutEntry {
        let action: String
        let defaultShortcut: String
        var currentShortcut: String
    }

    private var entries: [ShortcutEntry] = []
    private var settings: SettingsManager { SettingsManager.shared }

    override init(frame: NSRect) {
        super.init(frame: frame)
        loadEntries()
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func loadEntries() {
        let defaults: [(String, String)] = [
            ("Split Right", "\u{2318}D"),
            ("Split Down", "\u{21E7}\u{2318}D"),
            ("Close Pane/Tab", "\u{2318}W"),
            ("New Terminal Tab", "\u{2318}T"),
            ("New Workspace", "\u{2318}N"),
            ("Equalize Panes", "\u{21E7}\u{2318}0"),
            ("Next Pane", "\u{21E7}\u{2318}\u{2192}"),
            ("Previous Pane", "\u{21E7}\u{2318}\u{2190}"),
            ("Clear Screen", "\u{2318}K"),
            ("Find", "\u{2318}F"),
            ("Scroll to Bottom", "\u{21E7}\u{2318}\u{2193}"),
            ("Run Scripts", "\u{2318}G"),
            ("Toggle Sidebar", "\u{2318}B"),
            ("Settings", "\u{2318},"),
        ]

        let customShortcuts = settings.settings.shortcuts
        entries = defaults.map { action, def in
            ShortcutEntry(action: action, defaultShortcut: def,
                         currentShortcut: customShortcuts[action] ?? def)
        }
    }

    private func setupUI() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        tableView = NSTableView()
        tableView.backgroundColor = .clear
        tableView.rowHeight = 30
        tableView.gridStyleMask = []
        tableView.intercellSpacing = NSSize(width: 0, height: 0)

        let actionCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionCol.title = "Action"
        actionCol.width = 240
        tableView.addTableColumn(actionCol)

        let shortcutCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        shortcutCol.title = "Shortcut"
        shortcutCol.width = 140
        tableView.addTableColumn(shortcutCol)

        let defaultCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("default"))
        defaultCol.title = "Default"
        defaultCol.width = 120
        tableView.addTableColumn(defaultCol)

        tableView.dataSource = self
        tableView.delegate = self
        scrollView.documentView = tableView

        // Reset button
        let resetBtn = NSButton(title: "Reset All to Defaults", target: self, action: #selector(resetAll))
        resetBtn.bezelStyle = .recessed
        resetBtn.font = NSFont.systemFont(ofSize: 11)
        resetBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resetBtn)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: resetBtn.topAnchor, constant: -8),

            resetBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            resetBtn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    @objc private func resetAll() {
        settings.settings.shortcuts = [:]
        settings.save()
        loadEntries()
        tableView.reloadData()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let id = tableColumn?.identifier.rawValue ?? ""

        switch id {
        case "action":
            return makeCellLabel(entry.action,
                                 font: NSFont.systemFont(ofSize: 12),
                                 color: AppTheme.textPrimary)

        case "shortcut":
            return makeCellLabel(entry.currentShortcut,
                                 font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                                 color: AppTheme.accent)

        case "default":
            return makeCellLabel(entry.defaultShortcut,
                                 font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                                 color: AppTheme.textSecondary)

        default:
            return nil
        }
    }

    private func makeCellLabel(_ text: String, font: NSFont, color: NSColor) -> NSView {
        let cell = NSView()
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: cellHorizontalInset),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -cellHorizontalInset),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }
}
