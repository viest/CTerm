#!/usr/bin/env bash
set -euo pipefail

main_file="macos/CTerm/MainWindowController.swift"
session_file="macos/CTerm/SessionPersistence.swift"
ghostty_file="macos/CTerm/GhosttyTerminalView.swift"

rg -n 'struct GroupState: Codable' "$session_file" >/dev/null
rg -n 'let initialInput: String\?' "$session_file" >/dev/null
rg -n 'let projectId: UUID\?' "$session_file" >/dev/null
rg -n 'let primaryGroup: GroupState' "$session_file" >/dev/null
rg -n 'let projectGroups: \[GroupState\]' "$session_file" >/dev/null
rg -n 'let workspaceGroups: \[GroupState\]' "$session_file" >/dev/null
rg -n 'let activeProjectId: UUID\?' "$session_file" >/dev/null
rg -n 'let activeWorkspaceId: UUID\?' "$session_file" >/dev/null
rg -n 'func saveSession\(groups: \[GroupSnapshotInput\], activeProjectId: UUID\?, activeWorkspaceId: UUID\?\)' "$session_file" >/dev/null
rg -n 'let primaryGroup = groups\.first\(where: \{ \$0\.projectId == nil && \$0\.workspaceId == nil \}\)' "$session_file" >/dev/null
rg -n 'cwd: leaf\.view\.currentWorkingDir \?\? leaf\.view\.launchWorkingDir' "$session_file" >/dev/null
rg -n 'command: leaf\.view\.launchCommand' "$session_file" >/dev/null
rg -n 'initialInput: leaf\.view\.launchInitialInput' "$session_file" >/dev/null
rg -n 'private struct ScopedSessionStateV1: Codable' "$session_file" >/dev/null
rg -n 'private struct LegacySessionState: Codable' "$session_file" >/dev/null
rg -n 'primaryTerminalState = restoreTerminalGroup\(from: session\.primaryGroup\)' "$main_file" >/dev/null
rg -n 'projectTerminalStates\[projectId\] = restoreTerminalGroup\(from: group\)' "$main_file" >/dev/null
rg -n 'workspaceTerminalStates\[workspaceId\] = restoreTerminalGroup\(from: group\)' "$main_file" >/dev/null
rg -n 'private func restoreTerminalGroup\(from group: SessionPersistence\.GroupState\) -> TerminalGroupState' "$main_file" >/dev/null
rg -n 'private var pinnedTitleTabIds: Set<String> = \[\]' "$main_file" >/dev/null
rg -n 'pinnedTitleTabIds\.removeAll\(\)' "$main_file" >/dev/null
rg -n 'pinnedTitleTabIds\.insert\(tabState\.tabId\)' "$main_file" >/dev/null
rg -n 'private func terminalScope\(for group: SessionPersistence\.GroupState\) -> TerminalScope' "$main_file" >/dev/null
rg -n 'private func buildRestoredSplitTree\(from snapshot: SplitTreeSnapshot,' "$main_file" >/dev/null
rg -n 'scope: TerminalScope\) -> SplitNode' "$main_file" >/dev/null
rg -n 'case "split":' "$main_file" >/dev/null
rg -n 'let direction: SplitDirection = snapshot\.direction == "vertical" \? \.vertical : \.horizontal' "$main_file" >/dev/null
rg -n 'let ratio = min\(max\(snapshot\.ratio \?\? 0\.5, 0\.1\), 0\.9\)' "$main_file" >/dev/null
rg -n 'private func makeRestoredLeaf\(paneId: String\?,' "$main_file" >/dev/null
rg -n 'case \.workspace\(let workspaceId\):' "$main_file" >/dev/null
rg -n 'case \.project:' "$main_file" >/dev/null
rg -n 'command: paneState\?\.command \?\? "/bin/zsh"' "$main_file" >/dev/null
rg -n 'initialInput: paneState\?\.initialInput' "$main_file" >/dev/null
rg -n 'guard !pinnedTitleTabIds\.contains\(tabs\[location\.tabIndex\]\.id\) else \{ return \}' "$main_file" >/dev/null
rg -n 'pinnedTitleTabIds\.remove\(tab\.id\)' "$main_file" >/dev/null
rg -n 'view\.rememberShellReplay\(initialInput: cmd\)' "$main_file" >/dev/null
rg -n 'private\(set\) var launchCommand: String\?' "$ghostty_file" >/dev/null
rg -n 'private\(set\) var launchInitialInput: String\?' "$ghostty_file" >/dev/null
rg -n 'func rememberShellReplay\(initialInput: String, workingDir: String\? = nil\)' "$ghostty_file" >/dev/null
if rg -n 'focusedPaneId = session\.focusedPaneId' "$main_file" >/dev/null; then
  echo "session restore should rebuild isolated terminal groups instead of restoring a single global tab list" >&2
  exit 1
fi
