import AppKit

final class AboutWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private weak var parentWindow: NSWindow?

    override init() {
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "About CTerm"
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
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = AppTheme.bgPrimary.cgColor

        let topBar = NSView()
        topBar.wantsLayer = true
        topBar.layer?.backgroundColor = AppTheme.bgSecondary.cgColor
        topBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(topBar)

        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = AppTheme.border.cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(border)

        let topTitle = NSTextField(labelWithString: "About")
        topTitle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        topTitle.textColor = AppTheme.textSecondary
        topTitle.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(topTitle)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 88).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 88).isActive = true
        stack.addArrangedSubview(iconView)

        let nameLabel = NSTextField(labelWithString: appName())
        nameLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        nameLabel.textColor = AppTheme.textPrimary
        stack.addArrangedSubview(nameLabel)

        let infoStack = NSStackView()
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 8
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(infoStack)

        stack.setCustomSpacing(16, after: nameLabel)

        let infoRows = [
            ("Author", "viest"),
            ("Email", "wjx@php.net"),
            ("Version", versionText()),
            ("Built", buildTimeText()),
        ]
        for (title, value) in infoRows {
            infoStack.addArrangedSubview(makeInfoRow(title: title, value: value))
        }

        let copyrightText = copyrightString()
        if !copyrightText.isEmpty {
            let copyrightLabel = NSTextField(labelWithString: copyrightText)
            copyrightLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            copyrightLabel.textColor = AppTheme.textSecondary
            stack.addArrangedSubview(copyrightLabel)
        }

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 38),

            border.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            border.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),

            topTitle.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            topTitle.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 12),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
        ])
    }

    private func appName() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "CTerm"
    }

    private func makeInfoRow(title: String, value: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = AppTheme.textSecondary
        titleLabel.alignment = .right
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = AppTheme.textPrimary
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.maximumNumberOfLines = 1

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)
        return row
    }

    private func versionText() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let buildNumber = info["CFBundleVersion"] as? String ?? "0"
        return "Version \(shortVersion) (\(buildNumber))"
    }

    private func buildTimeText() -> String {
        guard let executableURL = Bundle.main.executableURL,
              let values = try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]),
              let buildDate = values.contentModificationDate else {
            return "Unknown"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss z"
        return formatter.string(from: buildDate)
    }

    private func copyrightString() -> String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }
}
