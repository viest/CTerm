#!/usr/bin/env bash
set -euo pipefail

main_file="macos/CTerm/MainWindowController.swift"

rg -n 'private static let leftSidebarMinWidth: CGFloat = 180' "$main_file" >/dev/null
rg -n 'private static let leftSidebarMaxWidth: CGFloat = 400' "$main_file" >/dev/null
rg -n 'private static let rightSidebarMinWidth: CGFloat = 220' "$main_file" >/dev/null

rg -n 'private func clampedLeftSidebarWidth\(_ width: CGFloat\) -> CGFloat' "$main_file" >/dev/null
rg -n 'min\(max\(width, Self\.leftSidebarMinWidth\), Self\.leftSidebarMaxWidth\)' "$main_file" >/dev/null
rg -n 'private func clampedRightSidebarWidth\(_ width: CGFloat\) -> CGFloat' "$main_file" >/dev/null
rg -n 'max\(width, Self\.rightSidebarMinWidth\)' "$main_file" >/dev/null

rg -n '"leftWidth": clampedLeftSidebarWidth\(leftSidebarWidth\)' "$main_file" >/dev/null
rg -n '"rightWidth": clampedRightSidebarWidth\(rightSidebarWidth\)' "$main_file" >/dev/null
rg -n 'if let v = layout\["leftWidth"\] as\? CGFloat \{ leftSidebarWidth = clampedLeftSidebarWidth\(v\) \}' "$main_file" >/dev/null
rg -n 'if let v = layout\["rightWidth"\] as\? CGFloat \{ rightSidebarWidth = clampedRightSidebarWidth\(v\) \}' "$main_file" >/dev/null

rg -n 'if leftSidebarVisible \{' "$main_file" >/dev/null
rg -n 'leftSidebarWidth = clampedLeftSidebarWidth\(leftSidebarWidth\)' "$main_file" >/dev/null
rg -n 'if rightSidebarVisible \{' "$main_file" >/dev/null
rg -n 'rightSidebarWidth = clampedRightSidebarWidth\(rightSidebarWidth\)' "$main_file" >/dev/null

rg -n 'return leftSidebarVisible \? Self\.leftSidebarMinWidth : 0' "$main_file" >/dev/null
rg -n 'return Self\.leftSidebarMaxWidth' "$main_file" >/dev/null
rg -n 'leftSidebarWidth = clampedLeftSidebarWidth\(projectSidebar\.frame\.width\)' "$main_file" >/dev/null
