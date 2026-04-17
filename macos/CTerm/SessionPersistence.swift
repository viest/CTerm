import AppKit

/// Manages save/restore of terminal session state across app launches.
class SessionPersistence {
    static let shared = SessionPersistence()

    private let baseDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".cterm/terminal-sessions")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let sessionFile: URL

    private init() {
        sessionFile = baseDir.appendingPathComponent("session.json")
    }

    // MARK: - Data Structures

    struct PaneState: Codable {
        let paneId: String
        let cwd: String?
        let command: String?
        let initialInput: String?
    }

    struct TabState: Codable {
        let tabId: String
        let title: String
        let treeSnapshot: SplitTreeSnapshot
        let panes: [PaneState]
    }

    struct GroupState: Codable {
        let projectId: UUID?
        let workspaceId: UUID?
        let tabs: [TabState]
        let focusedPaneId: String?
        let selectedTabIndex: Int
    }

    struct SessionState: Codable {
        let primaryGroup: GroupState
        let projectGroups: [GroupState]
        let workspaceGroups: [GroupState]
        let activeProjectId: UUID?
        let activeWorkspaceId: UUID?
        let timestamp: Date
    }

    struct GroupSnapshotInput {
        let projectId: UUID?
        let workspaceId: UUID?
        let tabs: [(id: String, title: String, tree: SplitNode)]
        let focusedPaneId: String?
        let selectedTabIndex: Int
    }

    private struct ScopedSessionStateV1: Codable {
        let primaryGroup: GroupState
        let workspaceGroups: [GroupState]
        let activeWorkspaceId: UUID?
        let timestamp: Date
    }

    private struct LegacySessionState: Codable {
        let tabs: [TabState]
        let focusedPaneId: String?
        let selectedTabIndex: Int
        let timestamp: Date
    }

    // MARK: - Save

    func saveSession(groups: [GroupSnapshotInput], activeProjectId: UUID?, activeWorkspaceId: UUID?) {
        let primaryGroup = groups.first(where: { $0.projectId == nil && $0.workspaceId == nil }) ?? GroupSnapshotInput(
            projectId: nil,
            workspaceId: nil,
            tabs: [],
            focusedPaneId: nil,
            selectedTabIndex: 0
        )

        let session = SessionState(
            primaryGroup: makeGroupState(from: primaryGroup),
            projectGroups: groups
                .filter { $0.projectId != nil }
                .map(makeGroupState(from:)),
            workspaceGroups: groups
                .filter { $0.workspaceId != nil }
                .map(makeGroupState(from:)),
            activeProjectId: activeProjectId,
            activeWorkspaceId: activeWorkspaceId,
            timestamp: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(session) {
            try? data.write(to: sessionFile)
        }

        // Save scrollback for each pane across every terminal group.
        for group in groups {
            for tab in group.tabs {
                let leaves = tab.tree.allLeaves()
                for leaf in leaves {
                    saveScrollback(paneId: leaf.id, surface: leaf.view.ghosttySurface)
                }
            }
        }
    }

    private func makeGroupState(from group: GroupSnapshotInput) -> GroupState {
        var tabStates: [TabState] = []

        for tab in group.tabs {
            let snapshot = SplitTreeSnapshot.from(tab.tree)
            let leaves = tab.tree.allLeaves()

            let panes = leaves.map { leaf in
                PaneState(
                    paneId: leaf.id,
                    cwd: leaf.view.currentWorkingDir ?? leaf.view.launchWorkingDir,
                    command: leaf.view.launchCommand,
                    initialInput: leaf.view.launchInitialInput
                )
            }

            tabStates.append(TabState(
                tabId: tab.id,
                title: tab.title,
                treeSnapshot: snapshot,
                panes: panes
            ))
        }

        return GroupState(
            projectId: group.projectId,
            workspaceId: group.workspaceId,
            tabs: tabStates,
            focusedPaneId: group.focusedPaneId,
            selectedTabIndex: group.selectedTabIndex
        )
    }

    private func saveScrollback(paneId: String, surface: ghostty_surface_t?) {
        guard let surface else { return }

        let paneDir = baseDir.appendingPathComponent(paneId)
        try? FileManager.default.createDirectory(at: paneDir, withIntermediateDirectories: true)

        var text = ghostty_text_s()
        if ghostty_surface_has_selection(surface) {
            if ghostty_surface_read_selection(surface, &text) {
                let content = String(cString: text.text)
                try? content.write(to: paneDir.appendingPathComponent("scrollback.txt"), atomically: true, encoding: .utf8)
                ghostty_surface_free_text(surface, &text)
            }
        }
    }

    // MARK: - Load

    func loadSession() -> SessionState? {
        guard FileManager.default.fileExists(atPath: sessionFile.path) else { return nil }
        guard let data = try? Data(contentsOf: sessionFile) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let session = try? decoder.decode(SessionState.self, from: data) {
            return session
        }

        if let scopedV1 = try? decoder.decode(ScopedSessionStateV1.self, from: data) {
            return SessionState(
                primaryGroup: scopedV1.primaryGroup,
                projectGroups: [],
                workspaceGroups: scopedV1.workspaceGroups,
                activeProjectId: nil,
                activeWorkspaceId: scopedV1.activeWorkspaceId,
                timestamp: scopedV1.timestamp
            )
        }

        guard let legacy = try? decoder.decode(LegacySessionState.self, from: data) else { return nil }
        return SessionState(
            primaryGroup: GroupState(
                projectId: nil,
                workspaceId: nil,
                tabs: legacy.tabs,
                focusedPaneId: legacy.focusedPaneId,
                selectedTabIndex: legacy.selectedTabIndex
            ),
            projectGroups: [],
            workspaceGroups: [],
            activeProjectId: nil,
            activeWorkspaceId: nil,
            timestamp: legacy.timestamp
        )
    }

    func readScrollback(paneId: String) -> String? {
        let path = baseDir.appendingPathComponent(paneId).appendingPathComponent("scrollback.txt")
        return try? String(contentsOf: path, encoding: .utf8)
    }

    // MARK: - Cleanup

    func clearSession() {
        try? FileManager.default.removeItem(at: sessionFile)

        // Clean up scrollback files
        if let contents = try? FileManager.default.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) {
            for item in contents where item.lastPathComponent != "session.json" {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }
}
