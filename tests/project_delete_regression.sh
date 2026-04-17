#!/usr/bin/env bash
set -euo pipefail

controller="macos/CTerm/MainWindowController.swift"
sidebar="macos/CTerm/ProjectSidebar.swift"

rg -n 'func projectRemoved\(_ project: ProjectItem\)' "$controller" >/dev/null
rg -n 'private func discardProjectTerminalState\(_ projectId: UUID\)' "$controller" >/dev/null
rg -n 'let relatedWorkspaces = workspaces\.filter \{ \$0\.projectId == project\.id \}' "$controller" >/dev/null
rg -n 'alert\.messageText = "Remove Repository"' "$controller" >/dev/null
rg -n 'Files on disk stay unchanged' "$controller" >/dev/null
rg -n 'Files on disk and existing worktrees stay unchanged' "$controller" >/dev/null
rg -n 'discardWorkspaceTerminalState\(workspace\)' "$controller" >/dev/null
rg -n 'discardProjectTerminalState\(project\.id\)' "$controller" >/dev/null
rg -n 'workspaces\.removeAll \{ relatedWorkspaceIds\.contains\(\$0\.id\) \}' "$controller" >/dev/null
rg -n 'saveWorkspaces\(\)' "$controller" >/dev/null
rg -n 'saveProjects\(\)' "$controller" >/dev/null
rg -n 'projectSidebar\.setWorkspaces\(workspaces\)' "$controller" >/dev/null
rg -n 'projectSidebar\.setProjects\(projects\)' "$controller" >/dev/null
rg -n 'switchTerminalScope\(to: \.project\(replacementProject\.id\)\)' "$controller" >/dev/null
rg -n 'switchTerminalScope\(to: \.primary\)' "$controller" >/dev/null
rg -n 'loadProjectPresets\(for: replacementProject\)' "$controller" >/dev/null
rg -n 'refreshPresetBarPresets\(\)' "$controller" >/dev/null

if sed -n '/func projectRemoved/,/func addProjectRequested/p' "$controller" | rg -n 'FileManager\.default\.removeItem|git worktree remove|branch -D' >/dev/null; then
  echo "project removal should only detach sidebar metadata, not delete files from disk" >&2
  exit 1
fi

if ! sed -n '/override func rightMouseDown/,/@objc private func contextDelete/p' "$sidebar" | rg -n 'Remove Repository\.\.\.' >/dev/null; then
  echo "project sidebar rows should expose a remove repository context menu entry" >&2
  exit 1
fi
