#!/usr/bin/env bash
set -euo pipefail

main_file="macos/CTerm/MainWindowController.swift"

rg -n 'private func canCreateTerminalInActiveScope\(\) -> Bool \{' "$main_file" >/dev/null
rg -n 'case \.project, \.workspace:' "$main_file" >/dev/null
rg -n 'case \.primary:' "$main_file" >/dev/null
rg -n 'return currentProject == nil' "$main_file" >/dev/null

sed -n '/@objc func newTerminalTab/,/@objc func closeCurrentTab/p' "$main_file" | rg -n 'guard canCreateTerminalInActiveScope\(\) else \{ return \}' >/dev/null
sed -n '/func newTerminalRequested/,/func presetSelected/p' "$main_file" | rg -n 'guard canCreateTerminalInActiveScope\(\) else \{ return \}' >/dev/null
sed -n '/func presetSelected/,/func presetRunInCurrent/p' "$main_file" | rg -n 'guard canCreateTerminalInActiveScope\(\) else \{ return \}' >/dev/null
sed -n '/func presetOpenInSplit/,/statusBar.updateProvider/p' "$main_file" | rg -n 'guard canCreateTerminalInActiveScope\(\) else \{ return \}' >/dev/null
