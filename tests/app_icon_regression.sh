#!/usr/bin/env bash
set -euo pipefail

makefile="Makefile"
plist="macos/Resources/Info.plist"
script="scripts/generate_app_icon.swift"
icon_png="macos/Resources/AppIcon-1024.png"

test -f "$icon_png"
test -s "$icon_png"

rg -n '^ICON_SOURCE = macos/Resources/AppIcon-1024\.png$' "$makefile" >/dev/null
rg -n '^ICON_FILE = \$\(BUILD_DIR\)/AppIcon\.icns$' "$makefile" >/dev/null
rg -n 'iconutil -c icns \$\(ICONSET_DIR\) -o \$\(ICON_FILE\)' "$makefile" >/dev/null
rg -n '@cp \$\(ICON_FILE\) \$\(APP_BUNDLE\)/Contents/Resources/AppIcon\.icns' "$makefile" >/dev/null

rg -n '<key>CFBundleIconFile</key>' "$plist" >/dev/null
rg -n '<string>AppIcon</string>' "$plist" >/dev/null

rg -n 'let outputPath = "macos/Resources/AppIcon-1024\.png"' "$script" >/dev/null
rg -n 'NSFont\.monospacedSystemFont\(ofSize: 210, weight: \.bold\)' "$script" >/dev/null
rg -n 'let promptOrigin = CGPoint\(x: 350, y: 336\)' "$script" >/dev/null
rg -n 'NSAttributedString\(string: ">", attributes: promptAccentAttributes\)\.draw\(at: promptOrigin\)' "$script" >/dev/null
rg -n 'NSAttributedString\(string: "_", attributes: promptAttributes\)\.draw\(at: CGPoint\(x: promptOrigin\.x \+ 154, y: promptOrigin\.y\)\)' "$script" >/dev/null
! rg -n 'NSShadow' "$script" >/dev/null
! rg -n 'NSGradient' "$script" >/dev/null
! rg -n 'topAccentRect|bottomAccentRect' "$script" >/dev/null
! rg -n 'terminalRect|terminalPath|headerHeight|dotColors|dividerX' "$script" >/dev/null
! rg -n 'branchPath|branchColor|branchOrigin|branchScale|branchPoint|nodePositions' "$script" >/dev/null
