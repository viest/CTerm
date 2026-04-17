#!/usr/bin/env bash
set -euo pipefail

file="macos/CTerm/GhosttyTerminalView.swift"

rg -n 'private func clampedMousePointForSurface\(from point: NSPoint\) -> NSPoint \{' "$file" >/dev/null
rg -n 'let drawableSize = surfaceDrawableSize\(from: bounds.size\)' "$file" >/dev/null
rg -n 'let clampedX = min\(max\(point.x, 0\), drawableSize.width\)' "$file" >/dev/null
rg -n 'let clampedY = min\(max\(point.y, 0\), drawableSize.height\)' "$file" >/dev/null
rg -n 'y: drawableSize.height - clampedY' "$file" >/dev/null
rg -n 'private func updateMousePosition\(for event: NSEvent, on surface: ghostty_surface_t\)' "$file" >/dev/null
rg -n 'let surfacePoint = clampedMousePointForSurface\(from: point\)' "$file" >/dev/null
rg -n 'ghostty_surface_mouse_pos\(surface, surfacePoint.x, surfacePoint.y, ghosttyMods\(event.modifierFlags\)\)' "$file" >/dev/null
rg -n 'updateMousePosition\(for: event, on: s\)' "$file" >/dev/null
