#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage: scripts/repack-zig-static-lib.sh <archive>
EOF
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

for tool in ar libtool ranlib; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "missing required tool: $tool" >&2
    exit 1
  fi
done

archive_input="$1"
archive_dir="$(cd "$(dirname "$archive_input")" && pwd)"
archive="$archive_dir/$(basename "$archive_input")"

if [[ ! -f "$archive" ]]; then
  echo "archive not found: $archive" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

cp "$archive" "$tmpdir/input.a"

(
  cd "$tmpdir"
  ar -x input.a

  shopt -s nullglob
  members=()
  for member in *; do
    case "$member" in
      "__.SYMDEF"|"__.SYMDEF SORTED"|"input.a")
        continue
        ;;
    esac
    chmod u+rw "$member"
    members+=("$member")
  done

  if [[ ${#members[@]} -eq 0 ]]; then
    echo "archive has no repackable members: $archive" >&2
    exit 1
  fi

  libtool -static -o output.a "${members[@]}"
  ranlib output.a
)

mv "$tmpdir/output.a" "$archive"
