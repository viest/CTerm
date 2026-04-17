#!/usr/bin/env bash
set -euo pipefail

main_file="macos/CTerm/MainWindowController.swift"
preset_bar_file="macos/CTerm/PresetBarView.swift"

rg -n 'private func normalizedTerminalLaunch\(command: String, initialInput: String\?\) -> \(command: String, initialInput: String\?\)' "$main_file" >/dev/null
rg -n 'if trimmedCommand\.contains\(where: \{ \$0\.isWhitespace \}\) \{' "$main_file" >/dev/null
rg -n 'return \("/bin/zsh", trimmedCommand \+ "\\n"\)' "$main_file" >/dev/null
rg -n 'let launch = normalizedTerminalLaunch\(command: command, initialInput: initialInput\)' "$main_file" >/dev/null
rg -n 'command: launch\.command' "$main_file" >/dev/null
rg -n 'initialInput: launch\.initialInput' "$main_file" >/dev/null
rg -n 'func presetSelected\(_ preset: AgentPresetItem\)' "$main_file" >/dev/null
rg -n 'addTerminalTab\(title: preset\.name, command: preset\.command, workingDir: workDir\)' "$main_file" >/dev/null
rg -n 'func presetOpenInSplit\(_ preset: AgentPresetItem\)' "$main_file" >/dev/null
rg -n 'splitLeaf\(fId, direction: \.horizontal, newId: newId, newView: newView\)' "$main_file" >/dev/null
rg -n 'Open in New Tab' "$preset_bar_file" >/dev/null
rg -n 'Open in Split Pane' "$preset_bar_file" >/dev/null
rg -n 'contextPopover\.show\(' "$preset_bar_file" >/dev/null
rg -n 'self\?\.delegate\?\.presetOpenInSplit\(preset\)' "$preset_bar_file" >/dev/null

if rg -n 'shouldRunPresetInFocusedPane' "$main_file" >/dev/null; then
    echo "preset left-click should always open a new tab" >&2
    exit 1
fi

if sed -n '/let termView = GhosttyTerminalView(/,/)/p' "$main_file" | rg -n 'command: command,|initialInput: initialInput' >/dev/null; then
    echo "terminal launch should normalize shell commands before creating GhosttyTerminalView" >&2
    exit 1
fi
