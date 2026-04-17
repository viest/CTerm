#!/usr/bin/env bash
set -euo pipefail

file="macos/CTerm/GhosttyTerminalView.swift"

rg -n 'override func doCommand\(by [^)]*Selector\)' "$file" >/dev/null
rg -n 'interpretKeyEvents maps terminal keys like arrows, return, and' "$file" >/dev/null
rg -n 'AppKit fallback here only causes NSBeep\(\)\.' "$file" >/dev/null
! rg -n 'super\.doCommand\(by: commandSelector\)' "$file" >/dev/null
