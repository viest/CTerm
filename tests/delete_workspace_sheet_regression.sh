#!/usr/bin/env bash
set -euo pipefail

controller="macos/CTerm/MainWindowController.swift"
sheet="macos/CTerm/DeleteWorkspaceSheet.swift"

rg -n 'private var deleteWorkspaceSheet: DeleteWorkspaceSheet\?' "$controller" >/dev/null
rg -n 'let sheet = DeleteWorkspaceSheet\(\)' "$controller" >/dev/null
rg -n 'deleteWorkspaceSheet = sheet' "$controller" >/dev/null
rg -n 'sheet\.show\(relativeTo: window, workspace: workspace\)' "$controller" >/dev/null

if sed -n '/func workspaceDeleteRequested/,/func workspaceOpenInEditor/p' "$controller" | rg -n 'NSAlert|runModal|accessoryView' >/dev/null; then
  echo "workspaceDeleteRequested should not use NSAlert" >&2
  exit 1
fi

rg -n '^final class DeleteWorkspaceSheet: NSObject, NSWindowDelegate \{' "$sheet" >/dev/null
rg -n 'let panelHeight: CGFloat = 262' "$sheet" >/dev/null
rg -n 'var y: CGFloat = panelHeight - 36' "$sheet" >/dev/null
rg -n 'panel\.backgroundColor = AppTheme\.bgSecondary' "$sheet" >/dev/null
rg -n 'panel\.appearance = NSAppearance\(named: \.darkAqua\)' "$sheet" >/dev/null
rg -n 'makeLabel\("Delete Workspace"' "$sheet" >/dev/null
rg -n 'deleteBranchCheckbox = NSButton\(checkboxWithTitle:' "$sheet" >/dev/null
rg -n 'let deleteButton = NSButton\(title: "Delete"' "$sheet" >/dev/null
