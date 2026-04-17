#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage: scripts/sign-app-bundle.sh <app-bundle>

Environment:
  CTERM_CODESIGN_IDENTITY      Code signing identity. Defaults to ad-hoc signing (-).
  CTERM_CODESIGN_ENTITLEMENTS  Optional entitlements plist used for non ad-hoc signing.
EOF
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

if ! command -v codesign >/dev/null 2>&1; then
  echo "missing required tool: codesign" >&2
  exit 1
fi

app_bundle="$1"
identity="${CTERM_CODESIGN_IDENTITY:--}"
entitlements="${CTERM_CODESIGN_ENTITLEMENTS:-}"

if [[ ! -d "$app_bundle" ]]; then
  echo "app bundle not found: $app_bundle" >&2
  exit 1
fi

args=(--force --deep --sign "$identity")
if [[ "$identity" != "-" ]]; then
  args+=(--options runtime --timestamp)
  if [[ -n "$entitlements" ]]; then
    args+=(--entitlements "$entitlements")
  fi
fi

codesign "${args[@]}" "$app_bundle"
codesign --verify --deep --strict --verbose=2 "$app_bundle"
