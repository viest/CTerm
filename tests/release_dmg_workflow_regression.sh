#!/usr/bin/env bash
set -euo pipefail

makefile="Makefile"
workflow=".github/workflows/release-dmg.yml"
script="scripts/create-dmg.sh"

rg -n '^\.PHONY: .*dmg' "$makefile" >/dev/null
rg -n '^DMG_OUTPUT = \$\(BUILD_DIR\)/\$\(APP_NAME\)\.dmg$' "$makefile" >/dev/null
rg -n '^dmg: app$' "$makefile" >/dev/null
rg -n 'scripts/create-dmg\.sh --app "\$\(APP_BUNDLE\)" --output "\$\(DMG_OUTPUT\)"' "$makefile" >/dev/null

rg -n '^name: Build Release DMG$' "$workflow" >/dev/null
rg -n '^on:$' "$workflow" >/dev/null
rg -n '^  push:$' "$workflow" >/dev/null
rg -n "^      - '\\*'$" "$workflow" >/dev/null
rg -n '^permissions:$' "$workflow" >/dev/null
rg -n '^  contents: write$' "$workflow" >/dev/null
rg -n '^    runs-on: macos-14$' "$workflow" >/dev/null
rg -n 'uses: actions/checkout@v4' "$workflow" >/dev/null
rg -n 'lfs: true' "$workflow" >/dev/null
rg -n 'run: git lfs pull' "$workflow" >/dev/null
rg -n 'uses: mlugg/setup-zig@v2' "$workflow" >/dev/null
rg -n 'version: 0.16.0' "$workflow" >/dev/null
rg -n '^      - name: Verify Zig toolchain$' "$workflow" >/dev/null
rg -n '^        run: zig version$' "$workflow" >/dev/null
rg -n 'run: make app' "$workflow" >/dev/null
rg -n 'bash \./scripts/create-dmg\.sh --version "\$TAG_NAME"' "$workflow" >/dev/null
rg -n 'uses: actions/upload-artifact@v4' "$workflow" >/dev/null
rg -n 'path: build/CTerm-\*\.dmg' "$workflow" >/dev/null
rg -n 'gh release upload "\$TAG_NAME" "\$DMG_PATH" --clobber' "$workflow" >/dev/null
rg -n 'gh release create "\$TAG_NAME" "\$DMG_PATH" --title "\$TAG_NAME" --generate-notes' "$workflow" >/dev/null

rg -n '^Usage: scripts/create-dmg\.sh \[--version VERSION\] \[--app APP_BUNDLE\] \[--output OUTPUT_DMG\]$' "$script" >/dev/null
rg -n 'for tool in hdiutil plutil ditto; do' "$script" >/dev/null
rg -n 'version_core="\$\{version#refs/tags/\}"' "$script" >/dev/null
rg -n 'version_core="\$\{version_core#v\}"' "$script" >/dev/null
rg -n 'ditto "\$app_bundle" "\$staged_app"' "$script" >/dev/null
rg -n 'ln -s /Applications "\$stage_dir/Applications"' "$script" >/dev/null
rg -n 'plutil -replace CFBundleShortVersionString -string "\$version_core" "\$plist"' "$script" >/dev/null
rg -n 'plutil -replace CFBundleVersion -string "\$version_core" "\$plist"' "$script" >/dev/null
rg -n 'bash "\$repo_root/scripts/sign-app-bundle\.sh" "\$staged_app"' "$script" >/dev/null
rg -n 'hdiutil create \\' "$script" >/dev/null
rg -n 'Created \$output' "$script" >/dev/null
