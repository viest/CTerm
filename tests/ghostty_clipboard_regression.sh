#!/usr/bin/env bash
set -euo pipefail

file="macos/CTerm/GhosttyTerminalView.swift"

rg -n 'private struct ClipboardItem \{' "$file" >/dev/null
rg -n 'private static func cleanedClipboardText\(_ text: String\) -> String \{' "$file" >/dev/null
rg -n 'private static func clipboardItems\(' "$file" >/dev/null
rg -n 'mime: String\(cString: mime\)' "$file" >/dev/null
rg -n 'data: String\(cString: data\)' "$file" >/dev/null
rg -n 'private static func pasteboardType\(for mime: String\) -> NSPasteboard.PasteboardType\? \{' "$file" >/dev/null
rg -n 'case "text/plain":' "$file" >/dev/null
rg -n 'return \.string' "$file" >/dev/null
rg -n 'case "text/html":' "$file" >/dev/null
rg -n 'return \.html' "$file" >/dev/null
rg -n 'let items = GhosttyTerminalView\.clipboardItems\(from: content, count: count\)' "$file" >/dev/null
rg -n 'let declaredTypes = items\.compactMap \{ GhosttyTerminalView\.pasteboardType\(for: \$0\.mime\) \}' "$file" >/dev/null
rg -n 'guard let type = GhosttyTerminalView\.pasteboardType\(for: item\.mime\) else \{ continue \}' "$file" >/dev/null
rg -n 'GhosttyTerminalView\.cleanedClipboardText\(item\.data\)' "$file" >/dev/null
rg -n 'pb.setString\(value, forType: type\)' "$file" >/dev/null
rg -n 'private func handlePasteboardContents\(\) -> Bool \{' "$file" >/dev/null
rg -n 'if let image = NSImage\(pasteboard: pb\),' "$file" >/dev/null
rg -n 'let path = saveImageToTemp\(image\)' "$file" >/dev/null
rg -n 'pb\.readObjects\(forClasses: \[NSURL\.self\], options: \[\.urlReadingFileURLsOnly: true\]\)' "$file" >/dev/null
rg -n 'pasteString\(urls\.map\(\\\.path\)\.joined\(separator: " "\)\)' "$file" >/dev/null
rg -n 'if event\.modifierFlags\.contains\(\.command\),' "$file" >/dev/null
rg -n 'event\.charactersIgnoringModifiers == "v"' "$file" >/dev/null
rg -n '@IBAction func paste\(_ sender: Any\?\) \{' "$file" >/dev/null
rg -n 'private func saveImageToTemp\(_ image: NSImage\) -> String\? \{' "$file" >/dev/null
rg -n 'bitmap\.representation\(using: \.png, properties: \[:\]\)' "$file" >/dev/null
rg -n 'appendingPathComponent\("cterm-images"\)' "$file" >/dev/null
