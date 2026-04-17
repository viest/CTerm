#!/usr/bin/env bash
set -euo pipefail

main_file="macos/CTerm/MainWindowController.swift"
sidebar_file="macos/CTerm/ProjectSidebar.swift"

rg -n 'private enum TerminalScope: Equatable' "$main_file" >/dev/null
rg -n 'private var activeTerminalScope: TerminalScope = \.primary' "$main_file" >/dev/null
rg -n 'private var projectTerminalStates: \[UUID: TerminalGroupState\] = \[:\]' "$main_file" >/dev/null
rg -n 'private var workspaceTerminalStates: \[UUID: TerminalGroupState\] = \[:\]' "$main_file" >/dev/null
rg -n 'private func switchTerminalScope\(to scope: TerminalScope\)' "$main_file" >/dev/null
rg -n 'func projectLocalSelected\(_ project: ProjectItem\)' "$main_file" >/dev/null
rg -n 'switchTerminalScope\(to: \.project\(project\.id\)\)' "$main_file" >/dev/null
rg -n 'private func openProjectTerminal\(_ project: ProjectItem\)' "$main_file" >/dev/null
rg -n 'func projectLocalSelected\(_ project: ProjectItem\)' "$sidebar_file" >/dev/null
rg -n 'localRow\.onClick = \{ \[weak self\] p in self\?\.delegate\?\.projectLocalSelected\(p\) \}' "$sidebar_file" >/dev/null
rg -n 'override func mouseDown\(with event: NSEvent\) \{ onClick\?\(project\) \}' "$sidebar_file" >/dev/null
rg -n 'private func openWorkspaceTerminal\(_ workspace: WorkspaceItem\)' "$main_file" >/dev/null
rg -n 'private func trackPaneForActiveWorkspace\(_ paneId: String\)' "$main_file" >/dev/null
rg -n 'func workspaceSelected\(_ workspace: WorkspaceItem\) \{' "$main_file" >/dev/null
rg -n 'switchTerminalScope\(to: \.workspace\(workspace\.id\)\)' "$main_file" >/dev/null
rg -n 'if tabs\.isEmpty \{' "$main_file" >/dev/null
rg -n 'openWorkspaceTerminal\(workspace\)' "$main_file" >/dev/null
if rg -n 'private func findWorkspaceTerminal' "$main_file" >/dev/null; then
    echo "workspace terminals should be isolated by scope instead of searching a shared tab list" >&2
    exit 1
fi
if rg -n 'private func focusWorkspaceTerminal' "$main_file" >/dev/null; then
    echo "workspace switching should restore its terminal group instead of focusing a pane in the shared group" >&2
    exit 1
fi
