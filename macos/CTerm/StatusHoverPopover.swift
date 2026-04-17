import AppKit

final class StatusHoverPopoverManager: NSObject {
    static let shared = StatusHoverPopoverManager()

    private let popover = NSPopover()
    private let contentController = StatusHoverPopoverContentController()
    private weak var anchorView: NSView?
    private var pendingShowWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = contentController
    }

    func scheduleShow(text: String?, relativeTo view: NSView, delay: TimeInterval = 0.35) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            close(relativeTo: view)
            return
        }

        cancelPendingShow()
        if anchorView !== view {
            close()
        }

        let workItem = DispatchWorkItem { [weak self, weak view] in
            guard let self, let view, view.window != nil else { return }
            self.anchorView = view
            self.popover.contentSize = self.contentController.configure(text: trimmed)
            self.popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        }

        pendingShowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func update(text: String?, relativeTo view: NSView) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            close(relativeTo: view)
            return
        }
        guard anchorView === view, popover.isShown else { return }

        popover.contentSize = contentController.configure(text: trimmed)
    }

    func close(relativeTo view: NSView? = nil) {
        cancelPendingShow()
        guard view == nil || anchorView === view else { return }
        if popover.isShown {
            popover.performClose(nil)
        }
        anchorView = nil
    }

    private func cancelPendingShow() {
        pendingShowWorkItem?.cancel()
        pendingShowWorkItem = nil
    }
}

final class StatusHoverLabel: NSTextField {
    var hoverText: String? {
        didSet {
            StatusHoverPopoverManager.shared.update(text: hoverText, relativeTo: self)
        }
    }

    private var trackingAreaRef: NSTrackingArea?

    convenience init(labelWithString string: String) {
        self.init(frame: .zero)
        stringValue = string
        isEditable = false
        isBordered = false
        drawsBackground = false
        isSelectable = false
        lineBreakMode = .byClipping
        usesSingleLineMode = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        StatusHoverPopoverManager.shared.scheduleShow(text: hoverText, relativeTo: self)
    }

    override func mouseExited(with event: NSEvent) {
        StatusHoverPopoverManager.shared.close(relativeTo: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            StatusHoverPopoverManager.shared.close(relativeTo: self)
        }
    }
}

private final class StatusHoverPopoverContentController: NSViewController {
    private let backgroundView = NSVisualEffectView()
    private let stackView = NSStackView()
    private let horizontalPadding: CGFloat = 12
    private let verticalPadding: CGFloat = 10
    private let minTextWidth: CGFloat = 120
    private let maxTextWidth: CGFloat = 260
    private var stackViewWidthConstraint: NSLayoutConstraint!
    private var labelWidthConstraints: [NSLayoutConstraint] = []

    override func loadView() {
        backgroundView.material = .popover
        backgroundView.blendingMode = .withinWindow
        backgroundView.state = .active
        backgroundView.appearance = NSAppearance(named: .darkAqua)

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(stackView)

        stackViewWidthConstraint = stackView.widthAnchor.constraint(equalToConstant: maxTextWidth)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: horizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -horizontalPadding),
            stackView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: verticalPadding),
            stackView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -verticalPadding),
            stackViewWidthConstraint,
        ])

        view = backgroundView
    }

    @discardableResult
    func configure(text: String) -> NSSize {
        loadViewIfNeeded()

        for subview in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        NSLayoutConstraint.deactivate(labelWidthConstraints)
        labelWidthConstraints.removeAll()

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let textWidth = measuredTextWidth(for: lines)
        stackViewWidthConstraint.constant = textWidth

        for (index, line) in lines.enumerated() {
            let label = NSTextField(wrappingLabelWithString: line)
            label.font = NSFont.systemFont(ofSize: index == 0 ? 12 : 11, weight: index == 0 ? .medium : .regular)
            label.textColor = index == 0 ? .labelColor : .secondaryLabelColor
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            stackView.addArrangedSubview(label)

            let widthConstraint = label.widthAnchor.constraint(equalToConstant: textWidth)
            widthConstraint.isActive = true
            labelWidthConstraints.append(widthConstraint)
        }

        view.layoutSubtreeIfNeeded()
        let contentSize = NSSize(
            width: textWidth + horizontalPadding * 2,
            height: view.fittingSize.height
        )
        preferredContentSize = contentSize
        return contentSize
    }

    private func measuredTextWidth(for lines: [String]) -> CGFloat {
        var measuredWidth: CGFloat = minTextWidth

        for (index, line) in lines.enumerated() {
            let font = NSFont.systemFont(ofSize: index == 0 ? 12 : 11, weight: index == 0 ? .medium : .regular)
            let rect = (line as NSString).boundingRect(
                with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            )
            measuredWidth = max(measuredWidth, ceil(rect.width))
        }

        return min(maxTextWidth, max(minTextWidth, measuredWidth))
    }
}
