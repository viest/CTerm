#!/usr/bin/env bash
set -euo pipefail

file="macos/CTerm/SettingsWindow.swift"
main_file="macos/CTerm/MainWindowController.swift"
app_delegate_file="macos/CTerm/AppDelegate.swift"
general_tab_file="macos/CTerm/SettingsGeneralTab.swift"
agents_tab_file="macos/CTerm/SettingsAgentsTab.swift"
terminal_tab_file="macos/CTerm/SettingsTerminalTab.swift"
shortcuts_tab_file="macos/CTerm/SettingsShortcutsTab.swift"
centered_field_file="macos/CTerm/VerticallyCenteredTextField.swift"
ghostty_file="macos/CTerm/GhosttyTerminalView.swift"
split_container_file="macos/CTerm/SplitContainerView.swift"

# Settings windows must stay attached to the main window so closing the app
# window does not leave the settings window behind.
rg -n 'SettingsWindow: NSObject, NSWindowDelegate' "$file" >/dev/null
rg -n 'private let window: NSWindow' "$file" >/dev/null
rg -n 'private weak var parentWindow: NSWindow\?' "$file" >/dev/null
rg -n 'window\.delegate = self' "$file" >/dev/null
rg -n 'func present\(attachedTo parentWindow: NSWindow\?\)' "$file" >/dev/null
rg -n 'parentWindow\.addChildWindow\(window, ordered: \.above\)' "$file" >/dev/null
rg -n 'func close\(\)' "$file" >/dev/null
rg -n 'func windowWillClose\(_ notification: Notification\)' "$file" >/dev/null
rg -n 'parentWindow\?\.removeChildWindow\(window\)' "$file" >/dev/null
rg -n 'window\.makeKeyAndOrderFront\(nil\)' "$file" >/dev/null
rg -n 'window\.orderFrontRegardless\(\)' "$file" >/dev/null
rg -n 'NSApplication\.shared\.activate\(ignoringOtherApps: true\)' "$file" >/dev/null
rg -n 'window\.isMovableByWindowBackground = false' "$file" >/dev/null
rg -n 'private var settingsWindow: SettingsWindow\?' "$main_file" >/dev/null
rg -n 'private var projectPresets: \[AgentPresetItem\] = \[\]' "$main_file" >/dev/null
rg -n 'settingsWindow = SettingsWindow\(\)' "$main_file" >/dev/null
rg -n 'settingsWindow\?\.onPresetsChanged = \{ \[weak self\] presets in' "$main_file" >/dev/null
rg -n 'window\.delegate = self' "$main_file" >/dev/null
rg -n 'settingsWindow\?\.present\(attachedTo: window\)' "$main_file" >/dev/null
rg -n 'settingsWindow\?\.close\(\)' "$main_file" >/dev/null
rg -n 'settingsWindow = nil' "$main_file" >/dev/null
rg -n '@objc func showSettings\(_ sender: Any\?\)' "$main_file" >/dev/null
rg -n 'window\.isMovableByWindowBackground = false' "$main_file" >/dev/null
rg -n 'private func visibleTopBarPresets\(from presets: \[AgentPresetItem\]\) -> \[AgentPresetItem\]' "$main_file" >/dev/null
rg -n 'presets\.filter\(\\\.pinned\)' "$main_file" >/dev/null
rg -n 'private func refreshPresetBarPresets\(\)' "$main_file" >/dev/null
rg -n 'let mergedPresets = projectPresets \+ presets' "$main_file" >/dev/null
rg -n 'presetBar\?\.setPresets\(visibleTopBarPresets\(from: mergedPresets\)\)' "$main_file" >/dev/null
rg -n 'let settingsItem = NSMenuItem\(title: "Settings\.\.\.", action: #selector\(showSettings\(_:\)\), keyEquivalent: ","\)' "$app_delegate_file" >/dev/null
rg -n 'settingsItem\.target = self' "$app_delegate_file" >/dev/null
rg -n 'mainWindowController\?\.showSettings\(sender\)' "$app_delegate_file" >/dev/null
rg -n 'private let contentWidth: CGFloat = 520' "$general_tab_file" >/dev/null
rg -n 'private let detailWidth: CGFloat = 344' "$agents_tab_file" >/dev/null
rg -n 'private let contentWidth: CGFloat = 520' "$terminal_tab_file" >/dev/null
rg -n 'SettingsManager\.shared\.onSettingsChanged = \{ \[weak self\] in' "$main_file" >/dev/null
rg -n 'private func applyTerminalSettingsToAllPanes\(\)' "$main_file" >/dev/null
rg -n 'GhosttyTerminalView\.applySharedSettings\(settings\)' "$main_file" >/dev/null
rg -n 'leaf\.view\.applyTerminalSettings\(settings\)' "$main_file" >/dev/null
rg -n 'container\.applyTerminalThemeBackground\(settings\)' "$main_file" >/dev/null
rg -n 'final class VerticallyCenteredTextField: NSTextField' "$centered_field_file" >/dev/null
rg -n 'func makeSettingsTextFieldContainer\(for textField: NSTextField, width: CGFloat\? = nil, height: CGFloat = 24\) -> NSView' "$centered_field_file" >/dev/null
rg -n 'drawsBackground = false' "$centered_field_file" >/dev/null
rg -n 'backgroundColor = \.clear' "$centered_field_file" >/dev/null
rg -n 'cell\?\.isScrollable = true' "$centered_field_file" >/dev/null
rg -n 'container\.layer\?\.backgroundColor = AppTheme\.bgTertiary\.cgColor' "$centered_field_file" >/dev/null
rg -n 'setContentHuggingPriority\(\.defaultLow, for: \.horizontal\)' "$centered_field_file" >/dev/null
rg -n 'VerticallyCenteredTextField\(\)' "$general_tab_file" >/dev/null
rg -n 'VerticallyCenteredTextField\(\)' "$agents_tab_file" >/dev/null
rg -n 'VerticallyCenteredTextField\(\)' "$terminal_tab_file" >/dev/null
rg -n 'makeSettingsTextFieldContainer\(for: worktreeDirField\)' "$general_tab_file" >/dev/null
rg -n 'makeSettingsTextFieldContainer\(for: fontSizeField, width: 50\)' "$terminal_tab_file" >/dev/null
rg -n 'makeSettingsTextFieldContainer\(for: scrollbackField, width: 90\)' "$terminal_tab_file" >/dev/null
rg -n 'widthAnchor\.constraint\(equalToConstant: contentWidth\)' "$general_tab_file" >/dev/null
rg -n 'private let cellHorizontalInset: CGFloat = 10' "$shortcuts_tab_file" >/dev/null
rg -n 'func tableView\(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn\?, row: Int\) -> NSView\?' "$shortcuts_tab_file" >/dev/null
rg -n 'return makeCellLabel\(entry\.currentShortcut' "$shortcuts_tab_file" >/dev/null
rg -n 'return makeCellLabel\(entry\.defaultShortcut' "$shortcuts_tab_file" >/dev/null
rg -n 'label\.leadingAnchor\.constraint\(equalTo: cell\.leadingAnchor, constant: cellHorizontalInset\)' "$shortcuts_tab_file" >/dev/null
! rg -n 'alignment = \.center' "$shortcuts_tab_file" >/dev/null
rg -n 'tableView\.selectRowIndexes\(IndexSet\(integer: 0\), byExtendingSelection: false\)' "$agents_tab_file" >/dev/null
rg -n 'SettingsAgentsFlippedView' "$agents_tab_file" >/dev/null
rg -n 'private final class SettingsAgentsRowView: NSTableRowView' "$agents_tab_file" >/dev/null
rg -n 'AppTheme\.accent\.setFill\(\)' "$agents_tab_file" >/dev/null
rg -n 'func tableView\(_ tableView: NSTableView, rowViewForRow row: Int\) -> NSTableRowView\?' "$agents_tab_file" >/dev/null
rg -n 'detailScroll\.contentView\.widthAnchor' "$agents_tab_file" >/dev/null
rg -n 'docView\.heightAnchor\.constraint\(greaterThanOrEqualTo: detailScroll\.contentView\.heightAnchor\)' "$agents_tab_file" >/dev/null
rg -n 'docView\.bottomAnchor\.constraint\(greaterThanOrEqualTo: detailStack\.bottomAnchor, constant: detailInset\)' "$agents_tab_file" >/dev/null
rg -n 'makeBarButton\("\+", action: #selector\(addAgent\), width: 28\)' "$agents_tab_file" >/dev/null
rg -n 'makeBarButton\("\\u\{2212\}", action: #selector\(removeAgent\), width: 28\)' "$agents_tab_file" >/dev/null
rg -n 'makeBarButton\("Reset", action: #selector\(resetDefaults\)\)' "$agents_tab_file" >/dev/null
rg -n 'barSpacer\.setContentHuggingPriority\(\.defaultLow, for: \.horizontal\)' "$agents_tab_file" >/dev/null
rg -n 'barSpacer\.setContentCompressionResistancePriority\(\.defaultLow, for: \.horizontal\)' "$agents_tab_file" >/dev/null
rg -n 'private var showInTopBarSwitch: NSSwitch!' "$agents_tab_file" >/dev/null
rg -n 'let cell = NSView\(\)' "$agents_tab_file" >/dev/null
rg -n 'label\.centerYAnchor\.constraint\(equalTo: cell\.centerYAnchor\)' "$agents_tab_file" >/dev/null
rg -n 'if let textField = field as\? NSTextField' "$agents_tab_file" >/dev/null
rg -n 'makeSettingsTextFieldContainer\(for: textField, width: width\)' "$agents_tab_file" >/dev/null
rg -n 'makeLabeledField\("Description"' "$agents_tab_file" >/dev/null
rg -n 'detailStack\.addArrangedSubview\(makeSwitchRow\("Show in top bar", sw: showInTopBarSwitch\)\)' "$agents_tab_file" >/dev/null
rg -n 'showInTopBarSwitch\.isEnabled = enabled' "$agents_tab_file" >/dev/null
rg -n 'showInTopBarSwitch\.state = preset\.pinned \? \.on : \.off' "$agents_tab_file" >/dev/null
rg -n 'presets\[row\]\.pinned = showInTopBarSwitch\.state == \.on' "$agents_tab_file" >/dev/null
rg -n 'private func makeBarButton\(_ title: String, action: Selector, width: CGFloat\? = nil\) -> NSButton' "$agents_tab_file" >/dev/null
rg -n 'btn\.setContentHuggingPriority\(\.required, for: \.horizontal\)' "$agents_tab_file" >/dev/null
rg -n 'btn\.setContentCompressionResistancePriority\(\.required, for: \.horizontal\)' "$agents_tab_file" >/dev/null
! rg -n 'Command with prompt' "$agents_tab_file" >/dev/null
! rg -n 'resetBtn\.widthAnchor\.constraint\(equalToConstant: 50\)' "$agents_tab_file" >/dev/null
rg -n 'private weak var agentsTab: SettingsAgentsTab\?' "$file" >/dev/null
rg -n 'var onPresetsChanged: \(\(\[AgentPresetItem\]\) -> Void\)\?' "$file" >/dev/null
rg -n 'agentsTab\?\.onPresetsChanged = onPresetsChanged' "$file" >/dev/null
rg -n 'self\.agentsTab = agentsTab' "$file" >/dev/null
rg -n 'static func applySharedSettings\(_ settings: AppSettings\)' "$ghostty_file" >/dev/null
rg -n 'func applyTerminalSettings\(_ settings: AppSettings\)' "$ghostty_file" >/dev/null
rg -n 'ghostty_app_update_config\(app, cfg\)' "$ghostty_file" >/dev/null
rg -n 'ghostty_surface_update_config\(surface, cfg\)' "$ghostty_file" >/dev/null
rg -n 'scfg\.font_size = Float\(settings\.fontSize\)' "$ghostty_file" >/dev/null
rg -n 'font-family = ' "$ghostty_file" >/dev/null
rg -n 'font-size = ' "$ghostty_file" >/dev/null
rg -n 'cursor-style = ' "$ghostty_file" >/dev/null
rg -n 'scrollback-limit = ' "$ghostty_file" >/dev/null
rg -n 'selection-background = ' "$ghostty_file" >/dev/null
rg -n 'func applyTerminalThemeBackground\(_ settings: AppSettings\)' "$split_container_file" >/dev/null
rg -n 'GhosttyTerminalView\.backgroundColor\(for: settings\)' "$split_container_file" >/dev/null
rg -n 'widthAnchor\.constraint\(equalToConstant: contentWidth\)' "$terminal_tab_file" >/dev/null
! rg -n 'widthAnchor\.constraint\(equalTo: parent\.widthAnchor\)' "$general_tab_file" >/dev/null
! rg -n 'widthAnchor\.constraint\(equalTo: parent\.widthAnchor\)' "$terminal_tab_file" >/dev/null
! rg -n 'availableFontFamilies|availableMembers\(ofFontFamily:' "$terminal_tab_file" >/dev/null
