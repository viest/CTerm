#!/usr/bin/env bash
set -euo pipefail

main_file="macos/CTerm/MainWindowController.swift"
tabbar_file="macos/CTerm/TerminalTabBar.swift"
sheet_file="macos/CTerm/RenameTabSheet.swift"

rg -n 'func tabBar\(_ tabBar: TerminalTabBar, didRequestRenameTabAt index: Int\)' "$tabbar_file" >/dev/null
rg -n 'btn\.onRename = \{ \[weak self\] idx in self\?\.tabRenameRequested\(idx\) \}' "$tabbar_file" >/dev/null
rg -n 'private func tabRenameRequested\(_ index: Int\)' "$tabbar_file" >/dev/null
rg -n 'override func rightMouseDown\(with event: NSEvent\)' "$tabbar_file" >/dev/null
rg -n 'Rename Tab\.\.\.' "$tabbar_file" >/dev/null
rg -n 'else if event\.clickCount == 2 \{' "$tabbar_file" >/dev/null
rg -n 'private func renameVisibleTab\(at index: Int\)' "$main_file" >/dev/null
rg -n 'private var renameTabSheet: RenameTabSheet\?' "$main_file" >/dev/null
rg -n 'renameTabSheet = RenameTabSheet\(\)' "$main_file" >/dev/null
rg -n 'renameTabSheet\?\.show\(relativeTo: window, initialTitle: currentTitle\)' "$main_file" >/dev/null
rg -n 'pinnedTitleTabIds\.insert\(tabId\)' "$main_file" >/dev/null
rg -n 'func tabBar\(_ tabBar: TerminalTabBar, didRequestRenameTabAt index: Int\)' "$main_file" >/dev/null
rg -n 'final class RenameTabSheet: NSObject, NSWindowDelegate' "$sheet_file" >/dev/null
rg -n 'panel\.backgroundColor = AppTheme\.bgSecondary' "$sheet_file" >/dev/null
rg -n 'panel\.appearance = NSAppearance\(named: \.darkAqua\)' "$sheet_file" >/dev/null
rg -n 'titleLabel = makeLabel\("Rename Tab"' "$sheet_file" >/dev/null
rg -n 'makeSettingsTextFieldContainer\(for: titleField, width: fieldWidth, height: 28\)' "$sheet_file" >/dev/null
rg -n 'window\.beginSheet\(panel\)' "$sheet_file" >/dev/null
if rg -n 'alert\.messageText = "Rename Tab"' "$main_file" >/dev/null; then
  echo "tab rename should use the custom dark sheet instead of NSAlert" >&2
  exit 1
fi
