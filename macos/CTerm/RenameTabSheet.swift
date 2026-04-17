import AppKit

final class RenameTabSheet: NSObject, NSWindowDelegate {
    var onConfirm: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private var sheet: NSPanel?
    private weak var parentWindow: NSWindow?
    private var titleField: VerticallyCenteredTextField!

    func show(relativeTo window: NSWindow, initialTitle: String) {
        guard sheet == nil else { return }

        parentWindow = window

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 172),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = AppTheme.bgSecondary
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isFloatingPanel = true
        panel.delegate = self
        sheet = panel

        let contentView = panel.contentView!
        contentView.wantsLayer = true

        let pad: CGFloat = 24
        let fieldWidth: CGFloat = 312
        var y: CGFloat = 136

        let titleLabel = makeLabel("Rename Tab", size: 17, weight: .bold, color: AppTheme.textPrimary)
        titleLabel.frame = NSRect(x: pad, y: y, width: fieldWidth, height: 22)
        contentView.addSubview(titleLabel)
        y -= 30

        let sectionLabel = makeSectionLabel("TAB NAME", y: y)
        contentView.addSubview(sectionLabel)
        y -= 28

        titleField = VerticallyCenteredTextField(frame: .zero)
        titleField.stringValue = initialTitle
        titleField.placeholderString = "Tab name"
        titleField.font = NSFont.systemFont(ofSize: 13)
        titleField.textColor = AppTheme.textPrimary
        let fieldContainer = makeSettingsTextFieldContainer(for: titleField, width: fieldWidth, height: 28)
        fieldContainer.frame = NSRect(x: pad, y: y, width: fieldWidth, height: 28)
        contentView.addSubview(fieldContainer)
        y -= 52

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.frame = NSRect(x: pad + fieldWidth - 168, y: y, width: 78, height: 28)
        contentView.addSubview(cancelButton)

        let renameButton = NSButton(title: "Rename", target: self, action: #selector(renameClicked))
        renameButton.bezelStyle = .rounded
        renameButton.keyEquivalent = "\r"
        renameButton.contentTintColor = .white
        renameButton.frame = NSRect(x: pad + fieldWidth - 84, y: y, width: 84, height: 28)
        if #available(macOS 11.0, *) {
            renameButton.bezelColor = AppTheme.accent
        }
        contentView.addSubview(renameButton)

        window.beginSheet(panel)

        DispatchQueue.main.async { [weak self] in
            self?.titleField.selectText(nil)
        }
    }

    @objc private func cancelClicked() {
        dismiss()
    }

    @objc private func renameClicked() {
        let trimmedTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        onConfirm?(trimmedTitle)
        dismiss()
    }

    func windowWillClose(_ notification: Notification) {
        dismiss()
    }

    private func dismiss() {
        guard let sheet, let parentWindow else { return }

        self.sheet = nil
        self.parentWindow = nil
        parentWindow.endSheet(sheet)
        onDismiss?()
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    private func makeSectionLabel(_ text: String, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = NSColor(white: 0.45, alpha: 1)
        label.frame = NSRect(x: 24, y: y, width: 200, height: 14)
        return label
    }
}
