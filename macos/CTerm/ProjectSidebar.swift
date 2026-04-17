import AppKit

protocol ProjectSidebarDelegate: AnyObject {
    func projectLocalSelected(_ project: ProjectItem)
    func projectOpenInEditor(_ project: ProjectItem)
    func projectRemoved(_ project: ProjectItem)
    func addProjectRequested()
    func newWorkspaceRequested()
    func workspaceSelected(_ workspace: WorkspaceItem)
    func workspaceDeleteRequested(_ workspace: WorkspaceItem)
    func workspaceOpenInEditor(_ workspace: WorkspaceItem)
}

class ProjectSidebar: NSView {
    enum ActiveSelection: Equatable {
        case none
        case local(UUID)
        case workspace(UUID)
    }

    weak var delegate: ProjectSidebarDelegate?
    private var projects: [ProjectItem] = []
    private var workspaces: [WorkspaceItem] = []
    private var expandedIndex: Int = -1
    private var activeSelection: ActiveSelection = .none
    private var runningLocalProjectIds: Set<UUID> = []
    private var runningWorkspaceIds: Set<UUID> = []

    private var scrollView: NSScrollView!
    private var stackView: NSStackView!

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1).cgColor

        // Right border removed — NSSplitView divider handles separation

        // -- Top nav items --
        let navStack = NSStackView()
        navStack.orientation = .vertical
        navStack.spacing = 0
        navStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(navStack)

        let newWsRow = makeNavRow(icon: "plus", title: "New Workspace", shortcut: "\u{2318}N")
        navStack.addArrangedSubview(newWsRow)
        newWsRow.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(newWorkspace)))
        navStack.addArrangedSubview(makeSeparator())

        // -- Project list --
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        let flipContainer = SidebarFlipView()
        flipContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = flipContainer

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        flipContainer.addSubview(stackView)

        // -- Bottom: separator + Add repository --
        let bottomSep = NSView()
        bottomSep.wantsLayer = true
        bottomSep.layer?.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor
        bottomSep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomSep)

        let bottomRow = makeNavRow(icon: "square.and.arrow.down.on.square", title: "Add repository", shortcut: nil)
        bottomRow.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(addProject)))
        bottomRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomRow)

        NSLayoutConstraint.activate([
            navStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            navStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            navStack.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: navStack.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomSep.topAnchor),

            bottomSep.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomSep.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomSep.bottomAnchor.constraint(equalTo: bottomRow.topAnchor, constant: -4),
            bottomSep.heightAnchor.constraint(equalToConstant: 1),

            flipContainer.topAnchor.constraint(equalTo: scrollView.topAnchor),
            flipContainer.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            flipContainer.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: flipContainer.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: flipContainer.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: flipContainer.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: flipContainer.bottomAnchor),

            bottomRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshGitStatusRows()
    }

    // MARK: - Helpers

    private func makeNavRow(icon: String, title: String, shortcut: String?) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let img = NSImageView()
        img.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        img.contentTintColor = AppTheme.textSecondary
        img.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(img)

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12.5)
        label.textColor = AppTheme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)

        NSLayoutConstraint.activate([
            img.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            img.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            img.widthAnchor.constraint(equalToConstant: 16),
            img.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        if let sc = shortcut {
            let scLabel = NSTextField(labelWithString: sc)
            scLabel.font = NSFont.systemFont(ofSize: 10)
            scLabel.textColor = NSColor(white: 0.35, alpha: 1)
            scLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(scLabel)
            scLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12).isActive = true
            scLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor).isActive = true
        }

        return row
    }

    private func makeSeparator() -> NSView {
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return sep
    }

    // MARK: - Data

    func setWorkspaces(_ workspaces: [WorkspaceItem]) {
        self.workspaces = workspaces
        rebuildRows()
    }

    func setProjects(_ projects: [ProjectItem]) {
        self.projects = projects.sorted(by: Self.sortProjects)
        rebuildRows()
    }

    func setRunningActivity(localProjectIds: Set<UUID>, workspaceIds: Set<UUID>) {
        guard runningLocalProjectIds != localProjectIds || runningWorkspaceIds != workspaceIds else { return }
        runningLocalProjectIds = localProjectIds
        runningWorkspaceIds = workspaceIds
        rebuildRows()
    }

    private static func sortProjects(_ lhs: ProjectItem, _ rhs: ProjectItem) -> Bool {
        let lhsName = lhs.name.lowercased()
        let rhsName = rhs.name.lowercased()
        if lhsName != rhsName {
            return lhsName < rhsName
        }

        let lhsPath = lhs.path.lowercased()
        let rhsPath = rhs.path.lowercased()
        if lhsPath != rhsPath {
            return lhsPath < rhsPath
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    func setActiveSelection(_ selection: ActiveSelection) {
        activeSelection = selection

        switch selection {
        case .local(let projectId):
            if let projectIndex = projects.firstIndex(where: { $0.id == projectId }) {
                expandedIndex = projectIndex
            }
        case .workspace(let workspaceId):
            if let workspace = workspaces.first(where: { $0.id == workspaceId }),
               let projectIndex = projects.firstIndex(where: { $0.id == workspace.projectId }) {
                expandedIndex = projectIndex
            }
        case .none:
            break
        }

        rebuildRows()
    }

    func expandProject(at index: Int) {
        guard index >= 0, index < projects.count else { return }
        expandedIndex = index
        rebuildRows()
    }

    private func rebuildRows() {
        for v in stackView.arrangedSubviews { stackView.removeArrangedSubview(v); v.removeFromSuperview() }

        for (i, project) in projects.enumerated() {
            let isExpanded = (i == expandedIndex)
            let projectWorkspaces = workspaces.filter { $0.projectId == project.id }
            let wsCount = projectWorkspaces.count + 1 // +1 for "local"
            let isLocalSelected = activeSelection == .local(project.id)
            let isProjectLoading = runningLocalProjectIds.contains(project.id) || projectWorkspaces.contains { runningWorkspaceIds.contains($0.id) }

            let row = ProjectGroupRow(
                project: project,
                index: i,
                expanded: isExpanded,
                workspaceCount: wsCount,
                isLoading: isProjectLoading
            )
            row.onToggle = { [weak self] idx in
                guard let self = self else { return }
                self.expandedIndex = (self.expandedIndex == idx) ? -1 : idx
                self.rebuildRows()
            }
            row.onAdd = { [weak self] idx in
                self?.delegate?.newWorkspaceRequested()
            }
            row.onOpen = { [weak self] project in
                self?.delegate?.projectLocalSelected(project)
            }
            row.onOpenInEditor = { [weak self] project in
                self?.delegate?.projectOpenInEditor(project)
            }
            row.onDelete = { [weak self] project in
                self?.delegate?.projectRemoved(project)
            }
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

            if isExpanded {
                // "local" workspace (main working copy)
                let localRow = WorkspaceDetailRow(project: project, selected: isLocalSelected, isLoading: runningLocalProjectIds.contains(project.id))
                localRow.onClick = { [weak self] p in self?.delegate?.projectLocalSelected(p) }
                stackView.addArrangedSubview(localRow)
                localRow.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

                // Git worktree workspaces
                for ws in projectWorkspaces {
                    let wsRow = WorkspaceWorktreeRow(
                        workspace: ws,
                        selected: activeSelection == .workspace(ws.id),
                        isLoading: runningWorkspaceIds.contains(ws.id)
                    )
                    wsRow.onClick = { [weak self] w in self?.delegate?.workspaceSelected(w) }
                    wsRow.onDelete = { [weak self] w in self?.delegate?.workspaceDeleteRequested(w) }
                    wsRow.onOpenInEditor = { [weak self] w in self?.delegate?.workspaceOpenInEditor(w) }
                    stackView.addArrangedSubview(wsRow)
                    wsRow.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
                }
            }
        }
    }

    func refreshGitStatusRows() {
        guard window != nil else { return }

        for arrangedSubview in stackView.arrangedSubviews {
            if let row = arrangedSubview as? WorkspaceDetailRow {
                row.needsDisplay = true
                continue
            }

            if let row = arrangedSubview as? WorkspaceWorktreeRow {
                row.needsDisplay = true
            }
        }
    }

    @objc private func addProject() { delegate?.addProjectRequested() }
    @objc private func newWorkspace() { delegate?.newWorkspaceRequested() }
}

private class SidebarFlipView: NSView {
    override var isFlipped: Bool { true }
}

final class BrailleLoadingIndicator: NSTextField {
    static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    private var frameIndex = 0
    private var animationTimer: Timer?

    init(fontSize: CGFloat, color: NSColor = AppTheme.textSecondary) {
        super.init(frame: .zero)
        isEditable = false
        isBezeled = false
        isBordered = false
        drawsBackground = false
        isSelectable = false
        stringValue = Self.frames[0]
        font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
        textColor = color
        alignment = .center
        lineBreakMode = .byClipping
        translatesAutoresizingMaskIntoConstraints = false
        setContentCompressionResistancePriority(.required, for: .horizontal)
        startAnimating()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        animationTimer?.invalidate()
    }

    private func startAnimating() {
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.advanceFrame()
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceFrame() {
        frameIndex = (frameIndex + 1) % Self.frames.count
        stringValue = Self.frames[frameIndex]
    }
}

private func makeLoadingIndicator(fontSize: CGFloat) -> BrailleLoadingIndicator {
    BrailleLoadingIndicator(fontSize: fontSize)
}

// MARK: - Project group header row (like Superset)

private class ProjectGroupRow: NSView {
    var onToggle: ((Int) -> Void)?
    var onAdd: ((Int) -> Void)?
    var onOpen: ((ProjectItem) -> Void)?
    var onOpenInEditor: ((ProjectItem) -> Void)?
    var onDelete: ((ProjectItem) -> Void)?
    private let project: ProjectItem
    private let index: Int
    private let expanded: Bool
    private let workspaceCount: Int
    private let isLoading: Bool
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    private static let avatarColors: [NSColor] = [
        NSColor(red: 0.40, green: 0.52, blue: 0.95, alpha: 1),
        NSColor(red: 0.85, green: 0.45, blue: 0.30, alpha: 1),
        NSColor(red: 0.30, green: 0.75, blue: 0.48, alpha: 1),
        NSColor(red: 0.70, green: 0.42, blue: 0.85, alpha: 1),
        NSColor(red: 0.85, green: 0.60, blue: 0.25, alpha: 1),
        NSColor(red: 0.40, green: 0.70, blue: 0.75, alpha: 1),
    ]

    init(project: ProjectItem, index: Int, expanded: Bool, workspaceCount: Int = 1, isLoading: Bool = false) {
        self.project = project
        self.index = index
        self.expanded = expanded
        self.workspaceCount = workspaceCount
        self.isLoading = isLoading
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 38).isActive = true
        if isLoading {
            let indicator = makeLoadingIndicator(fontSize: 12.5)
            addSubview(indicator)
            NSLayoutConstraint.activate([
                indicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
                indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
                indicator.widthAnchor.constraint(equalToConstant: 12),
                indicator.heightAnchor.constraint(equalToConstant: 14),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        // Click on "+" area
        if loc.x > bounds.width - 50 && loc.x < bounds.width - 25 {
            onAdd?(index)
            return
        }
        onToggle?(index)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open Terminal", action: #selector(contextOpen), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let editorItem = NSMenuItem(title: "Open in Editor", action: #selector(contextOpenInEditor), keyEquivalent: "")
        editorItem.target = self
        menu.addItem(editorItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(title: "Remove Repository...", action: #selector(contextDelete), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func contextOpen() { onOpen?(project) }
    @objc private func contextOpenInEditor() { onOpenInEditor?(project) }
    @objc private func contextDelete() { onDelete?(project) }

    private func drawPlusIcon(center: NSPoint, color: NSColor) {
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round

        path.move(to: NSPoint(x: center.x - 4, y: center.y))
        path.line(to: NSPoint(x: center.x + 4, y: center.y))
        path.move(to: NSPoint(x: center.x, y: center.y - 4))
        path.line(to: NSPoint(x: center.x, y: center.y + 4))

        color.setStroke()
        path.stroke()
    }

    private func drawChevronIcon(center: NSPoint, color: NSColor) {
        let path = NSBezierPath()
        path.lineWidth = 1.7
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        if expanded {
            path.move(to: NSPoint(x: center.x - 3.5, y: center.y + 1.5))
            path.line(to: NSPoint(x: center.x, y: center.y - 2))
            path.line(to: NSPoint(x: center.x + 3.5, y: center.y + 1.5))
        } else {
            path.move(to: NSPoint(x: center.x - 1.5, y: center.y + 3.5))
            path.line(to: NSPoint(x: center.x + 2, y: center.y))
            path.line(to: NSPoint(x: center.x - 1.5, y: center.y - 3.5))
        }

        color.setStroke()
        path.stroke()
    }

    private func avatarColor() -> NSColor {
        let stableKey = project.path.isEmpty ? project.name : project.path
        let colorIndex = Int(Self.stableHash(stableKey) % UInt64(Self.avatarColors.count))
        return Self.avatarColors[colorIndex]
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor(white: 0.15, alpha: 1).setFill()
            bounds.fill()
        }

        let y = bounds.height

        // Avatar letter (circle)
        let avatarSize: CGFloat = 22
        let avatarX: CGFloat = 12
        let avatarY = (y - avatarSize) / 2
        let initial = String(project.name.prefix(1)).uppercased()
        let color = avatarColor()

        if !isLoading {
            color.withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: NSRect(x: avatarX, y: avatarY, width: avatarSize, height: avatarSize), xRadius: 5, yRadius: 5).fill()

            let iFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
            let iAttrs: [NSAttributedString.Key: Any] = [.font: iFont, .foregroundColor: color]
            let iSize = (initial as NSString).size(withAttributes: iAttrs)
            (initial as NSString).draw(at: NSPoint(
                x: avatarX + (avatarSize - iSize.width) / 2,
                y: avatarY + (avatarSize - iSize.height) / 2
            ), withAttributes: iAttrs)
        }

        // Project name
        let nameX = avatarX + avatarSize + 8
        let nameFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        let nameParagraphStyle = NSMutableParagraphStyle()
        nameParagraphStyle.lineBreakMode = .byTruncatingTail
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: nameFont,
            .foregroundColor: AppTheme.textPrimary,
            .paragraphStyle: nameParagraphStyle,
        ]
        let nameY = (y - 15) / 2

        // Workspace count
        let countFont = NSFont.systemFont(ofSize: 11)
        let countAttrs: [NSAttributedString.Key: Any] = [.font: countFont, .foregroundColor: AppTheme.textSecondary]
        let countStr = "(\(workspaceCount))" as NSString

        // Right side: "+" and chevron
        let btnColor = isHovered ? AppTheme.textPrimary : AppTheme.textSecondary
        drawPlusIcon(center: NSPoint(x: bounds.width - 40, y: bounds.midY), color: btnColor)
        drawChevronIcon(center: NSPoint(x: bounds.width - 18, y: bounds.midY), color: btnColor)

        let controlsLeftX = bounds.width - 52
        let countW = countStr.size(withAttributes: countAttrs).width
        let minimumNameWidth: CGFloat = 44
        let countSpacing: CGFloat = 5
        let nameRectHeight: CGFloat = 16
        let showsCount = (controlsLeftX - nameX) >= (minimumNameWidth + countSpacing + countW)
        let nameMaxX = showsCount ? (controlsLeftX - countW - countSpacing) : controlsLeftX
        let nameRect = NSRect(x: nameX, y: nameY - 1, width: max(0, nameMaxX - nameX), height: nameRectHeight)
        let nameAttrString = NSAttributedString(string: project.name, attributes: nameAttrs)
        nameAttrString.draw(with: nameRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        if showsCount {
            countStr.draw(at: NSPoint(x: controlsLeftX - countW, y: nameY + 1), withAttributes: countAttrs)
        }

        // Bottom separator
        NSColor(white: 0.16, alpha: 1).setFill()
        NSRect(x: 12, y: 0, width: bounds.width - 24, height: 1).fill()
    }
}

// MARK: - Expanded workspace detail row

private class WorkspaceDetailRow: NSView {
    var onClick: ((ProjectItem) -> Void)?
    private let project: ProjectItem
    private let selected: Bool
    private let isLoading: Bool
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(project: ProjectItem, selected: Bool = false, isLoading: Bool = false) {
        self.project = project
        self.selected = selected
        self.isLoading = isLoading
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.15, alpha: 1).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 44).isActive = true
        if isLoading {
            let indicator = makeLoadingIndicator(fontSize: 11.5)
            addSubview(indicator)
            NSLayoutConstraint.activate([
                indicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 21),
                indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
                indicator.widthAnchor.constraint(equalToConstant: 10),
                indicator.heightAnchor.constraint(equalToConstant: 12),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { onClick?(project) }

    override func draw(_ dirtyRect: NSRect) {
        if selected {
            AppTheme.bgTertiary.setFill()
            bounds.fill()
            AppTheme.accent.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 18, y: (bounds.height - 18) / 2, width: 3, height: 18),
                xRadius: 1.5,
                yRadius: 1.5
            ).fill()
        } else if isHovered {
            NSColor(white: 0.16, alpha: 1).setFill()
            bounds.fill()
        }

        let padLeft: CGFloat = 42

        // Status dot
        if !isLoading {
            let dotColor: NSColor = .systemGreen
            let dotSize: CGFloat = 6
            dotColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: padLeft - 12, y: (bounds.height - dotSize) / 2, width: dotSize, height: dotSize)).fill()
        }

        // "local"
        let nameFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let nameAttrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: AppTheme.textPrimary]
        ("local" as NSString).draw(at: NSPoint(x: padLeft, y: bounds.height / 2 + 1), withAttributes: nameAttrs)

        // Branch label: "main"
        let branchFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let branchAttrs: [NSAttributedString.Key: Any] = [.font: branchFont, .foregroundColor: AppTheme.textSecondary]
        let branch = getBranch()
        (branch as NSString).draw(at: NSPoint(x: padLeft, y: bounds.height / 2 - 13), withAttributes: branchAttrs)

        // Git stats (right side) — placeholder
        let statsFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        // Show diff stats if available
        let stats = getGitStats()
        if !stats.isEmpty {
            var x = bounds.width - 12
            for (text, color) in stats.reversed() {
                let attrs: [NSAttributedString.Key: Any] = [.font: statsFont, .foregroundColor: color]
                let w = (text as NSString).size(withAttributes: attrs).width
                x -= w + 6
                (text as NSString).draw(at: NSPoint(x: x, y: (bounds.height - 12) / 2), withAttributes: attrs)
            }
        }

        AppTheme.border.withAlphaComponent(0.8).setFill()
        NSRect(x: 24, y: 0, width: bounds.width - 36, height: 1).fill()
    }

    private func getBranch() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
        process.currentDirectoryURL = URL(fileURLWithPath: project.path)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "main"
        } catch { return "main" }
    }

    private func getGitStats() -> [(String, NSColor)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "--shortstat"]
        process.currentDirectoryURL = URL(fileURLWithPath: project.path)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            var result: [(String, NSColor)] = []
            // Parse "N files changed, N insertions(+), N deletions(-)"
            if let filesMatch = output.range(of: #"\d+ file"#, options: .regularExpression) {
                let num = output[filesMatch].split(separator: " ").first ?? "0"
                result.append(("\u{2191}\(num)", NSColor.systemYellow))
            }
            if let insMatch = output.range(of: #"\d+ insertion"#, options: .regularExpression) {
                let num = output[insMatch].split(separator: " ").first ?? "0"
                result.append(("+\(num)", NSColor.systemGreen))
            }
            if let delMatch = output.range(of: #"\d+ deletion"#, options: .regularExpression) {
                let num = output[delMatch].split(separator: " ").first ?? "0"
                result.append(("-\(num)", NSColor.systemRed))
            }
            return result
        } catch { return [] }
    }
}

// MARK: - Worktree workspace row

private class WorkspaceWorktreeRow: NSView {
    var onClick: ((WorkspaceItem) -> Void)?
    var onDelete: ((WorkspaceItem) -> Void)?
    var onOpenInEditor: ((WorkspaceItem) -> Void)?
    private let workspace: WorkspaceItem
    private let selected: Bool
    private let isLoading: Bool
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(workspace: WorkspaceItem, selected: Bool = false, isLoading: Bool = false) {
        self.workspace = workspace
        self.selected = selected
        self.isLoading = isLoading
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.15, alpha: 1).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 44).isActive = true
        if isLoading {
            let indicator = makeLoadingIndicator(fontSize: 11.5)
            addSubview(indicator)
            NSLayoutConstraint.activate([
                indicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 21),
                indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
                indicator.widthAnchor.constraint(equalToConstant: 10),
                indicator.heightAnchor.constraint(equalToConstant: 12),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { onClick?(workspace) }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Terminal", action: #selector(contextOpen), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let editorItem = NSMenuItem(title: "Open in Editor", action: #selector(contextOpenInEditor), keyEquivalent: "")
        editorItem.target = self
        menu.addItem(editorItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(title: "Delete Workspace...", action: #selector(contextDelete), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func contextOpen() { onClick?(workspace) }
    @objc private func contextOpenInEditor() { onOpenInEditor?(workspace) }
    @objc private func contextDelete() { onDelete?(workspace) }

    private func agentLabel() -> String {
        let loweredCommand = workspace.agentCommand.lowercased()
        if loweredCommand.contains("claude") { return "Claude" }
        if loweredCommand.contains("codex") { return "Codex" }
        if loweredCommand.contains("gemini") { return "Gemini" }
        if loweredCommand.contains("aider") { return "Aider" }
        if loweredCommand.contains("copilot") { return "Copilot" }

        let firstToken = workspace.agentCommand
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        if let firstToken, !firstToken.isEmpty {
            return firstToken.capitalized
        }

        return workspace.agentProvider.capitalized
    }

    private func makeTruncatingAttributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]
    }

    override func draw(_ dirtyRect: NSRect) {
        if selected {
            AppTheme.bgTertiary.setFill()
            bounds.fill()
            AppTheme.accent.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 18, y: (bounds.height - 18) / 2, width: 3, height: 18),
                xRadius: 1.5,
                yRadius: 1.5
            ).fill()
        } else if isHovered {
            NSColor(white: 0.16, alpha: 1).setFill()
            bounds.fill()
        }

        let padLeft: CGFloat = 42

        // Status dot
        if !isLoading {
            let dotColor: NSColor
            switch workspace.status {
            case .running: dotColor = .systemYellow
            case .idle: dotColor = .systemGreen
            case .completed: dotColor = .systemGray
            case .error: dotColor = .systemRed
            }
            let dotSize: CGFloat = 6
            dotColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: padLeft - 12, y: (bounds.height - dotSize) / 2,
                                         width: dotSize, height: dotSize)).fill()
        }

        // Agent badge on right
        let agentFont = NSFont.systemFont(ofSize: 9, weight: .medium)
        let agentColor = AgentPillButton.colorForProvider(workspace.agentProvider)
        let agentAttrs = makeTruncatingAttributes(font: agentFont, color: agentColor)
        let agentLabel = agentLabel()
        let agentPadding: CGFloat = 10
        let maxAgentWidth = min(84, bounds.width * 0.32)
        let agentTextWidth = ceil((agentLabel as NSString).size(withAttributes: agentAttrs).width)
        let agentWidth = min(maxAgentWidth, agentTextWidth)
        let agentRect = NSRect(
            x: bounds.width - agentPadding - agentWidth,
            y: (bounds.height - 12) / 2,
            width: max(0, agentWidth),
            height: 12
        )

        if agentRect.width > 0 {
            let agentAttrString = NSAttributedString(string: agentLabel, attributes: agentAttrs)
            agentAttrString.draw(with: agentRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }

        let contentMaxX = max(padLeft, agentRect.minX - 10)

        // Name
        let nameFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let nameAttrs = makeTruncatingAttributes(font: nameFont, color: AppTheme.textPrimary)
        let nameRect = NSRect(x: padLeft, y: bounds.height / 2 - 1, width: max(0, contentMaxX - padLeft), height: 14)
        let nameAttrString = NSAttributedString(string: workspace.name, attributes: nameAttrs)
        nameAttrString.draw(with: nameRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        // Branch
        let branchFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let branchAttrs = makeTruncatingAttributes(font: branchFont, color: AppTheme.textSecondary)
        let branchRect = NSRect(x: padLeft, y: bounds.height / 2 - 15, width: max(0, contentMaxX - padLeft), height: 12)
        let branchAttrString = NSAttributedString(string: workspace.branchName, attributes: branchAttrs)
        branchAttrString.draw(with: branchRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        AppTheme.border.withAlphaComponent(0.8).setFill()
        NSRect(x: 24, y: 0, width: bounds.width - 36, height: 1).fill()
    }
}

// Safe array subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
