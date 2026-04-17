import AppKit

class SettingsTerminalTab: NSView {
    private var fontPopup: NSPopUpButton!
    private var fontSizeField: NSTextField!
    private var fontSizeStepper: NSStepper!
    private var scrollbackField: NSTextField!
    private var cursorSegment: NSSegmentedControl!
    private var themePopup: NSPopUpButton!

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

        // — FONT
        stack.addArrangedSubview(makeSectionHeader("Font"))

        fontPopup = NSPopUpButton()
        fontPopup.font = NSFont.systemFont(ofSize: 12)
        for f in monospacedFonts() { fontPopup.addItem(withTitle: f) }
        fontPopup.selectItem(withTitle: settings.settings.fontFamily)
        fontPopup.target = self
        fontPopup.action = #selector(fontChanged)
        stack.addArrangedSubview(makeInlineRow("Family", right: fontPopup, rightWidth: 220, in: stack))

        // Font size with stepper
        fontSizeField = VerticallyCenteredTextField()
        fontSizeField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        fontSizeField.textColor = AppTheme.textPrimary
        fontSizeField.alignment = .center
        fontSizeField.integerValue = Int(settings.settings.fontSize)
        fontSizeField.target = self
        fontSizeField.action = #selector(fontSizeFieldChanged)
        let fontSizeFieldContainer = makeSettingsTextFieldContainer(for: fontSizeField, width: 50)

        fontSizeStepper = NSStepper()
        fontSizeStepper.minValue = 8
        fontSizeStepper.maxValue = 32
        fontSizeStepper.integerValue = Int(settings.settings.fontSize)
        fontSizeStepper.target = self
        fontSizeStepper.action = #selector(fontSizeStepperChanged)
        fontSizeStepper.translatesAutoresizingMaskIntoConstraints = false

        let ptLabel = NSTextField(labelWithString: "pt")
        ptLabel.font = NSFont.systemFont(ofSize: 11)
        ptLabel.textColor = AppTheme.textSecondary
        ptLabel.translatesAutoresizingMaskIntoConstraints = false

        let sizeGroup = NSStackView(views: [fontSizeFieldContainer, fontSizeStepper, ptLabel])
        sizeGroup.spacing = 4
        sizeGroup.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(makeInlineRowWithView("Size", right: sizeGroup, in: stack))

        stack.addArrangedSubview(makeSeparator(in: stack))

        // — DISPLAY
        stack.addArrangedSubview(makeSectionHeader("Display"))

        scrollbackField = VerticallyCenteredTextField()
        scrollbackField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        scrollbackField.textColor = AppTheme.textPrimary
        scrollbackField.alignment = .center
        scrollbackField.integerValue = settings.settings.scrollbackLines
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 1000
        formatter.maximum = 100000
        scrollbackField.formatter = formatter
        scrollbackField.target = self
        scrollbackField.action = #selector(scrollbackChanged)
        let scrollbackFieldContainer = makeSettingsTextFieldContainer(for: scrollbackField, width: 90)
        stack.addArrangedSubview(makeInlineRowWithView("Scrollback Lines", right: scrollbackFieldContainer, in: stack))

        cursorSegment = NSSegmentedControl(labels: ["Block", "Beam", "Underline"],
                                            trackingMode: .selectOne,
                                            target: self,
                                            action: #selector(cursorChanged))
        switch settings.settings.cursorStyle {
        case "beam": cursorSegment.selectedSegment = 1
        case "underline": cursorSegment.selectedSegment = 2
        default: cursorSegment.selectedSegment = 0
        }
        cursorSegment.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(makeInlineRowWithView("Cursor Style", right: cursorSegment, in: stack))

        themePopup = NSPopUpButton()
        themePopup.font = NSFont.systemFont(ofSize: 12)
        themePopup.addItem(withTitle: "Dark")
        themePopup.addItem(withTitle: "Light")
        themePopup.selectItem(withTitle: settings.settings.terminalTheme == "light" ? "Light" : "Dark")
        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        stack.addArrangedSubview(makeInlineRow("Theme", right: themePopup, rightWidth: 120, in: stack))
    }

    // MARK: - Actions

    @objc private func fontChanged() {
        settings.settings.fontFamily = fontPopup.selectedItem?.title ?? "SF Mono"
        settings.save()
    }

    @objc private func fontSizeFieldChanged() {
        let val = fontSizeField.integerValue
        guard val >= 8 && val <= 32 else { return }
        settings.settings.fontSize = Double(val)
        fontSizeStepper.integerValue = val
        settings.save()
    }

    @objc private func fontSizeStepperChanged() {
        let val = fontSizeStepper.integerValue
        fontSizeField.integerValue = val
        settings.settings.fontSize = Double(val)
        settings.save()
    }

    @objc private func scrollbackChanged() {
        settings.settings.scrollbackLines = scrollbackField.integerValue
        settings.save()
    }

    @objc private func cursorChanged() {
        let styles = ["block", "beam", "underline"]
        let idx = cursorSegment.selectedSegment
        if idx >= 0 && idx < styles.count {
            settings.settings.cursorStyle = styles[idx]
            settings.save()
        }
    }

    @objc private func themeChanged() {
        settings.settings.terminalTheme = themePopup.selectedItem?.title.lowercased() ?? "dark"
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

    private func makeInlineRow(_ title: String, right: NSPopUpButton, rightWidth: CGFloat, in parent: NSStackView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = AppTheme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false

        right.translatesAutoresizingMaskIntoConstraints = false
        right.widthAnchor.constraint(equalToConstant: rightWidth).isActive = true

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

    private func makeInlineRowWithView(_ title: String, right: NSView, in parent: NSStackView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = AppTheme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false

        right.translatesAutoresizingMaskIntoConstraints = false

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

    // MARK: - Helpers

    private func monospacedFonts() -> [String] {
        let candidates = [
            settings.settings.fontFamily,
            "SF Mono",
            "Menlo",
            "Monaco",
            "JetBrains Mono",
            "Fira Code",
            "Hack",
            "Source Code Pro",
            "IBM Plex Mono",
            "Courier New",
        ]

        var fonts: [String] = []
        var seen = Set<String>()
        for family in candidates {
            guard !family.isEmpty, !seen.contains(family) else { continue }
            guard let font = NSFont(name: family, size: 13), font.isFixedPitch else { continue }
            seen.insert(family)
            fonts.append(family)
        }

        if fonts.isEmpty {
            fonts = ["SF Mono", "Menlo", "Monaco", "Courier New"]
        }
        return fonts
    }
}
