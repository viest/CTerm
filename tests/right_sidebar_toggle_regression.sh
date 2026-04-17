#!/usr/bin/env bash
set -euo pipefail

main_file="macos/CTerm/MainWindowController.swift"
ghostty_file="macos/CTerm/GhosttyTerminalView.swift"

rg -n 'private var rightSidebarAnimating = false' "$main_file" >/dev/null
rg -n 'private var rightSidebarAnimationGeneration = 0' "$main_file" >/dev/null
rg -n 'updateRightSidebarVisibility\(animated: !rightSidebarAnimating\)' "$main_file" >/dev/null
rg -n 'terminalContentView\.layer\?\.masksToBounds = true' "$main_file" >/dev/null
rg -n 'terminalContentView\.trailingAnchor\.constraint\(equalTo: rightSidebarContainer\.leadingAnchor\)' "$main_file" >/dev/null
if rg -n 'terminalContentView\.trailingAnchor\.constraint\(equalTo: centerContainer\.trailingAnchor\)' "$main_file" >/dev/null; then
  echo "terminal content should shrink with the right sidebar" >&2
  exit 1
fi
rg -n 'let generation = rightSidebarAnimationGeneration' "$main_file" >/dev/null
rg -n 'if rightSidebarVisible \{' "$main_file" >/dev/null
rg -n 'rightSidebarContainer\.isHidden = false' "$main_file" >/dev/null
rg -n 'guard generation == self\.rightSidebarAnimationGeneration else \{ return \}' "$main_file" >/dev/null
rg -n 'self\.rightSidebarContainer\.isHidden = !self\.rightSidebarVisible' "$main_file" >/dev/null
rg -n 'completionHandler: finalize' "$main_file" >/dev/null
rg -n 'updateRightSidebarVisibility\(animated: false\)' "$main_file" >/dev/null

rg -n 'private var lastSurfaceSizePx: \(width: UInt32, height: UInt32\)\?' "$ghostty_file" >/dev/null
rg -n 'private func applySurfaceSize\(_ size: NSSize, to surface: ghostty_surface_t\)' "$ghostty_file" >/dev/null
rg -n 'if let lastSurfaceSizePx, lastSurfaceSizePx\.width == width, lastSurfaceSizePx\.height == height \{' "$ghostty_file" >/dev/null
rg -n 'ghostty_surface_set_size\(surface, width, height\)' "$ghostty_file" >/dev/null
