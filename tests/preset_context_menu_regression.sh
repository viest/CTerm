#!/usr/bin/env bash
set -euo pipefail

preset_file="macos/CTerm/PresetBarView.swift"

rg -n 'private let contextPopover = PresetContextPopover\(\)' "$preset_file" >/dev/null
rg -n 'contextPopover\.show\(' "$preset_file" >/dev/null
rg -n 'popover\.behavior = \.transient' "$preset_file" >/dev/null
rg -n 'popover\.appearance = NSAppearance\(named: \.darkAqua\)' "$preset_file" >/dev/null
rg -n 'containerView\.layer\?\.backgroundColor = AppTheme\.bgSecondary\.cgColor' "$preset_file" >/dev/null
rg -n 'containerView\.layer\?\.borderColor = AppTheme\.border\.cgColor' "$preset_file" >/dev/null
rg -n 'containerView\.layer\?\.cornerRadius = 8' "$preset_file" >/dev/null
rg -n 'actionsStack\.alignment = \.width' "$preset_file" >/dev/null
rg -n 'PresetContextActionButton\(' "$preset_file" >/dev/null
rg -n 'titleLabel\.alignment = \.left' "$preset_file" >/dev/null
rg -n 'title: "Run in Current Terminal"' "$preset_file" >/dev/null
rg -n 'title: "Open in New Tab"' "$preset_file" >/dev/null
rg -n 'title: "Open in Split Pane"' "$preset_file" >/dev/null

if rg -n 'let menu = NSMenu\(\)|NSMenuItem\(' "$preset_file" >/dev/null; then
    echo "preset context menu should use the custom popover instead of NSMenu" >&2
    exit 1
fi
