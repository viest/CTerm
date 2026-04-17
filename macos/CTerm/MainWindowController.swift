import AppKit
import UserNotifications

private class InvisibleDividerSplitView: NSSplitView {
    override var dividerColor: NSColor { .clear }
}

class MainWindowController: NSWindowController {
    private typealias TerminalTabState = (id: String, title: String, tree: SplitNode)

    private struct TerminalGroupState {
        var tabs: [TerminalTabState] = []
        var focusedPaneId: String?
        var selectedTabIndex: Int = 0
    }

    private struct PaneReference {
        let paneId: String
        let tabId: String
        let scope: TerminalScope
        let view: GhosttyTerminalView
    }

    /// A pane is considered "active" (spinner on) if it has any entry in
    /// `paneAgentStates`. Absence from the map means idle. This is the only
    /// source of truth for running-state UI — mutated edge-triggered by
    /// agent hook events and explicit user-stop intent (^C).
    private enum PaneAgentState {
        case running
        case awaitingPermission
    }

    private enum TerminalScope: Equatable {
        case primary
        case project(UUID)
        case workspace(UUID)

        var projectId: UUID? {
            switch self {
            case .project(let projectId):
                return projectId
            default:
                return nil
            }
        }

        var workspaceId: UUID? {
            switch self {
            case .primary, .project:
                return nil
            case .workspace(let workspaceId):
                return workspaceId
            }
        }
    }

    private static let leftSidebarMinWidth: CGFloat = 180
    private static let leftSidebarMaxWidth: CGFloat = 400
    private static let rightSidebarMinWidth: CGFloat = 220
    private static let gitRefreshInterval: TimeInterval = 5
    private static let usageMonitorInitialRefreshDelay: TimeInterval = 15

    private var mainSplitView: NSSplitView!
    private var projectSidebar: ProjectSidebar!
    private var centerContainer: NSView!
    private var presetBar: PresetBarView!
    private var tabBar: TerminalTabBar!
    private var terminalContentView: NSView!
    private var statusBar: StatusBarView!
    private var settingsWindow: SettingsWindow?
    private var tokenTracker: TokenTrackerBridge!
    private var usageMonitor: UsageMonitor!
    private var gitRefreshTimer: Timer?
    private var usageMonitorTimer: Timer?
    private var performanceMonitor: PerformanceMonitor!
    private var performanceMonitorTimer: Timer?

    // Per-tab split trees (replaces flat terminalViews array)
    private var tabs: [TerminalTabState] = []
    private var tabContainers: [String: SplitContainerView] = [:]  // tabId -> rendered view
    private var focusedPaneId: String?
    private var activeTerminalScope: TerminalScope = .primary
    private var primaryTerminalState = TerminalGroupState()
    private var projectTerminalStates: [UUID: TerminalGroupState] = [:]
    private var workspaceTerminalStates: [UUID: TerminalGroupState] = [:]
    private var pinnedTitleTabIds: Set<String> = []
    private var paneWorkspaceMap: [String: UUID] = [:]  // paneId -> workspace.id
    private var paneAgentStates: [String: PaneAgentState] = [:]
    private var currentTabIndex: Int { tabBar?.selectedIndex ?? 0 }

    private var searchBar: TerminalSearchBar?
    private var searchBarTopConstraint: NSLayoutConstraint?

    private var changesPanel: ChangesPanel!
    private var fileBrowser: FileBrowserView!
    private var portManager: PortManagerView!
    private var rightSidebarContainer: NSView!
    private var rightSidebarSegment: NSSegmentedControl!
    private var rightSidebarWidthConstraint: NSLayoutConstraint!
    private var rightSidebarVisible = true
    private var rightSidebarWidth: CGFloat = 300
    private var rightSidebarAnimating = false
    private var rightSidebarAnimationGeneration = 0

    private var quickOpenPanel: QuickOpenPanel?
    private var searchPanel: SearchPanel?

    private var leftSidebarVisible = true
    private var leftSidebarWidth: CGFloat = 250

    private var projects: [ProjectItem] = []
    private var presets: [AgentPresetItem] = []
    private var projectPresets: [AgentPresetItem] = []
    private var workspaces: [WorkspaceItem] = []
    private var currentProject: ProjectItem?
    private var newWorkspaceSheet: NewWorkspaceSheet?
    private var renameTabSheet: RenameTabSheet?
    private var deleteWorkspaceSheet: DeleteWorkspaceSheet?

    private let dataDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CTerm")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    deinit {
        gitRefreshTimer?.invalidate()
        usageMonitorTimer?.invalidate()
        performanceMonitorTimer?.invalidate()
        SettingsManager.shared.onSettingsChanged = nil
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CTerm"
        window.center()
        window.minSize = NSSize(width: 800, height: 500)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false

        // Reposition traffic lights to center vertically in the 34px agents bar
        let trafficLightY: CGFloat = 9
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            if let btn = window.standardWindowButton(buttonType) {
                btn.translatesAutoresizingMaskIntoConstraints = false
                if let sv = btn.superview {
                    NSLayoutConstraint.activate([
                        btn.topAnchor.constraint(equalTo: sv.topAnchor, constant: trafficLightY),
                    ])
                }
            }
        }
        window.backgroundColor = AppTheme.bgPrimary
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false

        self.init(window: window)
        window.delegate = self

        tokenTracker = TokenTrackerBridge()
        tokenTracker.onUsageUpdated = { [weak self] usageMap in
            self?.statusBar.updateAllAgentUsage(usageMap)
        }
        usageMonitor = UsageMonitor()
        usageMonitor.onSnapshotUpdated = { [weak self] snapshots in
            self?.statusBar.updateProviderMonitoring(snapshots)
        }
        performanceMonitor = PerformanceMonitor()
        performanceMonitor.onSnapshotUpdated = { [weak self] snapshot in
            self?.statusBar.updatePerformance(snapshot)
        }

        loadData()
        setupUI()
        updateGitRefreshTimer()
        observeSettingsChanges()
        AgentHookInstaller.install()
        AgentHookServer.shared.onEvent = { [weak self] cb in
            self?.handleAgentHookEvent(cb)
        }
        AgentHookServer.shared.start()
        startUsageMonitoring()
        startPerformanceMonitoring()
        loadSavedLayout()

        // Restore the most recently opened project context and expand it in the sidebar.
        if !projects.isEmpty {
            activateProject(projects[0])
            projectSidebar.expandProject(at: 0)
        } else if rightSidebarVisible {
            let path = NSHomeDirectory()
            changesPanel.currentProjectPath = path
            fileBrowser.projectPath = path
        }

        createInitialTerminal()
    }

    private func observeSettingsChanges() {
        applyTerminalSettingsToAllPanes()
        SettingsManager.shared.onSettingsChanged = { [weak self] in
            self?.applyTerminalSettingsToAllPanes()
        }
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = AppTheme.bgPrimary.cgColor

        let outerStack = NSStackView()
        outerStack.orientation = .vertical
        outerStack.spacing = 0
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(outerStack)

        // Preset bar
        presetBar = PresetBarView()
        presetBar.delegate = self
        refreshPresetBarPresets()
        outerStack.addArrangedSubview(presetBar)
        updatePresetBarTrafficLightSpacing()

        // Main split view (left sidebar | center)
        mainSplitView = InvisibleDividerSplitView()
        mainSplitView.isVertical = true
        mainSplitView.dividerStyle = .thin
        mainSplitView.delegate = self
        outerStack.addArrangedSubview(mainSplitView)

        // Left sidebar
        projectSidebar = ProjectSidebar(frame: NSRect(x: 0, y: 0, width: leftSidebarWidth, height: 600))
        projectSidebar.delegate = self
        projectSidebar.setProjects(projects)
        projectSidebar.setWorkspaces(workspaces)
        mainSplitView.addSubview(projectSidebar)

        // Center: toolbar + terminal content
        centerContainer = NSView()
        centerContainer.wantsLayer = true
        centerContainer.layer?.backgroundColor = AppTheme.bgPrimary.cgColor
        mainSplitView.addSubview(centerContainer)

        // Wire sidebar toggle buttons in preset bar
        presetBar.sidebarToggle.target = self
        presetBar.sidebarToggle.action = #selector(toggleLeftSidebar(_:))
        presetBar.settingsButton.target = self
        presetBar.settingsButton.action = #selector(openSettings(_:))
        presetBar.rightSidebarToggle.target = self
        presetBar.rightSidebarToggle.action = #selector(toggleRightSidebar(_:))

        // Tab bar
        tabBar = TerminalTabBar()
        tabBar.delegate = self
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        centerContainer.addSubview(tabBar)

        // Terminal content area
        terminalContentView = NSView()
        terminalContentView.wantsLayer = true
        terminalContentView.layer?.backgroundColor = GhosttyTerminalView.defaultBackgroundColor.cgColor
        terminalContentView.layer?.masksToBounds = true
        terminalContentView.translatesAutoresizingMaskIntoConstraints = false
        centerContainer.addSubview(terminalContentView)

        // Right sidebar container (hidden by default, shown via Cmd+L)
        rightSidebarContainer = NSView()
        rightSidebarContainer.wantsLayer = true
        rightSidebarContainer.layer?.backgroundColor = NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1).cgColor
        rightSidebarContainer.translatesAutoresizingMaskIntoConstraints = false

        rightSidebarContainer.isHidden = !rightSidebarVisible
        centerContainer.addSubview(rightSidebarContainer)

        // Tab buttons — custom styled to match left sidebar
        let tabContainer = NSView()
        tabContainer.translatesAutoresizingMaskIntoConstraints = false
        rightSidebarContainer.addSubview(tabContainer)

        let changesTab = makeSidebarTab("Changes", tag: 0, selected: true)
        let filesTab = makeSidebarTab("Files", tag: 1, selected: false)
        tabContainer.addSubview(changesTab)
        tabContainer.addSubview(filesTab)

        let refreshBtn = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")!, target: self, action: #selector(refreshRightSidebar))
        refreshBtn.bezelStyle = .inline
        refreshBtn.isBordered = false
        refreshBtn.contentTintColor = AppTheme.textSecondary
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        tabContainer.addSubview(refreshBtn)

        rightSidebarSegment = NSSegmentedControl() // keep for reference but hidden
        rightSidebarSegment.isHidden = true

        NSLayoutConstraint.activate([
            tabContainer.heightAnchor.constraint(equalToConstant: 28),
            changesTab.leadingAnchor.constraint(equalTo: tabContainer.leadingAnchor, constant: 10),
            changesTab.centerYAnchor.constraint(equalTo: tabContainer.centerYAnchor),
            filesTab.leadingAnchor.constraint(equalTo: changesTab.trailingAnchor, constant: 2),
            filesTab.centerYAnchor.constraint(equalTo: tabContainer.centerYAnchor),
            refreshBtn.trailingAnchor.constraint(equalTo: tabContainer.trailingAnchor, constant: -8),
            refreshBtn.centerYAnchor.constraint(equalTo: tabContainer.centerYAnchor),
            refreshBtn.widthAnchor.constraint(equalToConstant: 22),
            refreshBtn.heightAnchor.constraint(equalToConstant: 22),
        ])

        changesPanel = ChangesPanel()
        changesPanel.onGitRepositoryMutated = { [weak self] in
            self?.projectSidebar.refreshGitStatusRows()
        }
        changesPanel.translatesAutoresizingMaskIntoConstraints = false
        rightSidebarContainer.addSubview(changesPanel)

        fileBrowser = FileBrowserView()
        fileBrowser.translatesAutoresizingMaskIntoConstraints = false
        fileBrowser.isHidden = true
        rightSidebarContainer.addSubview(fileBrowser)

        portManager = PortManagerView()
        // Port manager is only shown when .cterm/ports.json exists — don't add to layout by default

        // Right sidebar internal layout (auto-layout is fine here — NOT inside NSSplitView)
        NSLayoutConstraint.activate([
            tabContainer.topAnchor.constraint(equalTo: rightSidebarContainer.topAnchor, constant: 4),
            tabContainer.leadingAnchor.constraint(equalTo: rightSidebarContainer.leadingAnchor),
            tabContainer.trailingAnchor.constraint(equalTo: rightSidebarContainer.trailingAnchor),

            changesPanel.topAnchor.constraint(equalTo: tabContainer.bottomAnchor, constant: 2),
            changesPanel.leadingAnchor.constraint(equalTo: rightSidebarContainer.leadingAnchor),
            changesPanel.trailingAnchor.constraint(equalTo: rightSidebarContainer.trailingAnchor),
            changesPanel.bottomAnchor.constraint(equalTo: rightSidebarContainer.bottomAnchor),

            fileBrowser.topAnchor.constraint(equalTo: tabContainer.bottomAnchor, constant: 2),
            fileBrowser.leadingAnchor.constraint(equalTo: rightSidebarContainer.leadingAnchor),
            fileBrowser.trailingAnchor.constraint(equalTo: rightSidebarContainer.trailingAnchor),
            fileBrowser.bottomAnchor.constraint(equalTo: rightSidebarContainer.bottomAnchor),
        ])

        // Right sidebar width constraint (stored as property for easy toggle)
        rightSidebarWidthConstraint = rightSidebarContainer.widthAnchor.constraint(equalToConstant: rightSidebarVisible ? rightSidebarWidth : 0)
        rightSidebarWidthConstraint.isActive = true

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: centerContainer.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor),

            terminalContentView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            terminalContentView.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
            terminalContentView.trailingAnchor.constraint(equalTo: rightSidebarContainer.leadingAnchor),
            terminalContentView.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor),

            rightSidebarContainer.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            rightSidebarContainer.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor),
            rightSidebarContainer.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor),
        ])

        // Status bar
        statusBar = StatusBarView()
        statusBar.updateAllAgentUsage(tokenTracker.providerUsage)
        outerStack.addArrangedSubview(statusBar)

        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            outerStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        DispatchQueue.main.async { [self] in
            updateSidebarVisibility(animated: false)
        }

        updateGitBranch()
    }

    private func startUsageMonitoring() {
        let cachedSnapshots = usageMonitor.loadCachedSnapshots()
        if !cachedSnapshots.isEmpty {
            statusBar.updateProviderMonitoring(cachedSnapshots)
        }

        usageMonitorTimer?.invalidate()
        usageMonitorTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.usageMonitor.refresh()
        }
        usageMonitorTimer?.tolerance = 5
        usageMonitorTimer?.fireDate = Date().addingTimeInterval(Self.usageMonitorInitialRefreshDelay)
    }

    private func startPerformanceMonitoring() {
        performanceMonitor.refresh()
        performanceMonitorTimer?.invalidate()
        performanceMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.performanceMonitor.refresh()
        }
        performanceMonitorTimer?.tolerance = 0.5
    }

    // MARK: - Terminal Management

    private func createInitialTerminal() {
        // Attempt to restore previous session
        if let session = SessionPersistence.shared.loadSession() {
            restoreSession(session)
            SessionPersistence.shared.clearSession()
            if !tabs.isEmpty {
                return
            }
        }

        switch activeTerminalScope {
        case .project(let projectId):
            if let project = projects.first(where: { $0.id == projectId }) {
                openProjectTerminal(project)
                return
            }
        case .workspace(let workspaceId):
            if let workspace = workspaces.first(where: { $0.id == workspaceId }) {
                openWorkspaceTerminal(workspace)
                return
            }
        case .primary:
            break
        }

        addTerminalTab(title: "Terminal", workingDir: defaultWorkingDirectoryForActiveScope())
    }

    private func applyTerminalSettingsToAllPanes() {
        let settings = SettingsManager.shared.settings
        let backgroundColor = GhosttyTerminalView.backgroundColor(for: settings).cgColor

        terminalContentView?.layer?.backgroundColor = backgroundColor
        GhosttyTerminalView.applySharedSettings(settings)

        for (_, _, tree) in allTerminalTabs() {
            for leaf in tree.allLeaves() {
                leaf.view.applyTerminalSettings(settings)
            }
        }

        for container in tabContainers.values {
            container.applyTerminalThemeBackground(settings)
        }
    }

    private func restoreSession(_ session: SessionPersistence.SessionState) {
        paneWorkspaceMap.removeAll()
        pinnedTitleTabIds.removeAll()
        primaryTerminalState = restoreTerminalGroup(from: session.primaryGroup)

        projectTerminalStates.removeAll()
        for group in session.projectGroups {
            guard let projectId = group.projectId else { continue }
            projectTerminalStates[projectId] = restoreTerminalGroup(from: group)
        }

        workspaceTerminalStates.removeAll()
        for group in session.workspaceGroups {
            guard let workspaceId = group.workspaceId else { continue }
            workspaceTerminalStates[workspaceId] = restoreTerminalGroup(from: group)
        }

        if let activeWorkspaceId = session.activeWorkspaceId,
           workspaceTerminalStates[activeWorkspaceId] != nil {
            activeTerminalScope = .workspace(activeWorkspaceId)
        } else if let activeProjectId = session.activeProjectId,
                  projectTerminalStates[activeProjectId] != nil {
            activeTerminalScope = .project(activeProjectId)
        } else {
            activeTerminalScope = .primary
        }

        syncSidebarSelection()
        applyTerminalGroupState(terminalGroupState(for: activeTerminalScope))
    }

    private func restoreTerminalGroup(from group: SessionPersistence.GroupState) -> TerminalGroupState {
        var restoredTabs: [TerminalTabState] = []
        let scope = terminalScope(for: group)

        for tabState in group.tabs {
            let paneStatesById = Dictionary(uniqueKeysWithValues: tabState.panes.map { ($0.paneId, $0) })
            let tree = buildRestoredSplitTree(
                from: tabState.treeSnapshot,
                paneStatesById: paneStatesById,
                fallbackPane: tabState.panes.first,
                scope: scope
            )
            restoredTabs.append((id: tabState.tabId, title: tabState.title, tree: tree))
            pinnedTitleTabIds.insert(tabState.tabId)
        }

        return TerminalGroupState(
            tabs: restoredTabs,
            focusedPaneId: group.focusedPaneId,
            selectedTabIndex: min(max(group.selectedTabIndex, 0), max(restoredTabs.count - 1, 0))
        )
    }

    private func terminalScope(for group: SessionPersistence.GroupState) -> TerminalScope {
        if let workspaceId = group.workspaceId {
            return .workspace(workspaceId)
        }
        if let projectId = group.projectId {
            return .project(projectId)
        }
        return .primary
    }

    private func buildRestoredSplitTree(from snapshot: SplitTreeSnapshot,
                                        paneStatesById: [String: SessionPersistence.PaneState],
                                        fallbackPane: SessionPersistence.PaneState?,
                                        scope: TerminalScope) -> SplitNode {
        switch snapshot.type {
        case "leaf":
            return makeRestoredLeaf(
                paneId: snapshot.paneId ?? snapshot.id,
                paneStatesById: paneStatesById,
                fallbackPane: fallbackPane,
                scope: scope
            )

        case "split":
            guard let firstSnapshot = snapshot.first, let secondSnapshot = snapshot.second else {
                return makeRestoredLeaf(
                    paneId: snapshot.paneId ?? snapshot.id,
                    paneStatesById: paneStatesById,
                    fallbackPane: fallbackPane,
                    scope: scope
                )
            }

            let direction: SplitDirection = snapshot.direction == "vertical" ? .vertical : .horizontal
            let ratio = min(max(snapshot.ratio ?? 0.5, 0.1), 0.9)
            let first = buildRestoredSplitTree(
                from: firstSnapshot,
                paneStatesById: paneStatesById,
                fallbackPane: fallbackPane,
                scope: scope
            )
            let second = buildRestoredSplitTree(
                from: secondSnapshot,
                paneStatesById: paneStatesById,
                fallbackPane: fallbackPane,
                scope: scope
            )

            return .split(
                id: snapshot.id,
                direction: direction,
                first: first,
                second: second,
                ratio: ratio
            )

        default:
            return makeRestoredLeaf(
                paneId: snapshot.paneId ?? snapshot.id,
                paneStatesById: paneStatesById,
                fallbackPane: fallbackPane,
                scope: scope
            )
        }
    }

    private func makeRestoredLeaf(paneId: String?,
                                  paneStatesById: [String: SessionPersistence.PaneState],
                                  fallbackPane: SessionPersistence.PaneState?,
                                  scope: TerminalScope) -> SplitNode {
        let resolvedPaneId = (paneId?.isEmpty == false ? paneId! : fallbackPane?.paneId) ?? UUID().uuidString
        let paneState = paneStatesById[resolvedPaneId] ?? fallbackPane
        switch scope {
        case .workspace(let workspaceId):
            paneWorkspaceMap[resolvedPaneId] = workspaceId
        case .primary:
            if let workspace = workspaceContaining(path: paneState?.cwd) {
                paneWorkspaceMap[resolvedPaneId] = workspace.id
            }
        case .project:
            break
        }
        let env = buildPaneEnv(paneId: resolvedPaneId, tabId: resolvedPaneId, provider: "")
        let termView = makeTerminalView(
            command: paneState?.command ?? "/bin/zsh",
            workingDir: paneState?.cwd,
            initialInput: paneState?.initialInput,
            extraEnv: env
        )
        return .leaf(id: resolvedPaneId, view: termView)
    }

    private func normalizedTerminalLaunch(command: String, initialInput: String?) -> (command: String, initialInput: String?) {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedInput = (initialInput?.isEmpty == false) ? initialInput : nil

        guard !trimmedCommand.isEmpty else {
            return ("/bin/zsh", normalizedInput)
        }
        guard normalizedInput == nil else {
            return (trimmedCommand, normalizedInput)
        }
        if trimmedCommand.contains(where: { $0.isWhitespace }) {
            return ("/bin/zsh", trimmedCommand + "\n")
        }
        return (trimmedCommand, nil)
    }

    private func makeTerminalView(
        command: String = "/bin/zsh",
        workingDir: String? = nil,
        initialInput: String? = nil,
        extraEnv: [String: String] = [:]
    ) -> GhosttyTerminalView {
        let launch = normalizedTerminalLaunch(command: command, initialInput: initialInput)
        let termView = GhosttyTerminalView(
            frame: terminalContentView.bounds,
            command: launch.command,
            workingDir: workingDir ?? NSHomeDirectory(),
            initialInput: launch.initialInput,
            extraEnv: extraEnv
        )
        termView.tokenTracker = tokenTracker
        termView.delegate = self
        termView.onTitleChanged = { [weak self] title in
            self?.handleTerminalTitleChanged(view: termView, title: title)
        }
        termView.onPaneClicked = { [weak self] view in
            self?.handlePaneClicked(view)
        }
        termView.onSearchTotal = { [weak self] total in
            guard let self, let bar = self.searchBar else { return }
            bar.updateMatchInfo(total: total, selected: 0)
        }
        termView.onSearchSelected = { [weak self] selected in
            guard let self, let bar = self.searchBar else { return }
            bar.updateMatchInfo(total: -1, selected: selected)
        }
        termView.onCommandFinished = { [weak self] exitCode, duration in
            self?.handleCommandFinished(view: termView, exitCode: exitCode, duration: duration)
        }
        termView.onTerminalExit = { [weak self] in
            self?.handleTerminalExit(view: termView)
        }
        termView.onUserInterrupt = { [weak self] in
            self?.handleUserInterrupt(view: termView)
        }
        return termView
    }

    /// ^C in a pane is an explicit user-stop intent. We treat it as
    /// authoritative: the pane transitions to idle immediately. If the
    /// agent ignores the interrupt and resumes work, the next hook event
    /// will re-activate the pane.
    private func handleUserInterrupt(view: GhosttyTerminalView) {
        guard let location = findViewLocation(view) else { return }
        deactivatePaneAgentState(paneId: location.paneId, workspaceStatus: .idle)
    }

    @discardableResult
    private func addTerminalTab(
        title: String,
        command: String = "/bin/zsh",
        workingDir: String? = nil,
        initialInput: String? = nil,
        providerHint: String = "",
        pinTitle: Bool = false
    ) -> (paneId: String, view: GhosttyTerminalView) {
        let id = UUID().uuidString
        let env = buildPaneEnv(paneId: id, tabId: id, provider: providerHint)
        let termView = makeTerminalView(
            command: command,
            workingDir: workingDir,
            initialInput: initialInput,
            extraEnv: env
        )
        let tree = SplitNode.leaf(id: id, view: termView)

        tabs.append((id: id, title: title, tree: tree))
        // Callers that launch a specific agent (preset bar, workspace
        // setup) pass a meaningful title and ask us to pin it, so shell
        // OSC title sequences from the running agent don't overwrite
        // "Claude Code" with e.g. the transient cwd label.
        if pinTitle {
            pinnedTitleTabIds.insert(id)
        } else {
            pinnedTitleTabIds.remove(id)
        }
        tabBar.addTab(TabItem(id: id, title: title))

        showTab(at: tabs.count - 1)
        focusedPaneId = id
        trackPaneForActiveWorkspace(id)
        return (id, termView)
    }

    private func openProjectTerminal(_ project: ProjectItem) {
        addTerminalTab(title: project.name, workingDir: project.path)
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func projectContaining(path: String?) -> ProjectItem? {
        guard let path, !path.isEmpty else { return nil }

        let normalizedCandidate = normalizedPath(path)
        return projects
            .compactMap { project -> (project: ProjectItem, rootLength: Int)? in
                let projectRoot = normalizedPath(project.path)
                guard normalizedCandidate == projectRoot || normalizedCandidate.hasPrefix(projectRoot + "/") else {
                    return nil
                }
                return (project, projectRoot.count)
            }
            .max(by: { $0.rootLength < $1.rootLength })?
            .project
    }

    private func workspaceContaining(path: String?) -> WorkspaceItem? {
        guard let path, !path.isEmpty else { return nil }

        let normalizedCandidate = normalizedPath(path)
        return workspaces.first { workspace in
            let workspaceRoot = normalizedPath(workspace.worktreePath)
            return normalizedCandidate == workspaceRoot || normalizedCandidate.hasPrefix(workspaceRoot + "/")
        }
    }

    private func focusedTerminalView() -> GhosttyTerminalView? {
        guard let focusedPaneId else { return nil }

        for tab in tabs {
            if let view = tab.tree.findLeaf(focusedPaneId) {
                return view
            }
        }
        return nil
    }

    private func resolvedRightSidebarPath() -> String? {
        switch activeTerminalScope {
        case .project(let projectId):
            if let path = projects.first(where: { $0.id == projectId })?.path {
                return path
            }
        case .workspace(let workspaceId):
            if let path = workspaces.first(where: { $0.id == workspaceId })?.worktreePath {
                return path
            }
        case .primary:
            break
        }

        let focusedView = focusedTerminalView()
        let focusedPath = focusedView?.currentWorkingDir ?? focusedView?.launchWorkingDir
        if let workspace = workspaceContaining(path: focusedPath) {
            return workspace.worktreePath
        }
        if let project = projectContaining(path: focusedPath) {
            return project.path
        }
        return currentProject?.path
    }

    private func openWorkspaceTerminal(_ workspace: WorkspaceItem) {
        addTerminalTab(title: workspace.name, workingDir: workspace.worktreePath)
    }

    private func setWorkspaceStatus(_ workspaceId: UUID, to status: WorkspaceItem.WorkspaceStatus) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        workspaces[idx].status = status
        saveWorkspaces()
        projectSidebar.setWorkspaces(workspaces)
    }

    private func allPaneReferences() -> [PaneReference] {
        var references: [PaneReference] = []

        func appendTabs(_ groupTabs: [TerminalTabState], scope: TerminalScope) {
            guard scope != .primary else { return }
            for tab in groupTabs {
                for leaf in tab.tree.allLeaves() {
                    references.append(
                        PaneReference(
                            paneId: leaf.id,
                            tabId: tab.id,
                            scope: scope,
                            view: leaf.view
                        )
                    )
                }
            }
        }

        appendTabs(tabs, scope: activeTerminalScope)

        if activeTerminalScope != .primary {
            appendTabs(primaryTerminalState.tabs, scope: .primary)
        }

        for (projectId, state) in projectTerminalStates where activeTerminalScope != .project(projectId) {
            appendTabs(state.tabs, scope: .project(projectId))
        }

        for (workspaceId, state) in workspaceTerminalStates where activeTerminalScope != .workspace(workspaceId) {
            appendTabs(state.tabs, scope: .workspace(workspaceId))
        }

        return references
    }

    // MARK: - Agent pane activity state
    //
    // Design: `paneAgentStates` is the single source of truth for whether a
    // pane is "running an agent task." Entries are added/removed edge-
    // triggered by agent hook events (Start/Stop/PermissionRequest) and by
    // explicit user-stop intent (^C). All UI indicators — tab spinner,
    // sidebar dots, workspace status transitions — derive from this map on
    // each mutation; there is no polling, no secondary state to reconcile.

    private func refreshSidebarActivityIndicators() {
        let panesById = Dictionary(uniqueKeysWithValues: allPaneReferences().map { ($0.paneId, $0) })
        var localProjectIds: Set<UUID> = []
        var workspaceIds: Set<UUID> = []
        var runningTabIds: Set<String> = []

        for paneId in paneAgentStates.keys {
            guard let pane = panesById[paneId] else { continue }
            runningTabIds.insert(pane.tabId)
            switch pane.scope {
            case .project(let projectId):
                localProjectIds.insert(projectId)
            case .workspace(let workspaceId):
                workspaceIds.insert(workspaceId)
            case .primary:
                break
            }
        }

        projectSidebar.setRunningActivity(
            localProjectIds: localProjectIds,
            workspaceIds: workspaceIds
        )
        tabBar.setRunningTabs(runningTabIds)
    }

    /// Marks a pane as having an active agent task. Idempotent; repeated
    /// calls just refresh the state and update the workspace indicator to
    /// `.running` on the first activation.
    private func activatePaneAgentState(paneId: String, state: PaneAgentState) {
        let wasInactive = paneAgentStates[paneId] == nil
        paneAgentStates[paneId] = state
        if wasInactive, case .workspace(let wsId) = scope(forPaneId: paneId) ?? .primary {
            setWorkspaceStatus(wsId, to: .running)
        }
        refreshSidebarActivityIndicators()
    }

    /// Marks a pane as idle. If this was the last active pane in its
    /// workspace, transitions the workspace status to `workspaceStatus`
    /// (typically `.completed` / `.error` for natural stops, `.idle` for
    /// user-cancelled or lifecycle teardown). No-op if the pane was not
    /// active.
    @discardableResult
    private func deactivatePaneAgentState(paneId: String, workspaceStatus: WorkspaceItem.WorkspaceStatus = .idle) -> Bool {
        guard paneAgentStates.removeValue(forKey: paneId) != nil else {
            return false
        }
        if case .workspace(let wsId) = scope(forPaneId: paneId) ?? .primary {
            let hasOtherActiveInWorkspace = paneAgentStates.keys.contains { otherId in
                scope(forPaneId: otherId) == .workspace(wsId)
            }
            if !hasOtherActiveInWorkspace {
                setWorkspaceStatus(wsId, to: workspaceStatus)
            }
        }
        refreshSidebarActivityIndicators()
        return true
    }

    // MARK: - Agent hook integration

    /// Env vars injected into every CTerm-spawned shell, used by the notify-hook
    /// script to identify which pane an agent lifecycle event belongs to.
    private func buildPaneEnv(paneId: String, tabId: String, provider: String) -> [String: String] {
        var env: [String: String] = [
            "CTERM_PANE_ID": paneId,
            "CTERM_TAB_ID": tabId,
            "CTERM_HOME_DIR": AgentHookLayout.homeDir.path,
            "CTERM_HOOK_VERSION": AgentHookLayout.version
        ]
        let port = AgentHookServer.shared.port
        if port != 0 {
            env["CTERM_PORT"] = String(port)
        }
        switch activeTerminalScope {
        case .project(let id):
            env["CTERM_PROJECT_ID"] = id.uuidString
        case .workspace(let id):
            env["CTERM_WORKSPACE_ID"] = id.uuidString
            if let ws = workspaces.first(where: { $0.id == id }) {
                env["CTERM_PROJECT_ID"] = ws.projectId.uuidString
            }
        case .primary:
            break
        }
        if !provider.isEmpty {
            env["CTERM_PROVIDER"] = provider
        }
        return env
    }

    /// Agent hooks are the authoritative driver of pane activity state.
    /// Each event maps directly to a state transition; no counters, no
    /// polling, no reconciliation with secondary sources.
    private func handleAgentHookEvent(_ cb: AgentHookCallback) {
        guard scope(forPaneId: cb.paneId) != nil else { return }
        switch cb.eventType {
        case .start:
            activatePaneAgentState(paneId: cb.paneId, state: .running)
        case .permissionRequest:
            activatePaneAgentState(paneId: cb.paneId, state: .awaitingPermission)
        case .stop:
            deactivatePaneAgentState(paneId: cb.paneId, workspaceStatus: .completed)
        }
    }

    private func scope(forPaneId paneId: String) -> TerminalScope? {
        for pane in allPaneReferences() where pane.paneId == paneId {
            return pane.scope
        }
        return nil
    }

    private func canCreateTerminalInActiveScope() -> Bool {
        switch activeTerminalScope {
        case .project, .workspace:
            return true
        case .primary:
            return currentProject == nil
        }
    }

    private func defaultWorkingDirectoryForActiveScope() -> String? {
        switch activeTerminalScope {
        case .project(let projectId):
            return projects.first(where: { $0.id == projectId })?.path
        case .workspace(let workspaceId):
            return workspaces.first(where: { $0.id == workspaceId })?.worktreePath
        case .primary:
            return currentProject?.path
        }
    }

    private func currentVisibleSelectedTabIndex() -> Int {
        guard !tabs.isEmpty else { return 0 }
        return min(max(tabBar?.selectedIndex ?? 0, 0), tabs.count - 1)
    }

    private func currentTerminalGroupState() -> TerminalGroupState {
        TerminalGroupState(
            tabs: tabs,
            focusedPaneId: focusedPaneId,
            selectedTabIndex: currentVisibleSelectedTabIndex()
        )
    }

    private func terminalGroupState(for scope: TerminalScope) -> TerminalGroupState {
        switch scope {
        case .primary:
            return primaryTerminalState
        case .project(let projectId):
            return projectTerminalStates[projectId] ?? TerminalGroupState()
        case .workspace(let workspaceId):
            return workspaceTerminalStates[workspaceId] ?? TerminalGroupState()
        }
    }

    private func storeTerminalGroupState(_ state: TerminalGroupState, for scope: TerminalScope) {
        switch scope {
        case .primary:
            primaryTerminalState = state
        case .project(let projectId):
            projectTerminalStates[projectId] = state
        case .workspace(let workspaceId):
            workspaceTerminalStates[workspaceId] = state
        }
    }

    private func persistActiveTerminalGroupState() {
        storeTerminalGroupState(currentTerminalGroupState(), for: activeTerminalScope)
    }

    private func clearVisibleTerminalUI() {
        searchBar?.removeFromSuperview()
        searchBar = nil
        for subview in terminalContentView.subviews {
            subview.removeFromSuperview()
        }
        tabContainers.removeAll()
    }

    private func applyTerminalGroupState(_ state: TerminalGroupState) {
        clearVisibleTerminalUI()
        tabs = state.tabs
        focusedPaneId = state.focusedPaneId

        let selectedIndex = min(max(state.selectedTabIndex, 0), max(tabs.count - 1, 0))
        tabBar.setTabs(
            tabs.map { TabItem(id: $0.id, title: $0.title) },
            selectedIndex: selectedIndex
        )

        if !tabs.isEmpty {
            showTab(at: selectedIndex)
        }
        refreshSidebarActivityIndicators()
    }

    private func switchTerminalScope(to scope: TerminalScope) {
        guard activeTerminalScope != scope else { return }
        persistActiveTerminalGroupState()
        activeTerminalScope = scope
        syncSidebarSelection()
        applyTerminalGroupState(terminalGroupState(for: scope))
    }

    private func syncSidebarSelection() {
        guard let projectSidebar else { return }

        switch activeTerminalScope {
        case .project(let projectId):
            projectSidebar.setActiveSelection(.local(projectId))
        case .workspace(let workspaceId):
            projectSidebar.setActiveSelection(.workspace(workspaceId))
        case .primary:
            projectSidebar.setActiveSelection(.none)
        }
    }

    private func allTerminalTabs() -> [TerminalTabState] {
        var result = tabs

        if activeTerminalScope != .primary {
            result.append(contentsOf: primaryTerminalState.tabs)
        }

        for (projectId, state) in projectTerminalStates where activeTerminalScope != .project(projectId) {
            result.append(contentsOf: state.tabs)
        }

        for (workspaceId, state) in workspaceTerminalStates where activeTerminalScope != .workspace(workspaceId) {
            result.append(contentsOf: state.tabs)
        }

        return result
    }

    private func trackPaneForActiveWorkspace(_ paneId: String) {
        guard case .workspace(let workspaceId) = activeTerminalScope else { return }
        paneWorkspaceMap[paneId] = workspaceId
    }

    private func findViewLocation(_ view: GhosttyTerminalView) -> (scope: TerminalScope, tabIndex: Int, paneId: String)? {
        for (tabIndex, tab) in tabs.enumerated() {
            if let leaf = tab.tree.allLeaves().first(where: { $0.view === view }) {
                return (activeTerminalScope, tabIndex, leaf.id)
            }
        }

        if activeTerminalScope != .primary {
            for (tabIndex, tab) in primaryTerminalState.tabs.enumerated() {
                if let leaf = tab.tree.allLeaves().first(where: { $0.view === view }) {
                    return (.primary, tabIndex, leaf.id)
                }
            }
        }

        for (projectId, state) in projectTerminalStates where activeTerminalScope != .project(projectId) {
            for (tabIndex, tab) in state.tabs.enumerated() {
                if let leaf = tab.tree.allLeaves().first(where: { $0.view === view }) {
                    return (.project(projectId), tabIndex, leaf.id)
                }
            }
        }

        for (workspaceId, state) in workspaceTerminalStates where activeTerminalScope != .workspace(workspaceId) {
            for (tabIndex, tab) in state.tabs.enumerated() {
                if let leaf = tab.tree.allLeaves().first(where: { $0.view === view }) {
                    return (.workspace(workspaceId), tabIndex, leaf.id)
                }
            }
        }

        return nil
    }

    private func handleTerminalTitleChanged(view: GhosttyTerminalView, title: String) {
        guard let location = findViewLocation(view) else { return }

        switch location.scope {
        case let scope where scope == activeTerminalScope:
            guard location.tabIndex >= 0 && location.tabIndex < tabs.count else { return }
            guard !pinnedTitleTabIds.contains(tabs[location.tabIndex].id) else { return }
            tabs[location.tabIndex].title = title
            tabBar.updateTabTitle(at: location.tabIndex, title: title)

        case .primary:
            guard location.tabIndex >= 0 && location.tabIndex < primaryTerminalState.tabs.count else { return }
            guard !pinnedTitleTabIds.contains(primaryTerminalState.tabs[location.tabIndex].id) else { return }
            primaryTerminalState.tabs[location.tabIndex].title = title

        case .project(let projectId):
            guard projectTerminalStates[projectId] != nil,
                  location.tabIndex >= 0,
                  location.tabIndex < projectTerminalStates[projectId]!.tabs.count else { return }
            guard !pinnedTitleTabIds.contains(projectTerminalStates[projectId]!.tabs[location.tabIndex].id) else { return }
            projectTerminalStates[projectId]!.tabs[location.tabIndex].title = title

        case .workspace(let workspaceId):
            guard workspaceTerminalStates[workspaceId] != nil,
                  location.tabIndex >= 0,
                  location.tabIndex < workspaceTerminalStates[workspaceId]!.tabs.count else { return }
            guard !pinnedTitleTabIds.contains(workspaceTerminalStates[workspaceId]!.tabs[location.tabIndex].id) else { return }
            workspaceTerminalStates[workspaceId]!.tabs[location.tabIndex].title = title
        }
    }

    private func renameVisibleTab(at index: Int) {
        guard index >= 0 && index < tabs.count,
              let window else { return }

        let tabId = tabs[index].id
        let currentTitle = tabs[index].title
        if renameTabSheet == nil {
            renameTabSheet = RenameTabSheet()
        }

        renameTabSheet?.onConfirm = { [weak self] newTitle in
            guard let self,
                  let currentIndex = self.tabs.firstIndex(where: { $0.id == tabId }) else { return }
            self.tabs[currentIndex].title = newTitle
            self.pinnedTitleTabIds.insert(tabId)
            self.tabBar.updateTabTitle(at: currentIndex, title: newTitle)
        }
        renameTabSheet?.onDismiss = { [weak self] in
            self?.renameTabSheet = nil
        }
        renameTabSheet?.show(relativeTo: window, initialTitle: currentTitle)
    }

    private func showTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }

        // Remove current container
        for sub in terminalContentView.subviews { sub.removeFromSuperview() }

        let tab = tabs[index]

        // Get or create the SplitContainerView for this tab
        let container: SplitContainerView
        if let existing = tabContainers[tab.id] {
            container = existing
        } else {
            container = SplitContainerView(node: tab.tree, focusedPaneId: focusedPaneId)
            container.setDelegateRecursive(self)
            tabContainers[tab.id] = container
        }

        container.translatesAutoresizingMaskIntoConstraints = false
        terminalContentView.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: terminalContentView.topAnchor),
            container.leadingAnchor.constraint(equalTo: terminalContentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: terminalContentView.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: terminalContentView.bottomAnchor),
        ])

        // Restore focus to the focused pane in this tab
        let leaves = tab.tree.allLeaves()
        if let fId = focusedPaneId, let leaf = leaves.first(where: { $0.id == fId }) {
            window?.makeFirstResponder(leaf.view)
        } else if let first = leaves.first {
            focusedPaneId = first.id
            window?.makeFirstResponder(first.view)
        }

        container.updateFocus(focusedPaneId)
        syncRightSidebarProjectContext(forceRefresh: true)
    }

    private func removeTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        let tab = tabs[index]
        pinnedTitleTabIds.remove(tab.id)

        // Clean up all terminal views in this tab's tree
        let leaves = tab.tree.allLeaves()
        for leaf in leaves {
            deactivatePaneAgentState(paneId: leaf.id, workspaceStatus: .idle)
            paneWorkspaceMap.removeValue(forKey: leaf.id)
            leaf.view.removeFromSuperview()
        }

        // Remove container
        tabContainers[tab.id]?.removeFromSuperview()
        tabContainers.removeValue(forKey: tab.id)

        tabs.remove(at: index)
        tabBar.removeTab(at: index)

        if tabs.isEmpty {
            return
        } else {
            let newIndex = min(index, tabs.count - 1)
            showTab(at: newIndex)
        }
    }

    // MARK: - Split Pane Actions

    private func splitFocusedPane(direction: SplitDirection) {
        let idx = currentTabIndex
        guard idx >= 0 && idx < tabs.count else { return }
        guard let fId = focusedPaneId else { return }

        // Inherit working directory from the focused pane
        let focusedView = tabs[idx].tree.findLeaf(fId)
        let workDir = focusedView?.currentWorkingDir ?? defaultWorkingDirectoryForActiveScope()

        let newId = UUID().uuidString
        let newView = makeTerminalView(workingDir: workDir)
        let newTree = tabs[idx].tree.splitLeaf(fId, direction: direction, newId: newId, newView: newView)

        tabs[idx].tree = newTree
        focusedPaneId = newId
        trackPaneForActiveWorkspace(newId)

        // Rebuild the container
        rebuildCurrentTabContainer()
    }

    private func closeCurrentPane() {
        let idx = currentTabIndex
        guard idx >= 0 && idx < tabs.count else { return }
        guard let fId = focusedPaneId else { return }

        let tree = tabs[idx].tree

        // If only one leaf, close the tab
        if tree.leafCount <= 1 {
            removeTab(at: idx)
            return
        }

        // Find sibling to focus
        let nextFocus = tree.nextLeaf(after: fId) ?? tree.previousLeaf(before: fId)

        // Remove the terminal view
        if let view = tree.findLeaf(fId) {
            deactivatePaneAgentState(paneId: fId, workspaceStatus: .idle)
            paneWorkspaceMap.removeValue(forKey: fId)
            view.removeFromSuperview()
        }

        guard let newTree = tree.removeLeaf(fId) else {
            removeTab(at: idx)
            return
        }

        tabs[idx].tree = newTree
        focusedPaneId = nextFocus

        rebuildCurrentTabContainer()
    }

    private func rebuildCurrentTabContainer() {
        let idx = currentTabIndex
        guard idx >= 0 && idx < tabs.count else { return }
        let tab = tabs[idx]

        if let container = tabContainers[tab.id] {
            container.rebuild(with: tab.tree, focusedPaneId: focusedPaneId)
            container.setDelegateRecursive(self)
        } else {
            // Should not happen, but handle gracefully
            showTab(at: idx)
        }

        // Restore focus
        if let fId = focusedPaneId, let view = tab.tree.findLeaf(fId) {
            window?.makeFirstResponder(view)
        }
    }

    /// Shell-integration signal that a command in the PTY finished. For
    /// agent panes this acts as a secondary "agent done" signal (a one-shot
    /// `claude --print`, `aider --message …`, etc.): if the pane was active,
    /// transition it to idle with the exit-code-derived completion status
    /// and fire a workspace notification.
    private func handleCommandFinished(view: GhosttyTerminalView, exitCode: Int16, duration: UInt64) {
        guard let location = findViewLocation(view) else { return }
        let status: WorkspaceItem.WorkspaceStatus = exitCode == 0 ? .completed : .error
        let wasActive = deactivatePaneAgentState(paneId: location.paneId, workspaceStatus: status)
        guard wasActive,
              case .workspace(let workspaceId) = location.scope,
              let workspace = workspaces.first(where: { $0.id == workspaceId }) else { return }
        sendAgentNotification(workspace: workspace, exitCode: exitCode, duration: duration)
    }

    private func handleTerminalExit(view: GhosttyTerminalView) {
        guard let location = findViewLocation(view) else { return }
        deactivatePaneAgentState(paneId: location.paneId, workspaceStatus: .idle)
    }

    private func cleanupTerminalGroupState(_ state: TerminalGroupState) {
        for (_, _, tree) in state.tabs {
            for leaf in tree.allLeaves() {
                deactivatePaneAgentState(paneId: leaf.id, workspaceStatus: .idle)
                paneWorkspaceMap.removeValue(forKey: leaf.id)
                leaf.view.removeFromSuperview()
            }
        }
        for (tabId, _, _) in state.tabs {
            pinnedTitleTabIds.remove(tabId)
        }
    }

    private func discardWorkspaceTerminalState(_ workspace: WorkspaceItem) {
        if activeTerminalScope == .workspace(workspace.id) {
            let currentState = currentTerminalGroupState()
            cleanupTerminalGroupState(currentState)
            tabs.removeAll()
            focusedPaneId = nil
            clearVisibleTerminalUI()
            if projects.contains(where: { $0.id == workspace.projectId }) {
                activeTerminalScope = .project(workspace.projectId)
            } else {
                activeTerminalScope = .primary
            }
            syncSidebarSelection()
            applyTerminalGroupState(terminalGroupState(for: activeTerminalScope))
            if tabs.isEmpty {
                if case .project(let projectId) = activeTerminalScope,
                   let project = projects.first(where: { $0.id == projectId }) {
                    openProjectTerminal(project)
                } else {
                    addTerminalTab(title: "Terminal", workingDir: defaultWorkingDirectoryForActiveScope())
                }
            }
        } else if let state = workspaceTerminalStates.removeValue(forKey: workspace.id) {
            cleanupTerminalGroupState(state)
        }

        workspaceTerminalStates.removeValue(forKey: workspace.id)
        paneWorkspaceMap = paneWorkspaceMap.filter { $0.value != workspace.id }
    }

    private func discardProjectTerminalState(_ projectId: UUID) {
        if activeTerminalScope == .project(projectId) {
            let currentState = currentTerminalGroupState()
            cleanupTerminalGroupState(currentState)
            tabs.removeAll()
            focusedPaneId = nil
            clearVisibleTerminalUI()
            activeTerminalScope = .primary
            syncSidebarSelection()
            applyTerminalGroupState(terminalGroupState(for: activeTerminalScope))
            if tabs.isEmpty {
                addTerminalTab(title: "Terminal", workingDir: defaultWorkingDirectoryForActiveScope())
            }
        } else if let state = projectTerminalStates.removeValue(forKey: projectId) {
            cleanupTerminalGroupState(state)
        }

        projectTerminalStates.removeValue(forKey: projectId)
    }

    private func sendAgentNotification(workspace: WorkspaceItem, exitCode: Int16, duration: UInt64) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let content = UNMutableNotificationContent()
        content.title = exitCode == 0 ? "Agent Finished" : "Agent Failed"
        let durationSec = Double(duration) / 1_000_000_000
        let durationStr = durationSec < 60 ? String(format: "%.0fs", durationSec) : String(format: "%.1fm", durationSec / 60)
        content.body = "\(workspace.name) — \(durationStr)"
        content.sound = .default
        content.userInfo = ["workspaceId": workspace.id.uuidString]

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    private func handlePaneClicked(_ view: GhosttyTerminalView) {
        let idx = currentTabIndex
        guard idx >= 0 && idx < tabs.count else { return }

        // Find the pane id for this view
        let leaves = tabs[idx].tree.allLeaves()
        if let leaf = leaves.first(where: { $0.view === view }) {
            focusedPaneId = leaf.id
            tabContainers[tabs[idx].id]?.updateFocus(focusedPaneId)
            syncRightSidebarProjectContext(forceRefresh: true)
        }
    }

    // MARK: - Data Management

    private func loadData() {
        loadProjects()
        loadPresets()
        loadWorkspaces()
    }

    private func loadProjects() {
        let path = dataDir.appendingPathComponent("projects.json")
        if let data = try? Data(contentsOf: path),
           let decoded = try? JSONDecoder().decode([ProjectItem].self, from: data) {
            projects = decoded
        }
    }

    private func saveProjects() {
        let path = dataDir.appendingPathComponent("projects.json")
        if let data = try? JSONEncoder().encode(projects) {
            try? data.write(to: path)
        }
    }

    private func loadPresets() {
        let path = dataDir.appendingPathComponent("presets.json")
        if let data = try? Data(contentsOf: path),
           let decoded = try? JSONDecoder().decode([AgentPresetItem].self, from: data) {
            presets = decoded
        }
        if presets.isEmpty {
            presets = defaultPresets()
            savePresets()
        }
    }

    private func savePresets() {
        let path = dataDir.appendingPathComponent("presets.json")
        if let data = try? JSONEncoder().encode(presets) {
            try? data.write(to: path)
        }
    }

    private func defaultPresets() -> [AgentPresetItem] {
        [
            AgentPresetItem(name: "Claude Code", command: "claude --dangerously-skip-permissions", description: "Anthropic Claude Code", provider: "anthropic", icon: "brain"),
            AgentPresetItem(name: "Codex", command: "codex -c model_reasoning_effort=\"xhigh\" --ask-for-approval never --sandbox danger-full-access -c model_reasoning_summary=\"detailed\" -c model_supports_reasoning_summaries=true", description: "OpenAI Codex CLI", provider: "openai", icon: "sparkles"),
            AgentPresetItem(name: "Gemini CLI", command: "gemini", description: "Google Gemini CLI", provider: "google", icon: "diamond"),
            AgentPresetItem(name: "Aider", command: "aider", description: "AI Pair Programming", provider: "multiple", icon: "wrench"),
            AgentPresetItem(name: "Copilot", command: "gh copilot", description: "GitHub Copilot CLI", provider: "github", icon: "rocket"),
        ]
    }

    private func visibleTopBarPresets(from presets: [AgentPresetItem]) -> [AgentPresetItem] {
        presets.filter(\.pinned)
    }

    private func refreshPresetBarPresets() {
        let mergedPresets = projectPresets + presets
        presetBar?.setPresets(visibleTopBarPresets(from: mergedPresets))
    }

    // MARK: - Workspace Management

    private func loadWorkspaces() {
        let path = dataDir.appendingPathComponent("workspaces.json")
        if let data = try? Data(contentsOf: path),
           let decoded = try? JSONDecoder().decode([WorkspaceItem].self, from: data) {
            var didNormalize = false
            let normalized = decoded.map { workspace -> WorkspaceItem in
                var workspace = workspace
                if workspace.status == .running {
                    workspace.status = .idle
                    didNormalize = true
                }
                return workspace
            }
            workspaces = normalized
            if didNormalize {
                saveWorkspaces()
            }
        }
    }

    private func saveWorkspaces() {
        let path = dataDir.appendingPathComponent("workspaces.json")
        if let data = try? JSONEncoder().encode(workspaces) {
            try? data.write(to: path)
        }
    }

    @objc func newWorkspace(_ sender: Any?) {
        guard let window = window else { return }
        let sheet = NewWorkspaceSheet(projects: projects, presets: presets, selectedProject: currentProject)
        sheet.onConfirm = { [weak self] project, branchName, prompt, agent in
            self?.createWorkspace(project: project, branchName: branchName, prompt: prompt, agent: agent)
        }
        sheet.onConfirmExisting = { [weak self] project, branchName, prompt, agent in
            self?.createWorkspaceFromExistingBranch(project: project, branchName: branchName, prompt: prompt, agent: agent)
        }
        newWorkspaceSheet = sheet
        sheet.show(relativeTo: window)
    }

    private func createWorkspace(project: ProjectItem, branchName: String, prompt: String, agent: AgentPresetItem) {
        let worktreeBase = NSHomeDirectory() + "/.cterm/worktrees/\(project.name)"
        let worktreePath = worktreeBase + "/\(branchName.replacingOccurrences(of: "/", with: "_"))"

        try? FileManager.default.createDirectory(atPath: worktreeBase, withIntermediateDirectories: true)

        DispatchQueue.global().async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["worktree", "add", worktreePath, "-b", branchName]
            process.currentDirectoryURL = URL(fileURLWithPath: project.path)
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = Pipe()

            do {
                try process.run()
                process.waitUntilExit()

                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        self?.finishWorkspaceCreation(project: project, branchName: branchName,
                                                      worktreePath: worktreePath, prompt: prompt, agent: agent)
                    } else {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
                        let alert = NSAlert()
                        alert.messageText = "Worktree Creation Failed"
                        alert.informativeText = errMsg
                        alert.runModal()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Error"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    private func createWorkspaceFromExistingBranch(project: ProjectItem, branchName: String, prompt: String, agent: AgentPresetItem) {
        let worktreeBase = NSHomeDirectory() + "/.cterm/worktrees/\(project.name)"
        let worktreePath = worktreeBase + "/\(branchName.replacingOccurrences(of: "/", with: "_"))"

        try? FileManager.default.createDirectory(atPath: worktreeBase, withIntermediateDirectories: true)

        DispatchQueue.global().async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            // No -b flag: attach to existing branch
            process.arguments = ["worktree", "add", worktreePath, branchName]
            process.currentDirectoryURL = URL(fileURLWithPath: project.path)
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = Pipe()

            do {
                try process.run()
                process.waitUntilExit()

                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        self?.finishWorkspaceCreation(project: project, branchName: branchName,
                                                      worktreePath: worktreePath, prompt: prompt, agent: agent)
                    } else {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
                        let alert = NSAlert()
                        alert.messageText = "Worktree Creation Failed"
                        alert.informativeText = errMsg
                        alert.runModal()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Error"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    private func finishWorkspaceCreation(project: ProjectItem, branchName: String,
                                          worktreePath: String, prompt: String, agent: AgentPresetItem) {
        let ws = WorkspaceItem(projectId: project.id, name: branchName.components(separatedBy: "/").last ?? branchName,
                               branchName: branchName, worktreePath: worktreePath,
                               prompt: prompt, agentCommand: agent.command, agentProvider: agent.provider)
        workspaces.append(ws)
        saveWorkspaces()

        let agentInput: String
        if prompt.isEmpty {
            agentInput = agent.command + "\n"
        } else {
            let escaped = prompt.replacingOccurrences(of: "\"", with: "\\\"")
            if agent.command == "aider" {
                agentInput = "\(agent.command) --message \"\(escaped)\"\n"
            } else {
                agentInput = "\(agent.command) \"\(escaped)\"\n"
            }
        }

        // Run setup scripts before opening terminal
        let wsId = ws.id
        WorkspaceLifecycle.shared.runSetup(
            projectPath: project.path,
            workspaceName: ws.name,
            workingDir: worktreePath
        ) { [weak self] _ in
            self?.switchTerminalScope(to: .workspace(wsId))
            _ = self?.addTerminalTab(title: "\(agent.name): \(ws.name)", workingDir: worktreePath, initialInput: agentInput, pinTitle: true)
            self?.projectSidebar.setWorkspaces(self?.workspaces ?? [])
            self?.projectSidebar.setProjects(self?.projects ?? [])
        }
    }

    // MARK: - Workspace Deletion

    func deleteWorkspace(_ workspace: WorkspaceItem, deleteBranch: Bool) {
        // Find project for teardown
        let project = projects.first { $0.id == workspace.projectId }

        // Run teardown scripts
        WorkspaceLifecycle.shared.runTeardown(
            projectPath: project?.path ?? workspace.worktreePath,
            workspaceName: workspace.name,
            workingDir: workspace.worktreePath
        ) { [weak self] _ in
            self?.performWorkspaceDeletion(workspace, deleteBranch: deleteBranch, projectPath: project?.path)
        }
    }

    private func performWorkspaceDeletion(_ workspace: WorkspaceItem, deleteBranch: Bool, projectPath: String?) {
        discardWorkspaceTerminalState(workspace)

        // Remove git worktree on background thread
        DispatchQueue.global().async { [weak self] in
            let gitDir = projectPath ?? workspace.worktreePath
            func runGit(arguments: [String]) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = arguments
                process.currentDirectoryURL = URL(fileURLWithPath: gitDir)
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                try? process.run()
                process.waitUntilExit()
            }

            runGit(arguments: ["worktree", "remove", workspace.worktreePath, "--force"])

            // Optionally delete branch
            if deleteBranch {
                runGit(arguments: ["worktree", "prune"])
                runGit(arguments: ["branch", "-D", workspace.branchName])
            }

            DispatchQueue.main.async {
                self?.workspaces.removeAll { $0.id == workspace.id }
                self?.saveWorkspaces()
                self?.projectSidebar.setWorkspaces(self?.workspaces ?? [])
                self?.projectSidebar.setProjects(self?.projects ?? [])
            }
        }
    }

    // MARK: - Layout Management

    func saveCurrentLayout() {
        guard let window = window else { return }
        let layout: [String: Any] = [
            "frame": NSStringFromRect(window.frame),
            "leftVisible": leftSidebarVisible,
            "leftWidth": clampedLeftSidebarWidth(leftSidebarWidth),
            "rightVisible": rightSidebarVisible,
            "rightWidth": clampedRightSidebarWidth(rightSidebarWidth),
        ]
        UserDefaults.standard.set(layout, forKey: "CTerm.layout.default")
        tokenTracker.saveToDisk()
        persistActiveTerminalGroupState()

        // Save terminal session state
        SessionPersistence.shared.saveSession(
            groups: [
                SessionPersistence.GroupSnapshotInput(
                    projectId: nil,
                    workspaceId: nil,
                    tabs: primaryTerminalState.tabs,
                    focusedPaneId: primaryTerminalState.focusedPaneId,
                    selectedTabIndex: primaryTerminalState.selectedTabIndex
                )
            ] + projectTerminalStates.map { projectId, state in
                SessionPersistence.GroupSnapshotInput(
                    projectId: projectId,
                    workspaceId: nil,
                    tabs: state.tabs,
                    focusedPaneId: state.focusedPaneId,
                    selectedTabIndex: state.selectedTabIndex
                )
            } + workspaceTerminalStates.map { workspaceId, state in
                SessionPersistence.GroupSnapshotInput(
                    projectId: nil,
                    workspaceId: workspaceId,
                    tabs: state.tabs,
                    focusedPaneId: state.focusedPaneId,
                    selectedTabIndex: state.selectedTabIndex
                )
            },
            activeProjectId: activeTerminalScope.projectId,
            activeWorkspaceId: activeTerminalScope.workspaceId
        )
    }

    private func loadSavedLayout() {
        guard let layout = UserDefaults.standard.dictionary(forKey: "CTerm.layout.default") else { return }
        if let frameStr = layout["frame"] as? String {
            let frame = NSRectFromString(frameStr)
            if frame.width > 100 && frame.height > 100 { window?.setFrame(frame, display: true) }
        }
        if let v = layout["leftVisible"] as? Bool { leftSidebarVisible = v }
        if let v = layout["leftWidth"] as? CGFloat { leftSidebarWidth = clampedLeftSidebarWidth(v) }
        if let v = layout["rightVisible"] as? Bool { rightSidebarVisible = v }
        if let v = layout["rightWidth"] as? CGFloat { rightSidebarWidth = clampedRightSidebarWidth(v) }
        updateSidebarVisibility(animated: false)
        updateRightSidebarVisibility(animated: false)
    }

    private func updateSidebarVisibility(animated: Bool = true) {
        if leftSidebarVisible {
            leftSidebarWidth = clampedLeftSidebarWidth(leftSidebarWidth)
        }
        let leftPos: CGFloat = leftSidebarVisible ? leftSidebarWidth : 0
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                mainSplitView.animator().setPosition(leftPos, ofDividerAt: 0)
            })
        } else {
            mainSplitView.setPosition(leftPos, ofDividerAt: 0)
        }
    }

    private func updateGitBranch() {
        let path = currentProject?.path ?? NSHomeDirectory()
        DispatchQueue.global().async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
            process.currentDirectoryURL = URL(fileURLWithPath: path)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "~"
            DispatchQueue.main.async { self?.statusBar.updateBranch(branch) }
        }
    }

    private func updatePresetBarTrafficLightSpacing(showsTrafficLights: Bool? = nil) {
        let shouldShowTrafficLights = showsTrafficLights ?? !(window?.styleMask.contains(.fullScreen) ?? false)
        presetBar?.setShowsTrafficLightSpacing(shouldShowTrafficLights)
        presetBar?.layoutSubtreeIfNeeded()
    }

    @objc func showSettings(_ sender: Any?) {
        presentSettingsWindow()
    }

    // MARK: - Menu Actions

    @objc func newTerminalTab(_ sender: Any?) {
        guard canCreateTerminalInActiveScope() else { return }
        addTerminalTab(title: "Terminal \(tabs.count + 1)", workingDir: defaultWorkingDirectoryForActiveScope())
    }

    @objc func closeCurrentTab(_ sender: Any?) {
        closeCurrentPane()
    }

    @objc func toggleLeftSidebar(_ sender: Any?) {
        leftSidebarVisible.toggle()
        updateSidebarVisibility()
    }

    @objc func toggleRightSidebar(_ sender: Any?) {
        rightSidebarVisible.toggle()
        updateRightSidebarVisibility(animated: !rightSidebarAnimating)
        if rightSidebarVisible {
            syncRightSidebarProjectContext(forceRefresh: true)
        }
    }

    @objc func openSettings(_ sender: Any?) {
        presentSettingsWindow()
    }

    private func presentSettingsWindow() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
            settingsWindow?.onPresetsChanged = { [weak self] presets in
                self?.presets = presets
                self?.refreshPresetBarPresets()
            }
        }
        settingsWindow?.present(attachedTo: window)
    }

    @objc func rightSidebarTabChanged(_ sender: NSSegmentedControl) {
        changesPanel.isHidden = (sender.selectedSegment != 0)
        fileBrowser.isHidden = (sender.selectedSegment != 1)
    }

    @objc func refreshRightSidebar() {
        projectSidebar.refreshGitStatusRows()
        syncRightSidebarProjectContext(forceRefresh: true)
    }

    @objc func rightSidebarTabClicked(_ sender: NSButton) {
        let showChanges = (sender.tag == 0)
        changesPanel.isHidden = !showChanges
        fileBrowser.isHidden = showChanges

        // Update tab button appearance
        if let container = sender.superview {
            for case let btn as NSButton in container.subviews {
                let isSelected = (btn.tag == sender.tag)
                btn.layer?.backgroundColor = isSelected
                    ? NSColor(white: 0.18, alpha: 1).cgColor
                    : NSColor.clear.cgColor
                btn.contentTintColor = isSelected ? AppTheme.textPrimary : AppTheme.textSecondary
            }
        }

        syncRightSidebarProjectContext(forceRefresh: showChanges)
    }

    private func updateGitRefreshTimer() {
        gitRefreshTimer?.invalidate()
        gitRefreshTimer = nil

        guard window != nil else { return }

        let timer = Timer(timeInterval: Self.gitRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshGitStatusSurfaces()
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        gitRefreshTimer = timer
    }

    private func refreshGitStatusSurfaces() {
        projectSidebar.refreshGitStatusRows()

        guard rightSidebarVisible else { return }

        syncRightSidebarProjectContext(forceRefresh: !changesPanel.isHidden)
    }

    private func makeSidebarTab(_ title: String, tag: Int, selected: Bool) -> NSButton {
        let btn = NSButton(title: title, target: self, action: #selector(rightSidebarTabClicked(_:)))
        btn.tag = tag
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        btn.contentTintColor = selected ? AppTheme.textPrimary : AppTheme.textSecondary
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 4
        btn.layer?.backgroundColor = selected ? NSColor(white: 0.18, alpha: 1).cgColor : NSColor.clear.cgColor
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 70),
            btn.heightAnchor.constraint(equalToConstant: 22),
        ])
        return btn
    }

    @objc func openPresetByIndex(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0 && index < presets.count else { return }
        presetSelected(presets[index])
    }

    @objc func openInEditor(_ sender: Any?) {
        let path = currentProject?.path ?? NSHomeDirectory()
        let editor = SettingsManager.shared.settings.defaultEditor
        EditorLauncher.open(path: path, editor: editor)
    }

    @objc func copyWorkspacePath(_ sender: Any?) {
        if let fId = focusedPaneId,
           let idx = tabs.indices.first(where: { tabs[$0].tree.findLeaf(fId) != nil }),
           let view = tabs[idx].tree.findLeaf(fId),
           let cwd = view.currentWorkingDir {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cwd, forType: .string)
        } else if let path = currentProject?.path {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
    }

    @objc func showQuickOpen(_ sender: Any?) {
        guard let window = window else { return }
        let path = currentProject?.path ?? NSHomeDirectory()
        let editor = SettingsManager.shared.settings.defaultEditor
        let panel = QuickOpenPanel()
        panel.show(relativeTo: window, projectPath: path, editor: editor)
        quickOpenPanel = panel
    }

    @objc func showSearch(_ sender: Any?) {
        guard let window = window else { return }
        let editor = SettingsManager.shared.settings.defaultEditor

        // Collect all search paths: project + workspaces
        var paths: [(name: String, path: String)] = []
        if let project = currentProject {
            paths.append((name: project.name, path: project.path))
        }
        for ws in workspaces {
            paths.append((name: ws.name, path: ws.worktreePath))
        }

        let panel = SearchPanel()
        panel.show(relativeTo: window, searchPaths: paths, editor: editor)
        searchPanel = panel
    }

    private func updateRightSidebarVisibility(animated: Bool = true) {
        if rightSidebarVisible {
            rightSidebarWidth = clampedRightSidebarWidth(rightSidebarWidth)
        }
        let newWidth: CGFloat = rightSidebarVisible ? rightSidebarWidth : 0
        rightSidebarAnimationGeneration += 1
        let generation = rightSidebarAnimationGeneration

        if rightSidebarVisible {
            rightSidebarContainer.isHidden = false
        }

        let finalize = { [weak self] in
            guard let self else { return }
            guard generation == self.rightSidebarAnimationGeneration else { return }
            self.rightSidebarAnimating = false
            self.rightSidebarWidthConstraint.constant = newWidth
            self.rightSidebarContainer.isHidden = !self.rightSidebarVisible
            self.centerContainer.layoutSubtreeIfNeeded()
        }

        if animated {
            rightSidebarAnimating = true
            centerContainer.layoutSubtreeIfNeeded()
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                rightSidebarWidthConstraint.animator().constant = newWidth
                centerContainer.layoutSubtreeIfNeeded()
            }, completionHandler: finalize)
        } else {
            rightSidebarWidthConstraint.constant = newWidth
            centerContainer.layoutSubtreeIfNeeded()
            finalize()
        }
    }

    @objc func splitHorizontal(_ sender: Any?) {
        splitFocusedPane(direction: .horizontal)
    }

    @objc func splitVertical(_ sender: Any?) {
        splitFocusedPane(direction: .vertical)
    }

    @objc func equalizePanes(_ sender: Any?) {
        let idx = currentTabIndex
        guard idx >= 0 && idx < tabs.count else { return }
        tabs[idx].tree = tabs[idx].tree.equalized()
        rebuildCurrentTabContainer()
    }

    @objc func focusNextPane(_ sender: Any?) {
        let idx = currentTabIndex
        guard idx >= 0 && idx < tabs.count, let fId = focusedPaneId else { return }
        if let nextId = tabs[idx].tree.nextLeaf(after: fId) {
            focusedPaneId = nextId
            tabContainers[tabs[idx].id]?.updateFocus(focusedPaneId)
            if let view = tabs[idx].tree.findLeaf(nextId) {
                window?.makeFirstResponder(view)
            }
        }
    }

    @objc func focusPreviousPane(_ sender: Any?) {
        let idx = currentTabIndex
        guard idx >= 0 && idx < tabs.count, let fId = focusedPaneId else { return }
        if let prevId = tabs[idx].tree.previousLeaf(before: fId) {
            focusedPaneId = prevId
            tabContainers[tabs[idx].id]?.updateFocus(focusedPaneId)
            if let view = tabs[idx].tree.findLeaf(prevId) {
                window?.makeFirstResponder(view)
            }
        }
    }

    @objc func clearScreen(_ sender: Any?) {
        guard let fId = focusedPaneId, let idx = tabs.indices.first(where: { tabs[$0].tree.findLeaf(fId) != nil }) else { return }
        if let view = tabs[idx].tree.findLeaf(fId), let surface = view.ghosttySurface {
            let cmd = "clear_screen"
            ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
        }
    }

    @objc func scrollToBottom(_ sender: Any?) {
        guard let fId = focusedPaneId, let idx = tabs.indices.first(where: { tabs[$0].tree.findLeaf(fId) != nil }) else { return }
        if let view = tabs[idx].tree.findLeaf(fId), let surface = view.ghosttySurface {
            let cmd = "scroll_to_bottom"
            ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
        }
    }

    @objc func runWorkspaceScripts(_ sender: Any?) {
        // Run the "run" scripts from .cterm/config.json in the focused terminal
        guard let fId = focusedPaneId,
              let idx = tabs.indices.first(where: { tabs[$0].tree.findLeaf(fId) != nil }),
              let view = tabs[idx].tree.findLeaf(fId),
              let surface = view.ghosttySurface else { return }

        let cwd = view.currentWorkingDir ?? currentProject?.path ?? NSHomeDirectory()
        let projectPath = currentProject?.path ?? cwd

        if let config = WorkspaceLifecycle.shared.loadConfig(projectPath: projectPath),
           let commands = config.run, !commands.isEmpty {
            WorkspaceLifecycle.shared.sendCommandsToTerminal(commands: commands, surface: surface)
        }
    }

    @objc func findInTerminal(_ sender: Any?) {
        if searchBar != nil {
            dismissSearchBar()
            return
        }
        showSearchBar()
    }

    private func showSearchBar() {
        let bar = TerminalSearchBar()
        bar.delegate = self
        bar.translatesAutoresizingMaskIntoConstraints = false
        terminalContentView.addSubview(bar)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: terminalContentView.topAnchor),
            bar.leadingAnchor.constraint(equalTo: terminalContentView.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: terminalContentView.trailingAnchor),
        ])

        searchBar = bar
        bar.activate()
    }

    private func dismissSearchBar() {
        // End search in ghostty
        if let fId = focusedPaneId,
           let idx = tabs.indices.first(where: { tabs[$0].tree.findLeaf(fId) != nil }),
           let view = tabs[idx].tree.findLeaf(fId),
           let surface = view.ghosttySurface {
            let cmd = "end_search"
            ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
        }

        searchBar?.removeFromSuperview()
        searchBar = nil

        // Restore focus to terminal
        if let fId = focusedPaneId,
           let idx = tabs.indices.first(where: { tabs[$0].tree.findLeaf(fId) != nil }),
           let view = tabs[idx].tree.findLeaf(fId) {
            window?.makeFirstResponder(view)
        }
    }

    @objc func saveLayout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Save Layout"
        alert.informativeText = "Enter a name for this layout:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = "My Layout"
        alert.accessoryView = input
        if alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue
            guard !name.isEmpty, let window = window else { return }
            var layouts = UserDefaults.standard.dictionary(forKey: "CTerm.layouts") as? [String: [String: Any]] ?? [:]
            layouts[name] = [
                "frame": NSStringFromRect(window.frame),
                "leftVisible": leftSidebarVisible,
                "leftWidth": clampedLeftSidebarWidth(leftSidebarWidth),
                "rightVisible": rightSidebarVisible,
                "rightWidth": clampedRightSidebarWidth(rightSidebarWidth),
                "timestamp": Date().timeIntervalSince1970,
            ]
            UserDefaults.standard.set(layouts, forKey: "CTerm.layouts")
        }
    }

    @objc func loadLayout(_ sender: Any?) {
        let layouts = UserDefaults.standard.dictionary(forKey: "CTerm.layouts") as? [String: [String: Any]] ?? [:]
        guard !layouts.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Saved Layouts"
            alert.informativeText = "Save a layout first using View > Save Layout."
            alert.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Load Layout"
        alert.informativeText = "Select a layout to restore:"
        alert.addButton(withTitle: "Load")
        alert.addButton(withTitle: "Cancel")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        for name in layouts.keys.sorted() { popup.addItem(withTitle: name) }
        alert.accessoryView = popup
        if alert.runModal() == .alertFirstButtonReturn {
            guard let name = popup.selectedItem?.title, let layout = layouts[name] else { return }
            if let frameStr = layout["frame"] as? String {
                let frame = NSRectFromString(frameStr)
                if frame.width > 100 { window?.setFrame(frame, display: true, animate: true) }
            }
            if let v = layout["leftVisible"] as? Bool { leftSidebarVisible = v }
            if let v = layout["leftWidth"] as? CGFloat { leftSidebarWidth = clampedLeftSidebarWidth(v) }
            if let v = layout["rightVisible"] as? Bool { rightSidebarVisible = v }
            if let v = layout["rightWidth"] as? CGFloat { rightSidebarWidth = clampedRightSidebarWidth(v) }
            updateSidebarVisibility()
            updateRightSidebarVisibility()
        }
    }

    private func clampedLeftSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, Self.leftSidebarMinWidth), Self.leftSidebarMaxWidth)
    }

    private func clampedRightSidebarWidth(_ width: CGFloat) -> CGFloat {
        max(width, Self.rightSidebarMinWidth)
    }

    @objc func addProject(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory"
        if panel.runModal() == .OK, let url = panel.url {
            let project = ProjectItem(name: url.lastPathComponent, path: url.path)
            projects.append(project)
            saveProjects()
            projectSidebar.setProjects(projects)
        }
    }
}

// MARK: - TerminalTabBarDelegate

extension MainWindowController: TerminalTabBarDelegate {
    func tabBar(_ tabBar: TerminalTabBar, didSelectTabAt index: Int) {
        showTab(at: index)
    }

    func tabBar(_ tabBar: TerminalTabBar, didCloseTabAt index: Int) {
        removeTab(at: index)
    }

    func tabBar(_ tabBar: TerminalTabBar, didRequestRenameTabAt index: Int) {
        renameVisibleTab(at: index)
    }

    func tabBarDidRequestNewTab(_ tabBar: TerminalTabBar) {
        newTerminalTab(nil)
    }
}

// MARK: - NSSplitViewDelegate (for main sidebar split)

extension MainWindowController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard splitView === mainSplitView else { return proposedMinimumPosition }
        return leftSidebarVisible ? Self.leftSidebarMinWidth : 0
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard splitView === mainSplitView else { return proposedMaximumPosition }
        return Self.leftSidebarMaxWidth
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView, splitView === mainSplitView else { return }
        guard leftSidebarVisible else { return }
        leftSidebarWidth = clampedLeftSidebarWidth(projectSidebar.frame.width)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        guard splitView === mainSplitView else { return false }
        return subview === projectSidebar
    }
}

// MARK: - NSWindowDelegate

extension MainWindowController: NSWindowDelegate {
    func windowWillEnterFullScreen(_ notification: Notification) {
        updatePresetBarTrafficLightSpacing(showsTrafficLights: false)
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        updatePresetBarTrafficLightSpacing(showsTrafficLights: true)
    }

    func windowWillClose(_ notification: Notification) {
        settingsWindow?.close()
        settingsWindow = nil
    }
}

// MARK: - TerminalViewDelegate

extension MainWindowController: TerminalViewDelegate {
    func terminalDidUpdateTitle(_ title: String) {
        _ = title
    }

    func terminalDidExit(status: Int32) {}
}

// MARK: - SplitContainerDelegate

extension MainWindowController: SplitContainerDelegate {
    func splitContainerDidChangeFocus(_ paneId: String) {
        focusedPaneId = paneId
        let idx = currentTabIndex
        if idx >= 0 && idx < tabs.count {
            tabContainers[tabs[idx].id]?.updateFocus(paneId)
        }
    }

    func splitContainerDidChangeRatio(splitId: String, ratio: CGFloat) {
        let idx = currentTabIndex
        guard idx >= 0 && idx < tabs.count else { return }
        tabs[idx].tree = tabs[idx].tree.updatingRatio(splitId: splitId, ratio: ratio)
    }
}

// MARK: - TerminalSearchBarDelegate

extension MainWindowController: TerminalSearchBarDelegate {
    func searchBarDidUpdateQuery(_ query: String) {
        guard let fId = focusedPaneId,
              let idx = tabs.indices.first(where: { tabs[$0].tree.findLeaf(fId) != nil }),
              let view = tabs[idx].tree.findLeaf(fId),
              let surface = view.ghosttySurface else { return }

        if query.isEmpty {
            let cmd = "end_search"
            ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
            searchBar?.updateMatchInfo(total: -1, selected: 0)
        } else {
            let cmd = "search:\(query)"
            ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
        }
    }

    func searchBarDidRequestNext() {
        guard let fId = focusedPaneId,
              let idx = tabs.indices.first(where: { tabs[$0].tree.findLeaf(fId) != nil }),
              let view = tabs[idx].tree.findLeaf(fId),
              let surface = view.ghosttySurface else { return }
        let cmd = "search_forward"
        ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
    }

    func searchBarDidRequestPrevious() {
        guard let fId = focusedPaneId,
              let idx = tabs.indices.first(where: { tabs[$0].tree.findLeaf(fId) != nil }),
              let view = tabs[idx].tree.findLeaf(fId),
              let surface = view.ghosttySurface else { return }
        let cmd = "search_backward"
        ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
    }

    func searchBarDidClose() {
        dismissSearchBar()
    }
}

// MARK: - ProjectSidebarDelegate

extension MainWindowController: ProjectSidebarDelegate {
    func projectLocalSelected(_ project: ProjectItem) {
        activateProject(project)
        switchTerminalScope(to: .project(project.id))
        if tabs.isEmpty {
            openProjectTerminal(project)
        }
    }

    private func activateProject(_ project: ProjectItem) {
        currentProject = project
        updateGitBranch()
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].lastOpened = Date()
            saveProjects()
        }
        syncRightSidebarProjectContext()
        // Load project-level presets and merge
        loadProjectPresets(for: project)
        syncSidebarSelection()
    }

    private func syncRightSidebarProjectContext(forceRefresh: Bool = false) {
        let path = resolvedRightSidebarPath()
        changesPanel.currentProjectPath = path
        fileBrowser.projectPath = path
        portManager.workingDirectory = path

        guard rightSidebarVisible else { return }

        changesPanel.refreshIfNeeded(force: forceRefresh)
        fileBrowser.reloadIfNeeded(force: forceRefresh)
    }

    private func loadProjectPresets(for project: ProjectItem) {
        let configPath = (project.path as NSString).appendingPathComponent(".cterm/presets.json")
        guard FileManager.default.fileExists(atPath: configPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let projectPresets = try? JSONDecoder().decode([AgentPresetItem].self, from: data) else {
            self.projectPresets = []
            refreshPresetBarPresets()
            return
        }
        self.projectPresets = projectPresets
        refreshPresetBarPresets()
    }

    func projectOpenInEditor(_ project: ProjectItem) {
        let editor = project.editor.isEmpty ? "code" : project.editor
        EditorLauncher.open(path: project.path, editor: editor)
    }

    func projectRemoved(_ project: ProjectItem) {
        let relatedWorkspaces = workspaces.filter { $0.projectId == project.id }

        if window != nil {
            let alert = NSAlert()
            alert.messageText = "Remove Repository"
            alert.informativeText = relatedWorkspaces.isEmpty
                ? "This removes \(project.name) from CTerm. Files on disk stay unchanged."
                : "This removes \(project.name) and its workspace entries from CTerm. Files on disk and existing worktrees stay unchanged."
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Cancel")
            alert.window.appearance = NSAppearance(named: .darkAqua)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        let relatedWorkspaceIds = Set(relatedWorkspaces.map(\.id))
        let removedActiveProjectScope = activeTerminalScope.projectId == project.id
        let removedActiveWorkspaceScope = activeTerminalScope.workspaceId.map { relatedWorkspaceIds.contains($0) } ?? false
        let removedCurrentProject = currentProject?.id == project.id

        projects.removeAll { $0.id == project.id }

        for workspace in relatedWorkspaces {
            discardWorkspaceTerminalState(workspace)
        }
        discardProjectTerminalState(project.id)

        if !relatedWorkspaceIds.isEmpty {
            workspaces.removeAll { relatedWorkspaceIds.contains($0.id) }
            saveWorkspaces()
        }

        saveProjects()
        projectSidebar.setWorkspaces(workspaces)
        projectSidebar.setProjects(projects)
        syncSidebarSelection()

        if removedCurrentProject {
            currentProject = projects.first
            if let replacementProject = currentProject {
                loadProjectPresets(for: replacementProject)
            } else {
                projectPresets = []
                refreshPresetBarPresets()
            }
            updateGitBranch()
            syncRightSidebarProjectContext(forceRefresh: true)
        }

        if removedActiveProjectScope || removedActiveWorkspaceScope {
            if let replacementProject = currentProject {
                switchTerminalScope(to: .project(replacementProject.id))
                if tabs.isEmpty {
                    openProjectTerminal(replacementProject)
                }
            } else {
                switchTerminalScope(to: .primary)
                if tabs.isEmpty {
                    addTerminalTab(title: "Terminal", workingDir: defaultWorkingDirectoryForActiveScope())
                }
            }
        }
    }

    func addProjectRequested() { addProject(nil) }

    func newWorkspaceRequested() { newWorkspace(nil) }

    func workspaceSelected(_ workspace: WorkspaceItem) {
        if let project = projects.first(where: { $0.id == workspace.projectId }) {
            activateProject(project)
        }
        switchTerminalScope(to: .workspace(workspace.id))
        if tabs.isEmpty {
            openWorkspaceTerminal(workspace)
        }
    }

    func workspaceDeleteRequested(_ workspace: WorkspaceItem) {
        guard let window else { return }

        let sheet = DeleteWorkspaceSheet()
        sheet.onConfirm = { [weak self] deleteBranch in
            self?.deleteWorkspace(workspace, deleteBranch: deleteBranch)
        }
        sheet.onDismiss = { [weak self] in
            self?.deleteWorkspaceSheet = nil
        }
        deleteWorkspaceSheet = sheet
        sheet.show(relativeTo: window, workspace: workspace)
    }

    func workspaceOpenInEditor(_ workspace: WorkspaceItem) {
        let project = projects.first { $0.id == workspace.projectId }
        let editor = project?.editor.isEmpty == false ? project!.editor : "code"
        EditorLauncher.open(path: workspace.worktreePath, editor: editor)
    }
}

// MARK: - PresetBarDelegate

extension MainWindowController: PresetBarDelegate {
    func newTerminalRequested() {
        guard canCreateTerminalInActiveScope() else { return }
        // Pin the title so the shell's OSC title sequence (which would
        // otherwise replace "Terminal" with the cwd the moment the prompt
        // renders) can't hijack it. Same treatment as the agent-preset
        // path; users can still rename via the rename sheet.
        addTerminalTab(title: "Terminal", workingDir: defaultWorkingDirectoryForActiveScope(), pinTitle: true)
    }

    func presetSelected(_ preset: AgentPresetItem) {
        guard canCreateTerminalInActiveScope() else { return }
        let workDir = preset.workingDir.isEmpty ? defaultWorkingDirectoryForActiveScope() : preset.workingDir
        _ = addTerminalTab(
            title: preset.name,
            command: preset.command,
            workingDir: workDir,
            providerHint: preset.provider,
            pinTitle: true
        )
        statusBar.updateProvider(preset.provider)
    }

    func presetRunInCurrent(_ preset: AgentPresetItem) {
        guard let fId = focusedPaneId,
              let idx = tabs.indices.first(where: { tabs[$0].tree.findLeaf(fId) != nil }),
              let view = tabs[idx].tree.findLeaf(fId) else { return }
        let cmd = preset.command + "\n"
        view.rememberShellReplay(initialInput: cmd)
        view.executeShellCommand(cmd)
        statusBar.updateProvider(preset.provider)
    }

    func presetOpenInSplit(_ preset: AgentPresetItem) {
        guard canCreateTerminalInActiveScope() else { return }
        let workDir = preset.workingDir.isEmpty ? defaultWorkingDirectoryForActiveScope() : preset.workingDir
        let idx = currentTabIndex
        guard idx >= 0 && idx < tabs.count, let fId = focusedPaneId else { return }

        let newId = UUID().uuidString
        let env = buildPaneEnv(paneId: newId, tabId: tabs[idx].id, provider: preset.provider)
        let newView = makeTerminalView(command: preset.command, workingDir: workDir, extraEnv: env)
        tabs[idx].tree = tabs[idx].tree.splitLeaf(fId, direction: .horizontal, newId: newId, newView: newView)
        focusedPaneId = newId
        trackPaneForActiveWorkspace(newId)
        rebuildCurrentTabContainer()
        statusBar.updateProvider(preset.provider)
    }
}
