#!/usr/bin/env bash
set -euo pipefail

tab_file="macos/CTerm/TerminalTabBar.swift"

rg -n 'private static let selectedFillColor = NSColor\(white: 0\.18, alpha: 1\)' "$tab_file" >/dev/null
rg -n 'NSBezierPath\(roundedRect: contentRect, xRadius: 4, yRadius: 4\)' "$tab_file" >/dev/null
rg -n 'private var runningTabIds: Set<String> = \[\]' "$tab_file" >/dev/null
rg -n 'func setRunningTabs\(_ ids: Set<String>\)' "$tab_file" >/dev/null
rg -n 'private let loadingIndicator: BrailleLoadingIndicator' "$tab_file" >/dev/null
rg -n 'loadingIndicator\.leadingAnchor\.constraint\(equalTo: leadingAnchor, constant: 10\)' "$tab_file" >/dev/null
rg -n 'private func displayTitle\(\) -> String' "$tab_file" >/dev/null
rg -n 'BrailleLoadingIndicator\.frames\.contains\(String\(first\)\)' "$tab_file" >/dev/null
! rg -n 'NSProgressIndicator' "$tab_file" >/dev/null
if rg -n 'AppTheme\.accent\.setFill\(\)' "$tab_file" >/dev/null; then
  echo "selected terminal tab should not use AppTheme.accent for highlight" >&2
  exit 1
fi

if rg -n 'selectedBorderColor|selectedPath\.stroke\(\)' "$tab_file" >/dev/null; then
  echo "selected terminal tab should not use a border-style highlight" >&2
  exit 1
fi
