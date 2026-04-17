#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/repack-zig-static-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/demo.c" <<'EOF'
int demo(void) {
    return 42;
}
EOF

clang -c "$tmpdir/demo.c" -o "$tmpdir/demo.o"
ar -rcs "$tmpdir/libdemo.a" "$tmpdir/demo.o"

bash "$script" "$tmpdir/libdemo.a"

members="$(ar -t "$tmpdir/libdemo.a")"
if [[ "$members" != *"demo.o"* ]]; then
  echo "expected repacked archive to contain demo.o" >&2
  exit 1
fi

if ! nm -gU "$tmpdir/libdemo.a" | grep -q '_demo'; then
  echo "expected repacked archive to export _demo" >&2
  exit 1
fi
