#!/usr/bin/env bash
set -euo pipefail

main_file="macos/CTerm/MainWindowController.swift"

rg -n 'projectSidebar\.setProjects\(projects\)' "$main_file" >/dev/null
rg -n 'projectSidebar\.setWorkspaces\(workspaces\)' "$main_file" >/dev/null
rg -n 'private func loadWorkspaces\(\)' "$main_file" >/dev/null
rg -n 'let normalized = decoded\.map \{ workspace -> WorkspaceItem in' "$main_file" >/dev/null
rg -n 'var didNormalize = false' "$main_file" >/dev/null
rg -n 'if workspace\.status == \.running \{' "$main_file" >/dev/null
rg -n 'workspace\.status = \.idle' "$main_file" >/dev/null
rg -n 'didNormalize = true' "$main_file" >/dev/null
rg -n 'if didNormalize \{' "$main_file" >/dev/null
rg -n 'saveWorkspaces\(\)' "$main_file" >/dev/null
