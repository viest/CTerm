#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/dev-watch.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "expected output to contain: $needle" >&2
    echo "--- output ---" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

wait_for_log() {
  local log_file="$1"
  local needle="$2"
  local output=""

  for _ in $(seq 1 20); do
    output="$(cat "$log_file")"
    if [[ "$output" == *"$needle"* ]]; then
      printf '%s' "$output"
      return 0
    fi
    sleep 0.05
  done

  printf '%s' "$output"
  return 1
}

mkdir -p "$tmpdir/bin"
base_path="/usr/bin:/bin:/usr/sbin:/sbin"

missing_output="$(
  PATH="$tmpdir/bin:$base_path" /bin/bash "$script" 2>&1 || true
)"
assert_contains "$missing_output" "watchexec is required"
assert_contains "$missing_output" "brew install watchexec"

cat >"$tmpdir/bin/make" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "make:$*" >>"$DEV_WATCH_LOG"
EOF

cat >"$tmpdir/bin/pkill" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "pkill:$*" >>"$DEV_WATCH_LOG"
EOF

cat >"$tmpdir/bin/open" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "open:$*" >>"$DEV_WATCH_LOG"
EOF

cat >"$tmpdir/bin/tail" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "tail:$*" >>"$DEV_WATCH_LOG"
EOF

cat >"$tmpdir/bin/watchexec" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "watchexec:$*" >>"$DEV_WATCH_LOG"
EOF

chmod +x "$tmpdir/bin/make" "$tmpdir/bin/pkill" "$tmpdir/bin/open" "$tmpdir/bin/tail" "$tmpdir/bin/watchexec"

log="$tmpdir/dev-watch.log"
: >"$log"

PATH="$tmpdir/bin:$base_path" DEV_WATCH_LOG="$log" /bin/bash "$script" --run-once

log_output="$(wait_for_log "$log" "open:--stdout $repo_root/build/cterm-watch.log --stderr $repo_root/build/cterm-watch.log $repo_root/build/CTerm.app")"
assert_contains "$log_output" "make:dev"
assert_contains "$log_output" "pkill:-x CTerm"
assert_contains "$log_output" "open:--stdout $repo_root/build/cterm-watch.log --stderr $repo_root/build/cterm-watch.log $repo_root/build/CTerm.app"

: >"$log"
PATH="$tmpdir/bin:$base_path" DEV_WATCH_LOG="$log" /bin/bash "$script"
log_output="$(wait_for_log "$log" "watchexec:")"
assert_contains "$log_output" "tail:-n 0 -F $repo_root/build/cterm-watch.log"
assert_contains "$log_output" "watchexec:"
assert_contains "$log_output" "--postpone"
assert_contains "$log_output" "--watch src"
assert_contains "$log_output" "--watch macos/CTerm"
assert_contains "$log_output" "--watch include"
assert_contains "$log_output" "--watch macos/Resources/Info.plist"
assert_contains "$log_output" "--ignore .git"
assert_contains "$log_output" "--ignore build"
