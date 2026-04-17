import AppKit

private final class SettingsAgentsFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class SettingsAgentsRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }

        let selectionRect = bounds.insetBy(dx: 4, dy: 1)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)
        AppTheme.accent.setFill()
        path.fill()
    }
}

class SettingsAgentsTab: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private var tableView: NSTableView!
    private var detailStack: NSStackView!

    // Detail fields
    private var nameField: NSTextField!
    private var commandField: NSTextField!
    private var promptCommandField: NSTextField!
    private var providerPopup: NSPopUpButton!
    private var autoApplySwitch: NSSwitch!
    private var showInTopBarSwitch: NSSwitch!

    private var presets: [AgentPresetItem] = []
    var onPresetsChanged: (([AgentPresetItem]) -> Void)?

    private let outerInset: CGFloat = 12
    private let detailInset: CGFloat = 16
    private let listWidth: CGFloat = 170
    private let detailWidth: CGFloat = 344

    override init(frame: NSRect) {
        super.init(frame: frame)
        loadPresets()
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func loadPresets() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let path = appSupport.appendingPathComponent("CTerm/presets.json")
        if let data = try? Data(contentsOf: path),
           let decoded = try? JSONDecoder().decode([AgentPresetItem].self, from: data) {
            presets = decoded
        }
    }

    private func savePresets() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let path = appSupport.appendingPathComponent("CTerm/presets.json")
        if let data = try? JSONEncoder().encode(presets) {
            try? data.write(to: path)
        }
        onPresetsChanged?(presets)
    }

    private func setupUI() {
        // Left: agent list
        let listContainer = NSView()
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(listContainer)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(scrollView)

        tableView = NSTableView()
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Agent"
        nameCol.width = 160
        tableView.addTableColumn(nameCol)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 30
        tableView.target = self
        tableView.action = #selector(tableClicked)
        scrollView.documentView = tableView

        // Bottom bar: +, -, Reset
        let bottomBar = NSStackView()
        bottomBar.orientation = .horizontal
        bottomBar.spacing = 4
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(bottomBar)

        let addBtn = makeBarButton("+", action: #selector(addAgent), width: 28)
        let removeBtn = makeBarButton("\u{2212}", action: #selector(removeAgent), width: 28)
        let resetBtn = makeBarButton("Reset", action: #selector(resetDefaults))
        let barSpacer = NSView()
        barSpacer.translatesAutoresizingMaskIntoConstraints = false
        barSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        barSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bottomBar.addArrangedSubview(addBtn)
        bottomBar.addArrangedSubview(removeBtn)
        bottomBar.addArrangedSubview(barSpacer)
        bottomBar.addArrangedSubview(resetBtn)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: listContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -6),

            bottomBar.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 24),
        ])

        // Divider
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = AppTheme.border.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)

        // Right: detail panel
        let detailScroll = NSScrollView()
        detailScroll.hasVerticalScroller = true
        detailScroll.hasHorizontalScroller = false
        detailScroll.drawsBackground = false
        detailScroll.borderType = .noBorder
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detailScroll)

        detailStack = NSStackView()
        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 0
        detailStack.setContentHuggingPriority(.required, for: .vertical)
        detailStack.setContentCompressionResistancePriority(.required, for: .vertical)
        detailStack.translatesAutoresizingMaskIntoConstraints = false

        buildDetailPanel()

        let docView = SettingsAgentsFlippedView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(detailStack)
        detailScroll.documentView = docView

        NSLayoutConstraint.activate([
            listContainer.topAnchor.constraint(equalTo: topAnchor, constant: outerInset),
            listContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: outerInset),
            listContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -outerInset),
            listContainer.widthAnchor.constraint(equalToConstant: listWidth),

            divider.topAnchor.constraint(equalTo: topAnchor, constant: outerInset),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -outerInset),
            divider.leadingAnchor.constraint(equalTo: listContainer.trailingAnchor, constant: 8),
            divider.widthAnchor.constraint(equalToConstant: 1),

            detailScroll.topAnchor.constraint(equalTo: topAnchor, constant: outerInset),
            detailScroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: outerInset),
            detailScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -outerInset),
            detailScroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -outerInset),

            detailStack.topAnchor.constraint(equalTo: docView.topAnchor, constant: outerInset),
            detailStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor, constant: detailInset),
            docView.bottomAnchor.constraint(greaterThanOrEqualTo: detailStack.bottomAnchor, constant: detailInset),
            detailStack.widthAnchor.constraint(equalToConstant: detailWidth),
            docView.widthAnchor.constraint(equalTo: detailScroll.contentView.widthAnchor),
            docView.heightAnchor.constraint(greaterThanOrEqualTo: detailScroll.contentView.heightAnchor),
        ])

        tableView.reloadData()
        if !presets.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateDetail()
    }

    private func buildDetailPanel() {
        let fieldWidth = detailWidth

        nameField = makeField()
        nameField.target = self
        nameField.action = #selector(detailChanged)
        detailStack.addArrangedSubview(makeLabeledField("Name", field: nameField, width: fieldWidth))

        commandField = makeField()
        commandField.placeholderString = "e.g. claude"
        commandField.target = self
        commandField.action = #selector(detailChanged)
        detailStack.addArrangedSubview(makeLabeledField("Command (no prompt)", field: commandField, width: fieldWidth))

        promptCommandField = makeField()
        promptCommandField.placeholderString = "e.g. OpenAI Codex CLI"
        promptCommandField.target = self
        promptCommandField.action = #selector(detailChanged)
        detailStack.addArrangedSubview(makeLabeledField("Description", field: promptCommandField, width: fieldWidth))

        providerPopup = NSPopUpButton()
        providerPopup.font = NSFont.systemFont(ofSize: 12)
        for p in ["anthropic", "openai", "google", "github", "multiple", "custom"] {
            providerPopup.addItem(withTitle: p)
        }
        providerPopup.target = self
        providerPopup.action = #selector(detailChanged)
        providerPopup.translatesAutoresizingMaskIntoConstraints = false
        providerPopup.widthAnchor.constraint(equalToConstant: 160).isActive = true
        detailStack.addArrangedSubview(makeLabeledField("Provider", field: providerPopup, width: fieldWidth))

        autoApplySwitch = NSSwitch()
        autoApplySwitch.controlSize = .small
        autoApplySwitch.target = self
        autoApplySwitch.action = #selector(detailChanged)
        detailStack.addArrangedSubview(makeSwitchRow("Auto-apply on new workspace", sw: autoApplySwitch))

        showInTopBarSwitch = NSSwitch()
        showInTopBarSwitch.controlSize = .small
        showInTopBarSwitch.target = self
        showInTopBarSwitch.action = #selector(detailChanged)
        detailStack.addArrangedSubview(makeSwitchRow("Show in top bar", sw: showInTopBarSwitch))
    }

    private func updateDetail() {
        let row = tableView.selectedRow
        let enabled = row >= 0 && row < presets.count

        nameField.isEnabled = enabled
        commandField.isEnabled = enabled
        promptCommandField.isEnabled = enabled
        providerPopup.isEnabled = enabled
        autoApplySwitch.isEnabled = enabled
        showInTopBarSwitch.isEnabled = enabled

        guard enabled else {
            nameField.stringValue = ""
            commandField.stringValue = ""
            promptCommandField.stringValue = ""
            autoApplySwitch.state = .off
            showInTopBarSwitch.state = .off
            return
        }

        let preset = presets[row]
        nameField.stringValue = preset.name
        commandField.stringValue = preset.command
        promptCommandField.stringValue = preset.description
        providerPopup.selectItem(withTitle: preset.provider)
        autoApplySwitch.state = preset.autoApply ? .on : .off
        showInTopBarSwitch.state = preset.pinned ? .on : .off
    }

    // MARK: - Actions

    @objc private func tableClicked() { updateDetail() }

    @objc private func detailChanged() {
        let row = tableView.selectedRow
        guard row >= 0 && row < presets.count else { return }
        presets[row].name = nameField.stringValue
        presets[row].command = commandField.stringValue
        presets[row].description = promptCommandField.stringValue
        presets[row].provider = providerPopup.selectedItem?.title ?? "custom"
        presets[row].autoApply = autoApplySwitch.state == .on
        presets[row].pinned = showInTopBarSwitch.state == .on
        savePresets()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        updateDetail()
    }

    @objc private func addAgent() {
        presets.append(AgentPresetItem(name: "New Agent", command: "agent", description: "", provider: "custom"))
        savePresets()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: presets.count - 1), byExtendingSelection: false)
        updateDetail()
    }

    @objc private func removeAgent() {
        let row = tableView.selectedRow
        guard row >= 0 && row < presets.count else { return }
        presets.remove(at: row)
        savePresets()
        tableView.reloadData()
        if !presets.isEmpty {
            let nextRow = min(row, presets.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
        }
        updateDetail()
    }

    @objc private func resetDefaults() {
        presets = [
            AgentPresetItem(name: "Claude Code", command: "claude --dangerously-skip-permissions", description: "Anthropic Claude Code", provider: "anthropic", icon: "brain"),
            AgentPresetItem(name: "Codex", command: "codex -c model_reasoning_effort=\"xhigh\" --ask-for-approval never --sandbox danger-full-access -c model_reasoning_summary=\"detailed\" -c model_supports_reasoning_summaries=true", description: "OpenAI Codex CLI", provider: "openai", icon: "sparkles"),
            AgentPresetItem(name: "Gemini CLI", command: "gemini", description: "Google Gemini CLI", provider: "google", icon: "diamond"),
            AgentPresetItem(name: "Aider", command: "aider", description: "AI Pair Programming", provider: "multiple", icon: "wrench"),
            AgentPresetItem(name: "Copilot", command: "gh copilot", description: "GitHub Copilot CLI", provider: "github", icon: "rocket"),
        ]
        savePresets()
        tableView.reloadData()
        if !presets.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateDetail()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { presets.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SettingsAgentsRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSView()
        let label = NSTextField(labelWithString: presets[row].name)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = AppTheme.textPrimary
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    // MARK: - Row builders

    private func makeBarButton(_ title: String, action: Selector, width: CGFloat? = nil) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .recessed
        btn.font = NSFont.systemFont(ofSize: 12)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.setContentCompressionResistancePriority(.required, for: .horizontal)
        if let width {
            btn.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return btn
    }

    private func makeField() -> NSTextField {
        let f = VerticallyCenteredTextField()
        f.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        f.textColor = AppTheme.textPrimary
        return f
    }

    private func makeLabeledField(_ title: String, field: NSView, width: CGFloat) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        label.textColor = AppTheme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false

        let contentField: NSView
        if let textField = field as? NSTextField {
            contentField = makeSettingsTextFieldContainer(for: textField, width: width)
        } else {
            field.translatesAutoresizingMaskIntoConstraints = false
            contentField = field
        }
        contentField.translatesAutoresizingMaskIntoConstraints = false

        let col = NSStackView(views: [label, contentField])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 4
        col.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(col)
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: 48),
            col.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            col.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            col.widthAnchor.constraint(equalToConstant: width),
            col.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
        ])
        wrapper.widthAnchor.constraint(equalToConstant: width).isActive = true
        return wrapper
    }

    private func makeSwitchRow(_ title: String, sw: NSSwitch) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = AppTheme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false

        sw.translatesAutoresizingMaskIntoConstraints = false
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [label, spacer, sw])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(row)
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: 36),
            row.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            row.widthAnchor.constraint(equalToConstant: detailWidth),
            row.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
        ])
        wrapper.widthAnchor.constraint(equalToConstant: detailWidth).isActive = true
        return wrapper
    }
}
