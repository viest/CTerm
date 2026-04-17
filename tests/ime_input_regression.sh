#!/usr/bin/env bash
set -euo pipefail

terminal_file="macos/CTerm/GhosttyTerminalView.swift"

rg -n 'private var markedSelectedRange = NSRange\(location: 0, length: 0\)' "$terminal_file" >/dev/null
rg -n 'let hadMarkedText = hasMarkedText\(\)' "$terminal_file" >/dev/null
rg -n 'let hasCommittedText = text\?\.isEmpty == false' "$terminal_file" >/dev/null
rg -n 'if hasMarkedText\(\) \|\| \(hadMarkedText && !hasCommittedText\) \{' "$terminal_file" >/dev/null
rg -n 'if hasMarkedText\(\) \{' "$terminal_file" >/dev/null
rg -n 'updatePreeditText\(""\)' "$terminal_file" >/dev/null
rg -n 'updatePreeditText\(markedText\.string\)' "$terminal_file" >/dev/null
rg -n 'private func updatePreeditText\(_ text: String\) \{' "$terminal_file" >/dev/null
rg -n 'ghostty_surface_preedit\(surface, text, UInt\(text\.utf8\.count\)\)' "$terminal_file" >/dev/null
rg -n 'inputContext\?\.invalidateCharacterCoordinates\(\)' "$terminal_file" >/dev/null
rg -n 'markedSelectedRange = NSRange\(location: 0, length: 0\)' "$terminal_file" >/dev/null
rg -n 'let location = max\(0, min\(selectedRange\.location, markedText\.length\)\)' "$terminal_file" >/dev/null
rg -n 'func selectedRange\(\) -> NSRange \{' "$terminal_file" >/dev/null
rg -n 'return NSRange\(location: 0, length: 0\)' "$terminal_file" >/dev/null
rg -n 'actualRange\?\.pointee = markedRange\(\)' "$terminal_file" >/dev/null
rg -n 'ghostty_surface_ime_point\(surface, &x, &y, &width, &height\)' "$terminal_file" >/dev/null
rg -n 'let backingRect = NSRect\(' "$terminal_file" >/dev/null
rg -n 'let localRect = convertFromBacking\(backingRect\)' "$terminal_file" >/dev/null
