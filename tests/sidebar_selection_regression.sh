#!/usr/bin/env bash
set -euo pipefail

main_file="macos/CTerm/MainWindowController.swift"
sidebar_file="macos/CTerm/ProjectSidebar.swift"

rg -n 'enum ActiveSelection: Equatable' "$sidebar_file" >/dev/null
rg -n 'private var activeSelection: ActiveSelection = \.none' "$sidebar_file" >/dev/null
rg -n 'func setActiveSelection\(_ selection: ActiveSelection\)' "$sidebar_file" >/dev/null
rg -n 'let isLocalSelected = activeSelection == \.local\(project\.id\)' "$sidebar_file" >/dev/null
rg -n 'selected: activeSelection == \.workspace\(ws\.id\)' "$sidebar_file" >/dev/null
rg -n 'AppTheme\.bgTertiary\.setFill\(\)' "$sidebar_file" >/dev/null
rg -n 'AppTheme\.accent\.setFill\(\)' "$sidebar_file" >/dev/null
rg -n 'private func syncSidebarSelection\(\)' "$main_file" >/dev/null
rg -n 'projectSidebar\.setActiveSelection\(\.local\(projectId\)\)' "$main_file" >/dev/null
rg -n 'projectSidebar\.setActiveSelection\(\.workspace\(workspaceId\)\)' "$main_file" >/dev/null
rg -n 'projectSidebar\.setActiveSelection\(\.none\)' "$main_file" >/dev/null
rg -n 'syncSidebarSelection\(\)' "$main_file" >/dev/null
rg -n 'func expandProject\(at index: Int\)' "$sidebar_file" >/dev/null
rg -n 'activateProject\(projects\[0\]\)' "$main_file" >/dev/null
rg -n 'projectSidebar\.expandProject\(at: 0\)' "$main_file" >/dev/null

if rg -n 'case \.project\(|activeSelection == \.project\(' "$sidebar_file" >/dev/null; then
  echo "project headers should not participate in sidebar active selection" >&2
  exit 1
fi

if rg -n 'setActiveSelection\(\.project\(|delegate\?\.projectSelected|func projectSelected\(_ project: ProjectItem\)|selectProject\(at:' "$main_file" "$sidebar_file" >/dev/null; then
  echo "project headers should only expand or collapse, not participate in active selection" >&2
  exit 1
fi
