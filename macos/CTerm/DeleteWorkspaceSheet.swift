import AppKit

final class DeleteWorkspaceSheet: NSObject, NSWindowDelegate {
    var onConfirm: ((Bool) -> Void)?
    var onDismiss: (() -> Void)?

    private var sheet: NSPanel?
    private weak var parentWindow: NSWindow?
    private var deleteBranchCheckbox: NSButton!

    func show(relativeTo window: NSWindow, workspace: WorkspaceItem) {
        guard sheet == nil else { return }

        parentWindow = window

        let panelWidth: CGFloat = 460
        let panelHeight: CGFloat = 262
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
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
        let contentWidth: CGFloat = panelWidth - (pad * 2)
        var y: CGFloat = panelHeight - 36

        let titleLabel = makeLabel("Delete Workspace", size: 17, weight: .bold, color: AppTheme.textPrimary)
        titleLabel.frame = NSRect(x: pad, y: y, width: contentWidth, height: 22)
        contentView.addSubview(titleLabel)
        y -= 34

        let messageLabel = makeWrappingLabel(
            "Delete workspace '\(workspace.name)'?\nThis will remove the git worktree at:",
            font: NSFont.systemFont(ofSize: 13),
            color: AppTheme.textPrimary
        )
        messageLabel.frame = NSRect(x: pad, y: y - 28, width: contentWidth, height: 42)
        contentView.addSubview(messageLabel)
        y -= 64

        let pathLabel = makeWrappingLabel(
            workspace.worktreePath,
            font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            color: AppTheme.textSecondary
        )
        pathLabel.frame = NSRect(x: pad, y: y - 16, width: contentWidth, height: 36)
        contentView.addSubview(pathLabel)
        y -= 48

        deleteBranchCheckbox = NSButton(checkboxWithTitle: "Also delete branch '\(workspace.branchName)'", target: nil, action: nil)
        deleteBranchCheckbox.state = .off
        deleteBranchCheckbox.font = NSFont.systemFont(ofSize: 13)
        deleteBranchCheckbox.contentTintColor = AppTheme.textSecondary
        deleteBranchCheckbox.attributedTitle = NSAttributedString(
            string: deleteBranchCheckbox.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: AppTheme.textPrimary,
            ]
        )
        deleteBranchCheckbox.frame = NSRect(x: pad, y: y, width: contentWidth, height: 22)
        contentView.addSubview(deleteBranchCheckbox)
        y -= 56

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.frame = NSRect(x: pad + contentWidth - 168, y: y, width: 78, height: 28)
        contentView.addSubview(cancelButton)

        let deleteButton = NSButton(title: "Delete", target: self, action: #selector(deleteClicked))
        deleteButton.bezelStyle = .rounded
        deleteButton.keyEquivalent = "\r"
        deleteButton.contentTintColor = .white
        deleteButton.frame = NSRect(x: pad + contentWidth - 84, y: y, width: 84, height: 28)
        if #available(macOS 11.0, *) {
            deleteButton.bezelColor = AppTheme.accent
        }
        contentView.addSubview(deleteButton)

        window.beginSheet(panel)
    }

    @objc private func cancelClicked() {
        dismiss()
    }

    @objc private func deleteClicked() {
        onConfirm?(deleteBranchCheckbox.state == .on)
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

    private func makeWrappingLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = color
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }
}
