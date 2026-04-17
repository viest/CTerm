#!/usr/bin/env bash
set -euo pipefail

makefile="Makefile"
script="scripts/sign-app-bundle.sh"

rg -n '^app: swift \$\(ICON_FILE\)$' "$makefile" >/dev/null
rg -n '^dev: \$\(ICON_FILE\)$' "$makefile" >/dev/null
rg -n '^APP_STAGING_BUNDLE = \$\(BUILD_DIR\)/\$\(APP_NAME\)\.staging\.app$' "$makefile" >/dev/null
rg -n '^APP_PREVIOUS_BUNDLE = \$\(BUILD_DIR\)/\$\(APP_NAME\)\.previous\.app$' "$makefile" >/dev/null
rg -n 'cp \$\(BUILD_DIR\)/\$\(APP_NAME\) \$\(APP_STAGING_BUNDLE\)/Contents/MacOS/' "$makefile" >/dev/null
rg -n 'bash \./scripts/sign-app-bundle\.sh "\$\(APP_STAGING_BUNDLE\)"' "$makefile" >/dev/null
rg -n 'rm -rf \$\(APP_PREVIOUS_BUNDLE\)' "$makefile" >/dev/null
rg -n 'if \[ -d "\$\(APP_BUNDLE\)" \]; then mv "\$\(APP_BUNDLE\)" "\$\(APP_PREVIOUS_BUNDLE\)"; fi' "$makefile" >/dev/null
rg -n 'mv "\$\(APP_STAGING_BUNDLE\)" "\$\(APP_BUNDLE\)"' "$makefile" >/dev/null

rg -n '^Usage: scripts/sign-app-bundle\.sh <app-bundle>$' "$script" >/dev/null
rg -n '^  CTERM_CODESIGN_IDENTITY      Code signing identity\. Defaults to ad-hoc signing \(-\)\.$' "$script" >/dev/null
rg -n '^identity="\$\{CTERM_CODESIGN_IDENTITY:--\}"$' "$script" >/dev/null
rg -n '^entitlements="\$\{CTERM_CODESIGN_ENTITLEMENTS:-\}"$' "$script" >/dev/null
rg -n '^args=\(--force --deep --sign "\$identity"\)$' "$script" >/dev/null
rg -n '^  args\+=\(--options runtime --timestamp\)$' "$script" >/dev/null
rg -n '^    args\+=\(--entitlements "\$entitlements"\)$' "$script" >/dev/null
rg -n '^codesign "\$\{args\[@\]\}" "\$app_bundle"$' "$script" >/dev/null
rg -n '^codesign --verify --deep --strict --verbose=2 "\$app_bundle"$' "$script" >/dev/null
