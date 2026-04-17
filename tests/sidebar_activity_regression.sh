#!/usr/bin/env bash
set -euo pipefail

main_file="macos/CTerm/MainWindowController.swift"
ghostty_file="macos/CTerm/GhosttyTerminalView.swift"
tab_bar_file="macos/CTerm/TerminalTabBar.swift"

rg -n 'private var runningLocalProjectCommandCounts: \[UUID: Int\] = \[:\]' "$main_file" >/dev/null
rg -n 'private var runningWorkspaceCommandCounts: \[UUID: Int\] = \[:\]' "$main_file" >/dev/null
rg -n 'private var runningAgentPaneCounts: \[String: Int\] = \[:\]' "$main_file" >/dev/null
rg -n 'private var runningAgentPaneScopes: \[String: TerminalScope\] = \[:\]' "$main_file" >/dev/null
rg -n 'private var runningAgentPaneLastStartedAt: \[String: Date\] = \[:\]' "$main_file" >/dev/null
rg -n 'private var liveObservedAgentPaneIds: Set<String> = \[\]' "$main_file" >/dev/null
rg -n 'private var liveRunningAgentPaneIds: Set<String> = \[\]' "$main_file" >/dev/null
rg -n 'private let agentActivityQueue = DispatchQueue\(label: "cterm\.agent-activity", qos: \.utility\)' "$main_file" >/dev/null
rg -n 'private var agentActivityRefreshInFlight = false' "$main_file" >/dev/null
rg -n 'private var agentActivityRefreshPending = false' "$main_file" >/dev/null
rg -n 'private var agentActivityRefreshGeneration = 0' "$main_file" >/dev/null
rg -n 'private func refreshSidebarActivityIndicators\(\)' "$main_file" >/dev/null
rg -n 'private func startAgentActivityMonitoring\(\)' "$main_file" >/dev/null
rg -n 'private func refreshLiveAgentActivity\(\)' "$main_file" >/dev/null
rg -n 'private func codexSessionActivity\(for directories: Set<String>\)' "$main_file" >/dev/null
rg -n 'private func codexSessionFileState\(for file: URL\)' "$main_file" >/dev/null
rg -n 'private func parseCodexSessionFile\(_ file: URL,' "$main_file" >/dev/null
rg -n 'private func parseCodexSessionWorkingDirectory\(from contents: String\) -> String\?' "$main_file" >/dev/null
rg -n 'private func parseJSONStringValue\(in contents: String, startingAt index: String\.Index\) -> String\?' "$main_file" >/dev/null
rg -n 'private func readPrefixString\(from file: URL, byteCount: Int\) -> String\?' "$main_file" >/dev/null
rg -n 'let prefixContents = knownCwd == nil \? readPrefixString\(from: file, byteCount: 16_384\) : nil' "$main_file" >/dev/null
rg -n 'let tailContents = readTailString\(from: file, byteCount: 65_536\)' "$main_file" >/dev/null
rg -n 'Timer\.scheduledTimer\(withTimeInterval: 2\.0, repeats: true\)' "$main_file" >/dev/null
rg -n 'agentActivityTimer\?\.tolerance = 0\.5' "$main_file" >/dev/null
rg -n 'agentActivityQueue\.async' "$main_file" >/dev/null
rg -n 'DispatchQueue\.main\.async' "$main_file" >/dev/null
rg -n 'liveObservedAgentPaneIds = \[\]' "$main_file" >/dev/null
rg -n 'self\.liveObservedAgentPaneIds = Set\(' "$main_file" >/dev/null
rg -n 'lineText\.contains\("\\\"type\\\":\\\"event_msg\\\""\)' "$main_file" >/dev/null
rg -n 'lineText\.contains\("\\\"type\\\":\\\"task_started\\\""\)' "$main_file" >/dev/null
rg -n 'lineText\.contains\("\\\"type\\\":\\\"task_complete\\\""\)' "$main_file" >/dev/null
rg -n 'contents\.range\(of: "\\\"type\\\":\\\"session_meta\\\""\)' "$main_file" >/dev/null
rg -n 'range\(of: "\\\"cwd\\\":\\\""\)' "$main_file" >/dev/null
rg -n 'private func effectiveRunningPaneIds\(allPanes: \[PaneReference\]\) -> Set<String>' "$main_file" >/dev/null
rg -n 'private func clearObservedIdleCodexPaneCounts\(_ trackedPanes: \[TrackedAgentPane\]\)' "$main_file" >/dev/null
rg -n 'var runningPaneIds = liveRunningAgentPaneIds' "$main_file" >/dev/null
rg -n 'for \(paneId, count\) in runningAgentPaneCounts where count > 0 \{' "$main_file" >/dev/null
rg -n 'guard panesById\[paneId\] != nil else \{ continue \}' "$main_file" >/dev/null
rg -n 'runningPaneIds\.insert\(paneId\)' "$main_file" >/dev/null
rg -n 'clearObservedIdleCodexPaneCounts\(codexTrackedPanes\)' "$main_file" >/dev/null
rg -n 'liveObservedAgentPaneIds\.contains\(pane\.paneId\)' "$main_file" >/dev/null
rg -n '!liveRunningAgentPaneIds\.contains\(pane\.paneId\)' "$main_file" >/dev/null
rg -n 'runningAgentPaneCounts\[pane\.paneId, default: 0\] > 0' "$main_file" >/dev/null
rg -n 'runningAgentPaneLastStartedAt\[paneId\] = Date\(\)' "$main_file" >/dev/null
rg -n 'runningAgentPaneLastStartedAt\.removeValue\(forKey: paneId\)' "$main_file" >/dev/null
rg -n 'projectSidebar\.setRunningActivity\(' "$main_file" >/dev/null
rg -n 'tabBar\.setRunningTabs\(' "$main_file" >/dev/null
rg -n 'let cwd = view.launchWorkingDir \?\? view.currentWorkingDir' "$main_file" >/dev/null
rg -n 'private func markAgentTaskStarted\(scope: TerminalScope, paneId: String\)' "$main_file" >/dev/null
rg -n 'private func completeAgentTask\(for paneId: String, exitCode: Int16\) -> Bool' "$main_file" >/dev/null
rg -n 'private func clearRunningAgentTasks\(for paneId: String, workspaceStatus: WorkspaceItem\.WorkspaceStatus\? = \.idle\)' "$main_file" >/dev/null
rg -n 'clearRunningAgentTasks\(for: leaf\.id\)' "$main_file" >/dev/null
rg -n 'clearRunningAgentTasks\(for: fId\)' "$main_file" >/dev/null
rg -n 'if let terminal = self\?\.addTerminalTab\(title: ".*agent\.name.*ws\.name.*", workingDir: worktreePath, initialInput: agentInput\) \{' "$main_file" >/dev/null
rg -n 'self\?\.markAgentTaskStarted\(scope: \.workspace\(wsId\), paneId: terminal\.paneId\)' "$main_file" >/dev/null
rg -n 'markAgentTaskStarted\(scope: activeTerminalScope, paneId: terminal\.paneId\)' "$main_file" >/dev/null
rg -n 'markAgentTaskStarted\(scope: activeTerminalScope, paneId: fId\)' "$main_file" >/dev/null
rg -n 'markAgentTaskStarted\(scope: activeTerminalScope, paneId: newId\)' "$main_file" >/dev/null
rg -n 'let tracked = completeAgentTask\(for: location\.paneId, exitCode: exitCode\)' "$main_file" >/dev/null
rg -n 'private func handleTerminalExit\(view: GhosttyTerminalView\)' "$main_file" >/dev/null
rg -n 'var onTerminalExit: \(\(\) -> Void\)\?' "$ghostty_file" >/dev/null
rg -n 'v\.onTerminalExit\?\(\)' "$ghostty_file" >/dev/null
rg -n 'func setRunningTabs\(_ ids: Set<String>\)' "$tab_bar_file" >/dev/null

if rg -n 'String\(contentsOf: file, encoding: \.utf8\)' "$main_file" >/dev/null; then
  echo "codex session activity should not read entire session files just to discover cwd" >&2
  exit 1
fi

if sed -n '/private func parseCodexSessionFile/,/private func readPrefixString/p' "$main_file" | rg -n 'JSONSerialization' >/dev/null; then
  echo "codex session parsing should not JSON decode every scanned line" >&2
  exit 1
fi

if rg -n 'observedCodexSessionDirectories' "$main_file" >/dev/null; then
  echo "sidebar activity should track observed codex panes directly instead of directory-level shadow state" >&2
  exit 1
fi
