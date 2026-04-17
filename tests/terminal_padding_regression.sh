#!/usr/bin/env bash
set -euo pipefail

split_file="macos/CTerm/SplitContainerView.swift"
ghostty_file="macos/CTerm/GhosttyTerminalView.swift"
main_window_file="macos/CTerm/MainWindowController.swift"

rg -n 'private static let leafInset: CGFloat = 8' "$split_file" >/dev/null
rg -n 'private static let surfaceRightGuardPoints: CGFloat = 8' "$ghostty_file" >/dev/null
rg -n 'static var defaultBackgroundColor: NSColor' "$ghostty_file" >/dev/null
rg -n 'static func backgroundColor\(for settings: AppSettings\) -> NSColor' "$ghostty_file" >/dev/null
rg -n 'layer\?\.backgroundColor = Self\.backgroundColor\(for: SettingsManager\.shared\.settings\)\.cgColor' "$ghostty_file" >/dev/null
rg -n 'layer\?\.backgroundColor = GhosttyTerminalView\.defaultBackgroundColor\.cgColor' "$split_file" >/dev/null
rg -n 'terminalContentView\.layer\?\.backgroundColor = GhosttyTerminalView\.defaultBackgroundColor\.cgColor' "$main_window_file" >/dev/null
rg -n 'private func surfaceDrawableSize\(from size: NSSize\) -> NSSize' "$ghostty_file" >/dev/null
rg -n 'size\.width - Self\.surfaceRightGuardPoints' "$ghostty_file" >/dev/null
rg -n 'private func clampedBackingPoint\(from point: NSPoint\) -> NSPoint' "$ghostty_file" >/dev/null
rg -n 'let backed = clampedBackingPoint\(from: pt\)' "$ghostty_file" >/dev/null
rg -n 'view\.translatesAutoresizingMaskIntoConstraints = false' "$split_file" >/dev/null
rg -n 'view\.leadingAnchor\.constraint\(equalTo: leadingAnchor, constant: Self\.leafInset\)' "$split_file" >/dev/null
rg -n 'view\.bottomAnchor\.constraint\(equalTo: bottomAnchor, constant: -Self\.leafInset\)' "$split_file" >/dev/null
if rg -n 'leafFrame\(for: bounds\)' "$split_file" >/dev/null; then
  echo "terminal padding should be driven by constraints instead of manual frame math" >&2
  exit 1
fi
