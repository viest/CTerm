#!/usr/bin/env bash
set -euo pipefail

main_file="macos/CTerm/MainWindowController.swift"
changes_file="macos/CTerm/ChangesPanel.swift"
browser_file="macos/CTerm/FileBrowserView.swift"

rg -n 'private static let gitRefreshInterval: TimeInterval = 5' "$main_file" >/dev/null
rg -n 'private var gitRefreshTimer: Timer\?' "$main_file" >/dev/null
rg -n 'gitRefreshTimer\?\.invalidate\(\)' "$main_file" >/dev/null
rg -n 'updateGitRefreshTimer\(\)' "$main_file" >/dev/null
rg -n 'private func updateGitRefreshTimer\(\)' "$main_file" >/dev/null
rg -n 'let timer = Timer\(timeInterval: Self\.gitRefreshInterval, repeats: true\)' "$main_file" >/dev/null
rg -n 'private func refreshGitStatusSurfaces\(\)' "$main_file" >/dev/null
sed -n '/private func refreshGitStatusSurfaces/,/private func makeSidebarTab/p' "$main_file" | rg -n 'projectSidebar\.refreshGitStatusRows\(\)' >/dev/null
sed -n '/private func refreshGitStatusSurfaces/,/private func makeSidebarTab/p' "$main_file" | rg -n 'syncRightSidebarProjectContext\(forceRefresh: !changesPanel\.isHidden\)' >/dev/null
rg -n 'changesPanel\.onGitRepositoryMutated = \{ \[weak self\] in' "$main_file" >/dev/null
rg -n 'self\?\.projectSidebar\.refreshGitStatusRows\(\)' "$main_file" >/dev/null

rg -n 'private func projectContaining\(path: String\?\) -> ProjectItem\?' "$main_file" >/dev/null
rg -n 'private func focusedTerminalView\(\) -> GhosttyTerminalView\?' "$main_file" >/dev/null
rg -n 'private func resolvedRightSidebarPath\(\) -> String\?' "$main_file" >/dev/null
sed -n '/private func resolvedRightSidebarPath/,/private func openWorkspaceTerminal/p' "$main_file" | rg -n 'let focusedView = focusedTerminalView\(\)' >/dev/null
sed -n '/private func resolvedRightSidebarPath/,/private func openWorkspaceTerminal/p' "$main_file" | rg -n 'let focusedPath = focusedView\?\.currentWorkingDir \?\? focusedView\?\.launchWorkingDir' >/dev/null
sed -n '/private func resolvedRightSidebarPath/,/private func openWorkspaceTerminal/p' "$main_file" | rg -n 'workspaceContaining\(path: focusedPath\)' >/dev/null
sed -n '/private func resolvedRightSidebarPath/,/private func openWorkspaceTerminal/p' "$main_file" | rg -n 'projectContaining\(path: focusedPath\)' >/dev/null

rg -n 'private func syncRightSidebarProjectContext\(forceRefresh: Bool = false\)' "$main_file" >/dev/null
sed -n '/private func syncRightSidebarProjectContext/,/private func loadProjectPresets/p' "$main_file" | rg -n 'let path = resolvedRightSidebarPath\(\)' >/dev/null
rg -n 'changesPanel\.currentProjectPath = path' "$main_file" >/dev/null
rg -n 'fileBrowser\.projectPath = path' "$main_file" >/dev/null
rg -n 'changesPanel\.refreshIfNeeded\(force: forceRefresh\)' "$main_file" >/dev/null
rg -n 'fileBrowser\.reloadIfNeeded\(force: forceRefresh\)' "$main_file" >/dev/null
sed -n '/@objc func toggleRightSidebar/,/private func presentSettingsWindow/p' "$main_file" | rg -n 'syncRightSidebarProjectContext\(forceRefresh: true\)' >/dev/null
sed -n '/@objc func refreshRightSidebar/,/@objc func rightSidebarTabClicked/p' "$main_file" | rg -n 'projectSidebar\.refreshGitStatusRows\(\)' >/dev/null
sed -n '/@objc func rightSidebarTabClicked/,/private func updateGitRefreshTimer/p' "$main_file" | rg -n 'syncRightSidebarProjectContext\(forceRefresh: showChanges\)' >/dev/null
sed -n '/private func activateProject/,/private func loadProjectPresets/p' "$main_file" | rg -n 'syncRightSidebarProjectContext\(\)' >/dev/null
sed -n '/private func showTab/,/private func removeTab/p' "$main_file" | rg -n 'syncRightSidebarProjectContext\(forceRefresh: true\)' >/dev/null
sed -n '/private func handlePaneClicked/,/\/\/ MARK: - Data Management/p' "$main_file" | rg -n 'syncRightSidebarProjectContext\(forceRefresh: true\)' >/dev/null

rg -n 'func refreshIfNeeded\(force: Bool = false\)' "$changes_file" >/dev/null
rg -n 'guard shouldPollForChanges, !refreshInFlight, needsRefresh, let path = currentProjectPath else \{ return \}' "$changes_file" >/dev/null
rg -n 'runGit\(\["status", "--porcelain=1", "--branch"\], at: path\)' "$changes_file" >/dev/null
rg -n 'private func loadNumstat\(_ baseArgs: \[String\], paths: Set<String>, at path: String\) -> \[String: \(Int, Int\)\]' "$changes_file" >/dev/null

rg -n 'private var reloadInFlight = false' "$browser_file" >/dev/null
rg -n 'private var needsReload = false' "$browser_file" >/dev/null
rg -n 'func reloadIfNeeded\(force: Bool = false\)' "$browser_file" >/dev/null
rg -n 'private var shouldLoadContents: Bool \{' "$browser_file" >/dev/null
rg -n 'guard shouldLoadContents, !reloadInFlight, needsReload, let path = projectPath, !path.isEmpty, path != "/" else \{ return \}' "$browser_file" >/dev/null
