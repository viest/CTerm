import AppKit

class SettingsGeneralTab: NSView {
    private var worktreeDirField: NSTextField!
    private var shellPopup: NSPopUpButton!
    private var editorPopup: NSPopUpButton!

    private var settings: SettingsManager { SettingsManager.shared }
    private let contentWidth: CGFloat = 520
    private let rowHeight: CGFloat = 36

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
        ])

        // — PATHS
        stack.addArrangedSubview(makeSectionHeader("Paths"))

        // Worktree Base Directory
        let dirLabel = NSTextField(labelWithString: "Worktree Base Directory")
        dirLabel.font = NSFont.systemFont(ofSize: 12)
        dirLabel.textColor = AppTheme.textPrimary
        dirLabel.translatesAutoresizingMaskIntoConstraints = false

        worktreeDirField = makeTextField()
        worktreeDirField.stringValue = settings.settings.worktreeBaseDir
        worktreeDirField.target = self
        worktreeDirField.action = #selector(worktreeDirChanged)
        let worktreeDirFieldContainer = makeSettingsTextFieldContainer(for: worktreeDirField)

        let browseBtn = NSButton(title: "Browse…", target: self, action: #selector(browseWorktreeDir))
        browseBtn.bezelStyle = .recessed
        browseBtn.font = NSFont.systemFont(ofSize: 11)
        browseBtn.translatesAutoresizingMaskIntoConstraints = false
        browseBtn.setContentHuggingPriority(.required, for: .horizontal)
        browseBtn.setContentCompressionResistancePriority(.required, for: .horizontal)

        let fieldRow = NSStackView(views: [worktreeDirFieldContainer, browseBtn])
        fieldRow.spacing = 8
        fieldRow.translatesAutoresizingMaskIntoConstraints = false

        let dirGroup = NSStackView(views: [dirLabel, fieldRow])
        dirGroup.orientation = .vertical
        dirGroup.alignment = .leading
        dirGroup.spacing = 6
        dirGroup.translatesAutoresizingMaskIntoConstraints = false

        let dirWrapper = NSView()
        dirWrapper.translatesAutoresizingMaskIntoConstraints = false
        dirWrapper.addSubview(dirGroup)
        NSLayoutConstraint.activate([
            dirWrapper.heightAnchor.constraint(equalToConstant: 56),
            dirGroup.leadingAnchor.constraint(equalTo: dirWrapper.leadingAnchor),
            dirGroup.trailingAnchor.constraint(equalTo: dirWrapper.trailingAnchor),
            dirGroup.centerYAnchor.constraint(equalTo: dirWrapper.centerYAnchor),
            fieldRow.leadingAnchor.constraint(equalTo: dirGroup.leadingAnchor),
            fieldRow.trailingAnchor.constraint(equalTo: dirGroup.trailingAnchor),
        ])
        stack.addArrangedSubview(dirWrapper)
        dirWrapper.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        stack.addArrangedSubview(makeSeparator(in: stack))

        // — DEFAULTS
        stack.addArrangedSubview(makeSectionHeader("Defaults"))

        shellPopup = NSPopUpButton()
        shellPopup.font = NSFont.systemFont(ofSize: 12)
        for s in ["/bin/zsh", "/bin/bash", "/bin/sh", "/usr/local/bin/fish"] {
            shellPopup.addItem(withTitle: s)
        }
        shellPopup.selectItem(withTitle: settings.settings.defaultShell)
        shellPopup.target = self
        shellPopup.action = #selector(shellChanged)
        stack.addArrangedSubview(makeInlineRow("Default Shell", right: shellPopup, popupWidth: 200, in: stack))

        editorPopup = NSPopUpButton()
        editorPopup.font = NSFont.systemFont(ofSize: 12)
        let editors = [
            ("VS Code", "code"), ("Cursor", "cursor"), ("Xcode", "xcode"),
            ("Sublime Text", "subl"), ("JetBrains", "idea"), ("Vim", "vim"),
        ]
        for (name, _) in editors { editorPopup.addItem(withTitle: name) }
        if let idx = editors.firstIndex(where: { $0.1 == settings.settings.defaultEditor }) {
            editorPopup.selectItem(at: idx)
        }
        editorPopup.target = self
        editorPopup.action = #selector(editorChanged)
        stack.addArrangedSubview(makeInlineRow("Default Editor", right: editorPopup, popupWidth: 200, in: stack))

        stack.addArrangedSubview(makeSeparator(in: stack))

        // — BEHAVIOR
        stack.addArrangedSubview(makeSectionHeader("Behavior"))
        stack.addArrangedSubview(makeSwitchRow("Auto-run agent on workspace creation",
                                               isOn: settings.settings.agentAutoRun,
                                               action: #selector(agentAutoRunChanged), in: stack))
        stack.addArrangedSubview(makeSwitchRow("Confirm before quitting",
                                               isOn: settings.settings.confirmOnQuit,
                                               action: #selector(confirmQuitChanged), in: stack))
    }

    // MARK: - Actions

    @objc private func worktreeDirChanged() {
        settings.settings.worktreeBaseDir = worktreeDirField.stringValue
        settings.save()
    }

    @objc private func browseWorktreeDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            worktreeDirField.stringValue = url.path
            settings.settings.worktreeBaseDir = url.path
            settings.save()
        }
    }

    @objc private func shellChanged() {
        settings.settings.defaultShell = shellPopup.selectedItem?.title ?? "/bin/zsh"
        settings.save()
    }

    @objc private func editorChanged() {
        let editorMap = ["VS Code": "code", "Cursor": "cursor", "Xcode": "xcode",
                         "Sublime Text": "subl", "JetBrains": "idea", "Vim": "vim"]
        let selected = editorPopup.selectedItem?.title ?? "VS Code"
        settings.settings.defaultEditor = editorMap[selected] ?? "code"
        settings.save()
    }

    @objc private func agentAutoRunChanged(_ sender: NSSwitch) {
        settings.settings.agentAutoRun = (sender.state == .on)
        settings.save()
    }

    @objc private func confirmQuitChanged(_ sender: NSSwitch) {
        settings.settings.confirmOnQuit = (sender.state == .on)
        settings.save()
    }

    // MARK: - Row builders

    private func makeSectionHeader(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = AppTheme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 28),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])
        return container
    }

    private func makeSeparator(in parent: NSStackView) -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = AppTheme.border.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(line)
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: 16),
            line.heightAnchor.constraint(equalToConstant: 1),
            line.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            line.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
        ])
        wrapper.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return wrapper
    }

    private func makeInlineRow(_ title: String, right: NSView, popupWidth: CGFloat, in parent: NSStackView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = AppTheme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false

        right.translatesAutoresizingMaskIntoConstraints = false
        right.widthAnchor.constraint(equalToConstant: popupWidth).isActive = true

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)
        wrapper.addSubview(right)
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: rowHeight),
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            right.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
        ])
        wrapper.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return wrapper
    }

    private func makeSwitchRow(_ title: String, isOn: Bool, action: Selector, in parent: NSStackView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = AppTheme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false

        let sw = NSSwitch()
        sw.state = isOn ? .on : .off
        sw.controlSize = .small
        sw.target = self
        sw.action = action
        sw.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)
        wrapper.addSubview(sw)
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: rowHeight),
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            sw.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            sw.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
        ])
        wrapper.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return wrapper
    }

    private func makeTextField() -> NSTextField {
        let f = VerticallyCenteredTextField()
        f.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        f.textColor = AppTheme.textPrimary
        return f
    }
}
