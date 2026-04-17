#!/usr/bin/env bash
set -euo pipefail

sidebar_file="macos/CTerm/ProjectSidebar.swift"

rg -n 'func setProjects\(_ projects: \[ProjectItem\]\)' "$sidebar_file" >/dev/null
rg -n 'func setRunningActivity\(localProjectIds: Set<UUID>, workspaceIds: Set<UUID>\)' "$sidebar_file" >/dev/null
rg -n 'private var runningLocalProjectIds: Set<UUID> = \[\]' "$sidebar_file" >/dev/null
rg -n 'private var runningWorkspaceIds: Set<UUID> = \[\]' "$sidebar_file" >/dev/null
rg -n 'self\.projects = projects\.sorted\(by: Self\.sortProjects\)' "$sidebar_file" >/dev/null
rg -n 'private static func sortProjects\(_ lhs: ProjectItem, _ rhs: ProjectItem\) -> Bool' "$sidebar_file" >/dev/null
rg -n 'let lhsName = lhs\.name\.lowercased\(\)' "$sidebar_file" >/dev/null
rg -n 'let lhsPath = lhs\.path\.lowercased\(\)' "$sidebar_file" >/dev/null
rg -n 'return lhs\.id\.uuidString < rhs\.id\.uuidString' "$sidebar_file" >/dev/null

rg -n 'private func avatarColor\(\) -> NSColor' "$sidebar_file" >/dev/null
rg -n 'let stableKey = project\.path\.isEmpty \? project\.name : project\.path' "$sidebar_file" >/dev/null
rg -n 'private static func stableHash\(_ value: String\) -> UInt64' "$sidebar_file" >/dev/null
rg -n 'for byte in value\.utf8 \{' "$sidebar_file" >/dev/null
rg -n 'hash &\*= 1_099_511_628_211' "$sidebar_file" >/dev/null
rg -n 'let color = avatarColor\(\)' "$sidebar_file" >/dev/null
rg -n 'final class BrailleLoadingIndicator: NSTextField' "$sidebar_file" >/dev/null
rg -n 'static let frames = \["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"\]' "$sidebar_file" >/dev/null
rg -n 'private func makeLoadingIndicator\(fontSize: CGFloat\) -> BrailleLoadingIndicator' "$sidebar_file" >/dev/null
rg -n 'font = NSFont\.monospacedSystemFont\(ofSize: fontSize, weight: \.medium\)' "$sidebar_file" >/dev/null
rg -n 'row\.onOpen = \{ \[weak self\] project in' "$sidebar_file" >/dev/null
rg -n 'row\.onOpenInEditor = \{ \[weak self\] project in' "$sidebar_file" >/dev/null
rg -n 'row\.onDelete = \{ \[weak self\] project in' "$sidebar_file" >/dev/null
rg -n 'var onDelete: \(\(ProjectItem\) -> Void\)\?' "$sidebar_file" >/dev/null
rg -n 'override func viewDidMoveToWindow\(\)' "$sidebar_file" >/dev/null
sed -n '/override func viewDidMoveToWindow/,/\/\/ MARK: - Helpers/p' "$sidebar_file" | rg -n 'refreshGitStatusRows\(\)' >/dev/null
rg -n 'func refreshGitStatusRows\(\)' "$sidebar_file" >/dev/null
rg -n 'for arrangedSubview in stackView\.arrangedSubviews \{' "$sidebar_file" >/dev/null
rg -n 'if let row = arrangedSubview as\? WorkspaceDetailRow \{' "$sidebar_file" >/dev/null
rg -n 'if let row = arrangedSubview as\? WorkspaceWorktreeRow \{' "$sidebar_file" >/dev/null
rg -n 'row\.needsDisplay = true' "$sidebar_file" >/dev/null
rg -n 'override func rightMouseDown\(with event: NSEvent\)' "$sidebar_file" >/dev/null
rg -n 'let deleteItem = NSMenuItem\(title: "Remove Repository\.\.\.", action: #selector\(contextDelete\), keyEquivalent: ""\)' "$sidebar_file" >/dev/null
rg -n '@objc private func contextDelete\(\) \{ onDelete\?\(project\) \}' "$sidebar_file" >/dev/null
rg -n 'let isProjectLoading = runningLocalProjectIds\.contains\(project\.id\) \|\| projectWorkspaces\.contains \{ runningWorkspaceIds\.contains\(\$0\.id\) \}' "$sidebar_file" >/dev/null
rg -n 'WorkspaceDetailRow\(project: project, selected: isLocalSelected, isLoading: runningLocalProjectIds\.contains\(project\.id\)\)' "$sidebar_file" >/dev/null
rg -n 'WorkspaceWorktreeRow\(' "$sidebar_file" >/dev/null
rg -n 'isLoading: runningWorkspaceIds\.contains\(ws\.id\)' "$sidebar_file" >/dev/null
rg -n 'let indicator = makeLoadingIndicator\(fontSize: 12\.5\)' "$sidebar_file" >/dev/null
rg -n 'let indicator = makeLoadingIndicator\(fontSize: 11\.5\)' "$sidebar_file" >/dev/null

rg -n 'nameParagraphStyle\.lineBreakMode = \.byTruncatingTail' "$sidebar_file" >/dev/null
rg -n 'let controlsLeftX = bounds\.width - 52' "$sidebar_file" >/dev/null
rg -n 'let minimumNameWidth: CGFloat = 44' "$sidebar_file" >/dev/null
rg -n 'let showsCount = \(controlsLeftX - nameX\) >= \(minimumNameWidth \+ countSpacing \+ countW\)' "$sidebar_file" >/dev/null
rg -n 'let nameRect = NSRect\(x: nameX, y: nameY - 1, width: max\(0, nameMaxX - nameX\), height: nameRectHeight\)' "$sidebar_file" >/dev/null
rg -n 'nameAttrString\.draw\(with: nameRect, options: \[\.usesLineFragmentOrigin, \.truncatesLastVisibleLine\]\)' "$sidebar_file" >/dev/null
rg -n 'if showsCount \{' "$sidebar_file" >/dev/null
rg -n 'private func agentLabel\(\) -> String' "$sidebar_file" >/dev/null
rg -n 'if loweredCommand\.contains\("codex"\) \{ return "Codex" \}' "$sidebar_file" >/dev/null
rg -n 'private func makeTruncatingAttributes\(font: NSFont, color: NSColor\) -> \[NSAttributedString\.Key: Any\]' "$sidebar_file" >/dev/null
rg -n 'let maxAgentWidth = min\(84, bounds\.width \* 0\.32\)' "$sidebar_file" >/dev/null
rg -n 'let contentMaxX = max\(padLeft, agentRect\.minX - 10\)' "$sidebar_file" >/dev/null
rg -n 'heightAnchor\.constraint\(equalToConstant: 44\)\.isActive = true' "$sidebar_file" >/dev/null
rg -n 'AppTheme\.border\.withAlphaComponent\(0\.8\)\.setFill\(\)' "$sidebar_file" >/dev/null
rg -n 'NSRect\(x: 24, y: 0, width: bounds\.width - 36, height: 1\)\.fill\(\)' "$sidebar_file" >/dev/null
rg -n 'nameAttrString\.draw\(with: nameRect, options: \[\.usesLineFragmentOrigin, \.truncatesLastVisibleLine\]\)' "$sidebar_file" >/dev/null
rg -n 'branchAttrString\.draw\(with: branchRect, options: \[\.usesLineFragmentOrigin, \.truncatesLastVisibleLine\]\)' "$sidebar_file" >/dev/null
! rg -n 'let agentStr = workspace\.agentCommand as NSString' "$sidebar_file" >/dev/null
! rg -n 'NSProgressIndicator' "$sidebar_file" >/dev/null
! rg -n 'hashValue' "$sidebar_file" >/dev/null
! rg -n 'if lhs\.pinned != rhs\.pinned \{' "$sidebar_file" >/dev/null
! rg -n 'if lhs\.lastOpened != rhs\.lastOpened \{' "$sidebar_file" >/dev/null
! rg -n 'return \$0\.lastOpened > \$1\.lastOpened' "$sidebar_file" >/dev/null
! rg -n 'gitStatusRefreshTimer' "$sidebar_file" >/dev/null
! rg -n 'gitStatusRefreshInterval' "$sidebar_file" >/dev/null
! rg -n 'updateGitStatusRefreshTimer\(\)' "$sidebar_file" >/dev/null
