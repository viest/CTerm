import AppKit

protocol TerminalTabBarDelegate: AnyObject {
    func tabBar(_ tabBar: TerminalTabBar, didSelectTabAt index: Int)
    func tabBar(_ tabBar: TerminalTabBar, didCloseTabAt index: Int)
    func tabBar(_ tabBar: TerminalTabBar, didRequestRenameTabAt index: Int)
    func tabBarDidRequestNewTab(_ tabBar: TerminalTabBar)
}

struct TabItem {
    let id: String
    var title: String
}

class TerminalTabBar: NSView {
    weak var delegate: TerminalTabBarDelegate?

    private(set) var tabs: [TabItem] = []
    private(set) var selectedIndex: Int = 0
    private var tabButtons: [TabButton] = []
    private var runningTabIds: Set<String> = []
    private var addButton: NSButton!
    private var scrollView: NSScrollView!
    private var contentView: NSView!

    private let tabHeight: CGFloat = 32
    private let tabMinWidth: CGFloat = 120
    private let tabMaxWidth: CGFloat = 200

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.13, alpha: 1).cgColor

        // Bottom border
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = AppTheme.border.cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        // Add tab button
        addButton = NSButton(title: "+", target: self, action: #selector(addTabClicked))
        addButton.bezelStyle = .inline
        addButton.isBordered = false
        addButton.font = NSFont.systemFont(ofSize: 16, weight: .light)
        addButton.contentTintColor = AppTheme.textSecondary
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(addButton)

        // Scroll view for tabs
        scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        contentView = TerminalTabFlippedView()
        scrollView.documentView = contentView

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: tabHeight),

            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),

            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 28),
            addButton.heightAnchor.constraint(equalToConstant: 28),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -2),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Public API

    func addTab(_ tab: TabItem) {
        tabs.append(tab)
        selectedIndex = tabs.count - 1
        rebuildTabs()
    }

    func setTabs(_ newTabs: [TabItem], selectedIndex: Int) {
        tabs = newTabs
        if newTabs.isEmpty {
            self.selectedIndex = 0
        } else {
            self.selectedIndex = min(max(selectedIndex, 0), newTabs.count - 1)
        }
        rebuildTabs()
    }

    func removeTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        runningTabIds.remove(tabs[index].id)
        tabs.remove(at: index)
        if selectedIndex >= tabs.count { selectedIndex = max(0, tabs.count - 1) }
        rebuildTabs()
    }

    func selectTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        selectedIndex = index
        updateSelection()
    }

    func updateTabTitle(at index: Int, title: String) {
        guard index >= 0 && index < tabs.count else { return }
        tabs[index].title = title
        if index < tabButtons.count {
            tabButtons[index].title = title
        }
    }

    func setRunningTabs(_ ids: Set<String>) {
        guard runningTabIds != ids else { return }
        runningTabIds = ids
        for (index, button) in tabButtons.enumerated() where index < tabs.count {
            button.isRunning = runningTabIds.contains(tabs[index].id)
        }
    }

    var tabCount: Int { tabs.count }

    // MARK: - Internal

    private func rebuildTabs() {
        for btn in tabButtons { btn.removeFromSuperview() }
        tabButtons = []

        let availableWidth = scrollView.bounds.width
        let tabWidth = max(tabMinWidth, min(tabMaxWidth, availableWidth / max(1, CGFloat(tabs.count))))
        var x: CGFloat = 0

        for (i, tab) in tabs.enumerated() {
            let btn = TabButton(
                title: tab.title,
                index: i,
                isSelected: i == selectedIndex,
                isRunning: runningTabIds.contains(tab.id)
            )
            btn.target = self
            btn.onSelect = { [weak self] idx in self?.tabSelected(idx) }
            btn.onClose = { [weak self] idx in self?.tabClosed(idx) }
            btn.onRename = { [weak self] idx in self?.tabRenameRequested(idx) }
            btn.frame = NSRect(x: x, y: 0, width: tabWidth, height: tabHeight)
            contentView.addSubview(btn)
            tabButtons.append(btn)
            x += tabWidth
        }

        contentView.frame = NSRect(x: 0, y: 0, width: x, height: tabHeight)
        updateSelection()
    }

    private func updateSelection() {
        for (i, btn) in tabButtons.enumerated() {
            btn.isSelected = (i == selectedIndex)
        }
    }

    private func tabSelected(_ index: Int) {
        selectedIndex = index
        updateSelection()
        delegate?.tabBar(self, didSelectTabAt: index)
    }

    private func tabClosed(_ index: Int) {
        delegate?.tabBar(self, didCloseTabAt: index)
    }

    private func tabRenameRequested(_ index: Int) {
        delegate?.tabBar(self, didRequestRenameTabAt: index)
    }

    @objc private func addTabClicked() {
        delegate?.tabBarDidRequestNewTab(self)
    }

    private var lastLayoutWidth: CGFloat = 0

    override func layout() {
        super.layout()
        let w = bounds.width
        if abs(w - lastLayoutWidth) > 1 && w > 0 {
            lastLayoutWidth = w
            relayoutTabs()
        }
    }

    /// Relayout existing buttons without recreating them
    private func relayoutTabs() {
        guard !tabButtons.isEmpty else { return }
        let availableWidth = scrollView.bounds.width
        let tabWidth = max(tabMinWidth, min(tabMaxWidth, availableWidth / max(1, CGFloat(tabs.count))))
        var x: CGFloat = 0
        for btn in tabButtons {
            btn.frame = NSRect(x: x, y: 0, width: tabWidth, height: tabHeight)
            x += tabWidth
        }
        contentView.frame = NSRect(x: 0, y: 0, width: x, height: tabHeight)
    }
}

private class TerminalTabFlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Individual tab button

class TabButton: NSView {
    private static let selectedFillColor = NSColor(white: 0.18, alpha: 1)
    private static let hoverFillColor = NSColor(white: 0.18, alpha: 0.7)
    private static let separatorColor = NSColor(white: 0.22, alpha: 1)

    var title: String { didSet { needsDisplay = true } }
    let index: Int
    var isSelected: Bool { didSet { needsDisplay = true } }
    var isRunning: Bool {
        didSet {
            loadingIndicator.isHidden = !isRunning
            needsDisplay = true
        }
    }
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onRename: ((Int) -> Void)?

    weak var target: AnyObject?
    private var isHovered = false
    private var isCloseHovered = false
    private var trackingArea: NSTrackingArea?

    private let closeSize: CGFloat = 14
    private let loadingIndicator: BrailleLoadingIndicator

    init(title: String, index: Int, isSelected: Bool, isRunning: Bool) {
        self.title = title
        self.index = index
        self.isSelected = isSelected
        self.isRunning = isRunning
        self.loadingIndicator = BrailleLoadingIndicator(fontSize: 11.5)
        super.init(frame: .zero)
        wantsLayer = true
        setupLoadingIndicator()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLoadingIndicator() {
        loadingIndicator.isHidden = !isRunning
        addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            loadingIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            loadingIndicator.widthAnchor.constraint(equalToConstant: 10),
            loadingIndicator.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    private func displayTitle() -> String {
        let trimmed = title.trimmingCharacters(in: .newlines)
        guard let first = trimmed.first,
              BrailleLoadingIndicator.frames.contains(String(first)) else {
            return title
        }

        let remainder = trimmed.dropFirst()
        guard remainder.first?.isWhitespace == true else {
            return title
        }

        let cleaned = remainder.drop(while: \.isWhitespace)
        return cleaned.isEmpty ? title : String(cleaned)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { isHovered = false; isCloseHovered = false; needsDisplay = true }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let closeRect = closeButtonRect()
        let wasCloseHovered = isCloseHovered
        isCloseHovered = closeRect.contains(loc)
        if wasCloseHovered != isCloseHovered { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if closeButtonRect().contains(loc) {
            onClose?(index)
        } else if event.clickCount == 2 {
            onRename?(index)
        } else {
            onSelect?(index)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let renameItem = NSMenuItem(title: "Rename Tab...", action: #selector(contextRename), keyEquivalent: "")
        renameItem.target = self
        menu.addItem(renameItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func contextRename() {
        onRename?(index)
    }

    private func closeButtonRect() -> NSRect {
        let x = bounds.width - closeSize - 8
        let y = (bounds.height - closeSize) / 2
        return NSRect(x: x, y: y, width: closeSize, height: closeSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        let contentRect = bounds.insetBy(dx: 4, dy: 4)

        // Background
        if isSelected {
            let selectedPath = NSBezierPath(roundedRect: contentRect, xRadius: 4, yRadius: 4)
            Self.selectedFillColor.setFill()
            selectedPath.fill()
        } else if isHovered {
            let hoverPath = NSBezierPath(roundedRect: contentRect, xRadius: 4, yRadius: 4)
            Self.hoverFillColor.setFill()
            hoverPath.fill()
        }

        // Right separator
        if !isSelected {
            Self.separatorColor.setFill()
            NSRect(x: bounds.width - 1, y: 6, width: 1, height: bounds.height - 12).fill()
        }

        // Title — draw with clipping rect, no truncation loop
        let font = NSFont.systemFont(ofSize: 11.5, weight: isSelected ? .medium : .regular)
        let textColor = isSelected ? AppTheme.textPrimary : AppTheme.textSecondary
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let textX: CGFloat = isRunning ? 28 : 10
        let maxTextWidth = bounds.width - (isRunning ? 58 : 40)
        let displayTitle = displayTitle()
        let strSize = (displayTitle as NSString).size(withAttributes: attrs)
        let textY = (bounds.height - strSize.height) / 2

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: textX, y: 0, width: max(0, maxTextWidth), height: bounds.height)).addClip()
        (displayTitle as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()

        // Close button (show on hover or selected)
        if isHovered || isSelected {
            let closeRect = closeButtonRect()
            if isCloseHovered {
                NSColor(white: 0.3, alpha: 1).setFill()
                NSBezierPath(roundedRect: closeRect, xRadius: 3, yRadius: 3).fill()
            }
            let xColor = isCloseHovered ? AppTheme.textPrimary : AppTheme.textSecondary
            xColor.setStroke()
            let inset: CGFloat = 3.5
            let path = NSBezierPath()
            path.lineWidth = 1.3
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: closeRect.minX + inset, y: closeRect.minY + inset))
            path.line(to: NSPoint(x: closeRect.maxX - inset, y: closeRect.maxY - inset))
            path.move(to: NSPoint(x: closeRect.maxX - inset, y: closeRect.minY + inset))
            path.line(to: NSPoint(x: closeRect.minX + inset, y: closeRect.maxY - inset))
            path.stroke()
        }
    }
}
