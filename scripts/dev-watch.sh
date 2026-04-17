#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_bundle="$repo_root/build/CTerm.app"
previous_app_bundle="$repo_root/build/CTerm.previous.app"
watch_log="$repo_root/build/cterm-watch.log"

usage() {
  cat <<'EOF'
Usage: scripts/dev-watch.sh [--run-once]

Options:
  --run-once   Build and relaunch once without starting the watcher.
  -h, --help   Show this help text.
EOF
}

run_cycle() {
  (
    cd "$repo_root"
    make dev

    # macOS truncates each process's COMM to 16 chars and prefixes it with
    # argv[0], so an app launched from /Applications/CTerm.app shows up as
    # "/Applications/CT" — pkill -x CTerm silently fails to match it.
    # Use pattern matching on the full argv instead, and ask the running
    # app to quit first so unsaved state has a chance to flush.
    osascript -e 'tell application id "com.cterm.app" to quit' >/dev/null 2>&1 || true
    pkill -f "CTerm\.app/Contents/MacOS/CTerm" >/dev/null 2>&1 || true

    # Give it a moment to exit; then force-kill anything still alive so the
    # subsequent `open` launches our dev bundle instead of foregrounding a
    # stale /Applications/CTerm.app instance.
    for _ in 1 2 3 4 5; do
      pgrep -f "CTerm\.app/Contents/MacOS/CTerm" >/dev/null 2>&1 || break
      sleep 0.2
    done
    pkill -9 -f "CTerm\.app/Contents/MacOS/CTerm" >/dev/null 2>&1 || true

    rm -rf "$previous_app_bundle"
    mkdir -p "$(dirname "$watch_log")"
    printf '\n[%s] launch %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$app_bundle" >>"$watch_log"
    # -n forces a new instance bound to the given bundle path so LaunchServices
    # can't redirect us to a stale /Applications/CTerm.app registration.
    if ! open -n --stdout "$watch_log" --stderr "$watch_log" "$app_bundle"; then
      echo "warning: failed to launch $app_bundle" >&2
    fi
  )
}

require_watchexec() {
  if ! command -v watchexec >/dev/null 2>&1; then
    echo "watchexec is required for live rebuilds." >&2
    echo "Install it with: brew install watchexec" >&2
    exit 1
  fi
}

watch() {
  require_watchexec

  mkdir -p "$(dirname "$watch_log")"
  touch "$watch_log"
  tail -n 0 -F "$watch_log" &
  tail_pid=$!
  trap 'kill "$tail_pid" >/dev/null 2>&1 || true' EXIT

  run_cycle

  (
    cd "$repo_root"
    watchexec \
      --postpone \
      --watch src \
      --watch macos/CTerm \
      --watch include \
      --watch macos/Resources/Info.plist \
      --ignore .git \
      --ignore build \
      --ignore zig-out \
      --ignore .zig-cache \
      --restart \
      --delay-run 200ms \
      -- "$0" --run-once
  )
}

case "${1:-}" in
  --run-once)
    run_cycle
    ;;
  -h|--help)
    usage
    ;;
  "")
    watch
    ;;
  *)
    echo "unknown option: $1" >&2
    usage >&2
    exit 1
    ;;
esac
