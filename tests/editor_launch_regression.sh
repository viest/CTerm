#!/usr/bin/env bash
set -euo pipefail

models_file="macos/CTerm/Models.swift"
main_file="macos/CTerm/MainWindowController.swift"
quick_open_file="macos/CTerm/QuickOpenPanel.swift"
file_browser_file="macos/CTerm/FileBrowserView.swift"

rg -n 'enum EditorLauncher' "$models_file" >/dev/null
rg -n 'static func open\(path: String, editor: String, line: Int\? = nil\) -> Bool' "$models_file" >/dev/null
rg -n '"code": "Visual Studio Code"' "$models_file" >/dev/null
rg -n '"cursor": "Cursor"' "$models_file" >/dev/null
rg -n '"xcode": "Xcode"' "$models_file" >/dev/null
rg -n -F 'return ["xed", "--line", "\(line)", path]' "$models_file" >/dev/null
rg -n 'let mergedPath = \(existingPathEntries \+ defaultPathEntries\)\.filter \{ seen\.insert\(\$0\)\.inserted \}' "$models_file" >/dev/null
rg -n 'NSSound\.beep\(\)' "$models_file" >/dev/null

rg -n 'EditorLauncher\.open\(path: path, editor: editor\)' "$main_file" >/dev/null
rg -n 'EditorLauncher\.open\(path: project\.path, editor: editor\)' "$main_file" >/dev/null
rg -n 'EditorLauncher\.open\(path: workspace\.worktreePath, editor: editor\)' "$main_file" >/dev/null
rg -n 'EditorLauncher\.open\(path: fullPath, editor: editor\)' "$quick_open_file" >/dev/null
rg -n 'EditorLauncher\.open\(path: node\.path, editor: editor\)' "$file_browser_file" >/dev/null

! rg -n 'process\.arguments = \["-a", editor,' "$main_file" >/dev/null
! rg -n 'process\.arguments = \["-a", editor,' "$quick_open_file" >/dev/null
! rg -n 'process\.arguments = \["-a", editor,' "$file_browser_file" >/dev/null
