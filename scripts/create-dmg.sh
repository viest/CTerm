#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_app="$repo_root/build/CTerm.app"

usage() {
  cat <<'EOF' >&2
Usage: scripts/create-dmg.sh [--version VERSION] [--app APP_BUNDLE] [--output OUTPUT_DMG]

Options:
  --version VERSION   Release version or tag name to stamp into the app bundle.
  --app APP_BUNDLE    Path to the built .app bundle. Defaults to build/CTerm.app.
  --output OUTPUT     Output dmg path. Defaults to build/CTerm[-VERSION].dmg.
EOF
}

version=""
app_bundle="$default_app"
output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      version="$2"
      shift 2
      ;;
    --app)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      app_bundle="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      output="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

for tool in hdiutil plutil ditto; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "missing required tool: $tool" >&2
    exit 1
  fi
done

if [[ ! -d "$app_bundle" ]]; then
  echo "app bundle not found: $app_bundle" >&2
  exit 1
fi

version_core="${version#refs/tags/}"
version_core="${version_core#v}"

if [[ -z "$output" ]]; then
  if [[ -n "$version_core" ]]; then
    output="$repo_root/build/CTerm-$version_core.dmg"
  else
    output="$repo_root/build/CTerm.dmg"
  fi
fi

mkdir -p "$(dirname "$output")"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

stage_dir="$tmpdir/CTerm"
staged_app="$stage_dir/CTerm.app"
mkdir -p "$stage_dir"

ditto "$app_bundle" "$staged_app"
ln -s /Applications "$stage_dir/Applications"

if [[ -n "$version_core" ]]; then
  plist="$staged_app/Contents/Info.plist"
  plutil -replace CFBundleShortVersionString -string "$version_core" "$plist"
  plutil -replace CFBundleVersion -string "$version_core" "$plist"
fi

bash "$repo_root/scripts/sign-app-bundle.sh" "$staged_app"

volume_name="CTerm"
if [[ -n "$version_core" ]]; then
  volume_name="CTerm $version_core"
fi

rm -f "$output"
hdiutil create \
  -volname "$volume_name" \
  -srcfolder "$stage_dir" \
  -ov \
  -format UDZO \
  "$output" >/dev/null

echo "Created $output"
