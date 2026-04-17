#!/usr/bin/env bash
set -euo pipefail

ghostty_file="macos/CTerm/GhosttyTerminalView.swift"
main_file="macos/CTerm/MainWindowController.swift"

rg -n 'private static let returnKeyCode: UInt32 = 36' "$ghostty_file" >/dev/null
rg -n 'func executeShellCommand\(_ command: String\)' "$ghostty_file" >/dev/null
rg -n 'let body = command\.trimmingCharacters\(in: CharacterSet\(charactersIn: "\\r\\n"\)\)' "$ghostty_file" >/dev/null
rg -n 'let trailingNewlineCount = command\.reversed\(\)\.prefix \{ \$0 == "\\n" \|\| \$0 == "\\r" \}\.count' "$ghostty_file" >/dev/null
rg -n 'ghostty_surface_text\(surface, body, UInt\(body\.utf8\.count\)\)' "$ghostty_file" >/dev/null
rg -n 'sendReturnKey\(to: surface\)' "$ghostty_file" >/dev/null
rg -n 'private func sendReturnKey\(to surface: ghostty_surface_t\)' "$ghostty_file" >/dev/null
rg -n 'keyEv\.keycode = Self\.returnKeyCode' "$ghostty_file" >/dev/null
rg -n 'keyEv\.unshifted_codepoint = 13' "$ghostty_file" >/dev/null
rg -n 'self\?\.executeShellCommand\(inputCopy\)' "$ghostty_file" >/dev/null

rg -n 'view\.rememberShellReplay\(initialInput: cmd\)' "$main_file" >/dev/null
rg -n 'view\.executeShellCommand\(cmd\)' "$main_file" >/dev/null

if rg -n 'ghostty_surface_text\(surface, cmd, UInt\(cmd\.utf8\.count\)\)' "$main_file" >/dev/null; then
  echo "preset run-in-current should use executeShellCommand instead of raw surface_text" >&2
  exit 1
fi
